import Foundation
import RunnerKit

/// Something that happened to this machine while the app was watching.
///
/// A closed list, and a short one. Two days of real data on the runner this was
/// built against held 14 `Succeeded`, 2 `Canceled` and 1 `Failed` across 17
/// jobs — so an event per job would be eight interruptions a day, of which
/// roughly one in six carries any information. What is here is what a person
/// cannot find out by any other means than looking: a build that broke, and a
/// runner that stopped taking work. The rest is in the menu, which is where
/// something you would only glance at belongs.
enum FleetEvent: Equatable {
  /// A job this runner finished with `Failed`.
  case jobFailed(runner: String, job: String)
  /// The service is up and GitHub cannot see it. The silent failure this whole
  /// app exists for: nothing on the machine looks wrong and no work arrives.
  case runnerDisconnected(runner: String)
  /// The LaunchAgent went down, and not because anybody here asked it to.
  case runnerStoppedUnexpectedly(runner: String)
}

/// Turns a series of readings into the handful of things worth interrupting
/// somebody for.
///
/// Two rules do most of the work here, and both exist because the obvious
/// implementation is wrong in a way that only shows up on a real machine:
///
/// - **A runner is baselined the first time it is seen, and produces nothing.**
///   The job history comes out of `_diag`, which reaches back about two days,
///   so an app that notified on what it found at launch would announce a build
///   that broke on Tuesday. The same goes for a runner that appears mid-session:
///   it is new to this app, not new to the machine.
/// - **Only transitions.** A runner that has been disconnected for an hour is
///   the same fact every fifteen seconds, and a fact repeated 240 times is how
///   a user ends up switching notifications off — including the one that
///   mattered.
///
/// A value type with no clock and no I/O, so every rule above is a test rather
/// than an afternoon of waiting for a runner to misbehave.
struct FleetWatcher {
  /// What the last reading of one runner said.
  private struct Seen {
    let display: DisplayState
    /// The start time of the newest *finished* job already accounted for, and
    /// nil for a runner whose log held none.
    ///
    /// A start time rather than a count or an index: `_diag` rotates, so the
    /// list shrinks and shifts underneath this, and one runner runs one job at
    /// a time — which is exactly what makes its start instant an identity.
    let newestFinish: Date?
  }

  private var seen: [String: Seen] = [:]
  private struct ExpectedStop {
    let requestedAt: Date
    var completedAt: Date?
  }

  private let expectedStopLifetime: TimeInterval

  init(expectedStopLifetime: TimeInterval = 30) {
    self.expectedStopLifetime = expectedStopLifetime
  }

  /// Runners this app has asked to stop and has not yet watched stop.
  ///
  /// Kept apart from `seen` because it is set before the reading it applies to,
  /// and by a different caller: `stop` and `restart` know a stop is coming, and
  /// the scan that finds the runner down lands two seconds later.
  private var expectedStops: [String: ExpectedStop] = [:]

  /// Called when this app asks a runner to stop, so the stop it then observes
  /// is not reported back to the person who ordered it.
  ///
  /// This is the whole of the distinction between "you stopped it" and "it
  /// stopped": there is nothing in `launchctl` that says which, and guessing
  /// from timing would make a slow machine look like a crashed one. Restart
  /// takes the service down too, and lands in the same place.
  mutating func expectStop(for label: String, at requestAt: Date) {
    expectedStops[label] = ExpectedStop(requestedAt: requestAt)
  }

  /// Arms recovery only once the command cannot make any more progress.
  /// Until then an idle reading means merely that Stop has not reached
  /// launchd yet; it says nothing about the stop that is still in flight.
  mutating func completeExpectedStop(for label: String, at completedAt: Date) {
    expectedStops[label]?.completedAt = completedAt
  }

  /// Revokes an intent whose command definitely failed before completing.
  /// Timeouts deliberately do not call this: the process may already have
  /// stopped the service before it was killed at the deadline.
  mutating func cancelExpectedStop(for label: String) {
    expectedStops.removeValue(forKey: label)
  }

  /// Forgets runners that are no longer installed, so an uninstalled one does
  /// not leave a baseline behind for a reinstall to be compared against.
  mutating func keepOnly(_ labels: Set<String>) {
    seen = seen.filter { labels.contains($0.key) }
    expectedStops = expectedStops.filter { labels.contains($0.key) }
  }

  /// Reads one scan and reports what changed since the last one.
  mutating func events(in snapshots: [RunnerSnapshot]) -> [FleetEvent] {
    var events: [FleetEvent] = []
    for snapshot in snapshots {
      let label = snapshot.runner.label
      let newestFinish = snapshot.jobs.records.first { $0.finishedAt != nil }?
        .startedAt
      defer {
        seen[label] = Seen(display: snapshot.display, newestFinish: newestFinish)
      }
      guard let before = seen[label] else {
        // First sight of this runner. Everything in its log predates the app.
        continue
      }
      events += failures(in: snapshot, after: before.newestFinish)
      events += stateChange(in: snapshot, from: before.display)
    }
    return events
  }

  /// The jobs that failed since the last reading, oldest first.
  ///
  /// Only `.failed`, and deliberately not `.other`. The runner serialises the
  /// name of an enum it may add to, so an unrecognised word could be
  /// `SucceededWithIssues` as easily as `Abandoned` — and this app has met
  /// neither. Waking somebody up over a word nobody has read the meaning of is
  /// the one mistake a notification cannot take back.
  private func failures(
    in snapshot: RunnerSnapshot, after mark: Date?
  ) -> [FleetEvent] {
    var failures: [FleetEvent] = []
    for record in snapshot.jobs.records where record.finishedAt != nil {
      // Newest first, so the first record at or before the mark ends the walk:
      // everything past it has already been accounted for.
      if let mark, record.startedAt <= mark { break }
      guard record.result == .failed else { continue }
      failures.append(.jobFailed(runner: snapshot.name, job: record.name))
    }
    return failures.reversed()
  }

  /// What this runner's state moving says, and the expected stop it may spend.
  private mutating func stateChange(
    in snapshot: RunnerSnapshot, from before: DisplayState
  ) -> [FleetEvent] {
    let changed = snapshot.display != before
    var expectedStop = expectedStops[snapshot.runner.label]
    if let completedAt = expectedStop?.completedAt,
      snapshot.readAt >= completedAt.addingTimeInterval(expectedStopLifetime)
    {
      // An uncertain timeout cannot grant permanent silence. Expiration is
      // evaluated against probe time, so the first later observation is never
      // attributed to an action whose effects should already be settled.
      expectedStops.removeValue(forKey: snapshot.runner.label)
      expectedStop = nil
    }
    let maySuppressStop = expectedStop.map { snapshot.readAt >= $0.requestedAt } ?? false
    let maySpendExpectedStop =
      expectedStop?.completedAt.map {
        snapshot.readAt >= $0
      } ?? false
    switch snapshot.display.resolvedState {
    case .stopped:
      // Spent on the first stop observed rather than on the first stop
      // *reported*: a user who presses Stop on an already-stopped runner would
      // otherwise leave the token behind to swallow a real crash later.
      if maySpendExpectedStop {
        expectedStops.removeValue(forKey: snapshot.runner.label)
      }
      let expected = maySuppressStop
      guard changed, !expected else { return [] }
      return [.runnerStoppedUnexpectedly(runner: snapshot.name)]
    case .idle, .busy:
      // Up and taking work, so whatever stop was expected has been and gone —
      // which is what a restart looks like when the scan misses the gap.
      if maySpendExpectedStop {
        expectedStops.removeValue(forKey: snapshot.runner.label)
      }
      return []
    case .disconnected:
      return changed ? [.runnerDisconnected(runner: snapshot.name)] : []
    // `.unknown` is this app failing to read the machine, not the machine
    // failing, and `.starting` is a runner in the middle of the handshake. Both
    // are states with nothing to report yet.
    case .unknown, nil:
      return []
    }
  }
}

extension FleetEvent {
  var title: String {
    switch self {
    case .jobFailed: L10n.notificationJobFailedTitle
    case .runnerDisconnected: L10n.notificationDisconnectedTitle
    case .runnerStoppedUnexpectedly: L10n.notificationStoppedTitle
    }
  }

  var body: String {
    switch self {
    case .jobFailed(let runner, let job): L10n.notificationJobFailedBody(job, runner)
    case .runnerDisconnected(let runner): L10n.notificationDisconnectedBody(runner)
    case .runnerStoppedUnexpectedly(let runner): L10n.notificationStoppedBody(runner)
    }
  }
}
