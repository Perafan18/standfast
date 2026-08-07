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

enum ExpectedStopAction: Equatable {
  case stop
  case restart
}

enum ExpectedStopOutcome: Equatable {
  /// The requested Stop, or both halves of Restart, returned successfully.
  case actionCompleted
  /// Restart's Stop completed, but Start definitely failed.
  case restartStartFailed
  /// Restart's Stop completed and Start was attempted before timing out.
  case restartStartUncertain
  /// Stop itself timed out, so even its effect is unknown.
  case stopUncertain
}

struct ExpectedStopHandle: Hashable {
  fileprivate let label: String
  fileprivate let id: UUID
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
    /// False until `_diag` has answered at least once. A nil finish after that
    /// is a real empty-history watermark; before it, nil means no evidence.
    let hasJobBaseline: Bool
    /// The start time of the newest *finished* job already accounted for, and
    /// nil for an available history whose log held none.
    ///
    /// A start time rather than a count or an index: `_diag` rotates, so the
    /// list shrinks and shifts underneath this, and one runner runs one job at
    /// a time — which is exactly what makes its start instant an identity.
    let newestFinish: Date?
  }

  private var seen: [String: Seen] = [:]
  private struct ExpectedStop {
    let id: UUID
    let action: ExpectedStopAction
    let requestedAt: Date
    var completion: Completion?
  }

  private struct Completion {
    let outcome: ExpectedStopOutcome
    let completedAt: Date
    let graceDeadline: Date

    var isStopUncertain: Bool { outcome == .stopUncertain }
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
  private var expectedStops: [String: [ExpectedStop]] = [:]

  /// Called when this app asks a runner to stop, so the stop it then observes
  /// is not reported back to the person who ordered it.
  ///
  /// This is the whole of the distinction between "you stopped it" and "it
  /// stopped": there is nothing in `launchctl` that says which, and guessing
  /// from timing would make a slow machine look like a crashed one. Restart
  /// takes the service down too, and lands in the same place.
  @discardableResult
  mutating func expectStop(
    for label: String, action: ExpectedStopAction = .stop, at requestAt: Date
  ) -> ExpectedStopHandle {
    let handle = ExpectedStopHandle(label: label, id: UUID())
    expectedStops[label, default: []].append(
      ExpectedStop(
        id: handle.id, action: action, requestedAt: requestAt,
        completion: nil))
    return handle
  }

  /// Arms recovery only once the command cannot make any more progress.
  /// Until then an idle reading means merely that Stop has not reached
  /// launchd yet; it says nothing about the stop that is still in flight.
  mutating func completeExpectedStop(
    _ handle: ExpectedStopHandle, outcome: ExpectedStopOutcome = .actionCompleted,
    at completedAt: Date
  ) {
    guard var stops = expectedStops[handle.label],
      let index = stops.firstIndex(where: { $0.id == handle.id })
    else { return }
    stops[index].completion = Completion(
      outcome: outcome,
      completedAt: completedAt,
      graceDeadline: completedAt.addingTimeInterval(expectedStopLifetime))
    if outcome == .actionCompleted, index > stops.startIndex {
      stops.removeSubrange(stops.startIndex..<index)
    }
    expectedStops[handle.label] = stops
  }

  /// Revokes an intent whose command definitely failed before completing.
  /// Timeouts deliberately do not call this: the process may already have
  /// stopped the service before it was killed at the deadline.
  mutating func cancelExpectedStop(_ handle: ExpectedStopHandle) {
    guard var stops = expectedStops[handle.label] else { return }
    stops.removeAll { $0.id == handle.id }
    storeExpectedStops(stops, for: handle.label)
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
      guard let before = seen[label] else {
        // First sight of this runner baselines its state immediately, but its
        // jobs only when `_diag` actually answered. An unavailable cold read
        // carries the same empty value as a successfully empty directory and
        // must not turn historical failures into new ones on recovery.
        seen[label] = Seen(
          display: snapshot.display,
          hasJobBaseline: snapshot.isJobHistoryAvailable,
          newestFinish: snapshot.isJobHistoryAvailable ? newestFinish : nil)
        continue
      }
      let hasJobBaseline: Bool
      let jobBaseline: Date?
      if snapshot.isJobHistoryAvailable {
        if before.hasJobBaseline {
          events += failures(in: snapshot, after: before.newestFinish)
        }
        hasJobBaseline = true
        jobBaseline = newestFinish
      } else {
        hasJobBaseline = before.hasJobBaseline
        jobBaseline = before.newestFinish
      }
      let stateChange = stateChange(in: snapshot, from: before.display)
      events += stateChange.events
      seen[label] = Seen(
        display: stateChange.advancesBaseline ? snapshot.display : before.display,
        hasJobBaseline: hasJobBaseline, newestFinish: jobBaseline)
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
  ) -> (events: [FleetEvent], advancesBaseline: Bool) {
    let changed = snapshot.display != before
    let label = snapshot.runner.label
    var stops = expectedStops[label] ?? []
    // An uncertain timeout cannot grant permanent silence. Expiration is
    // evaluated against probe time, so the first later observation is never
    // attributed to an action whose effects should already be settled.
    stops.removeAll { stop in
      guard let completion = stop.completion else { return false }
      return completion.isStopUncertain
        && snapshot.readAt >= completion.graceDeadline
    }
    storeExpectedStops(stops, for: label)

    func maySuppressStop(_ stop: ExpectedStop) -> Bool {
      snapshot.readAt >= stop.requestedAt
    }
    func maySuppressRemoteState(_ stop: ExpectedStop) -> Bool {
      snapshot.stateReadAt >= stop.requestedAt
    }
    func maySpend(_ stop: ExpectedStop) -> Bool {
      stop.completion.map { snapshot.readAt >= $0.completedAt } ?? false
    }
    func withinCompletionGrace(_ stop: ExpectedStop) -> Bool {
      stop.completion.map { snapshot.readAt < $0.graceDeadline } ?? false
    }
    func runningObservationCompletesRestart(_ stop: ExpectedStop) -> Bool {
      guard stop.action == .restart, let outcome = stop.completion?.outcome else {
        return false
      }
      switch outcome {
      case .actionCompleted, .restartStartUncertain: return true
      case .restartStartFailed, .stopUncertain: return false
      }
    }
    func preservesExpectedStop(_ stop: ExpectedStop) -> Bool {
      maySuppressRemoteState(stop) && withinCompletionGrace(stop)
    }
    func defersDisconnection(_ stop: ExpectedStop) -> Bool {
      maySuppressRemoteState(stop)
        && (!maySpend(stop)
          || (withinCompletionGrace(stop)
            && !runningObservationCompletesRestart(stop)))
    }

    switch snapshot.display.resolvedState {
    case .stopped:
      // Spent on the first stop observed rather than on the first stop
      // *reported*: a user who presses Stop on an already-stopped runner would
      // otherwise leave the token behind to swallow a real crash later.
      let expected = stops.contains(where: maySuppressStop)
      let hasCompletedIntent = stops.contains { $0.completion != nil }
      stops.removeAll(where: maySpend)
      storeExpectedStops(stops, for: label)
      // A stopped transition seen before the command returns is provisional.
      // Keep the previous display baseline until the command outcome can
      // either confirm and spend it or cancel intent and expose it next scan.
      let advancesBaseline = hasCompletedIntent || !expected
      guard changed, !expected else { return ([], advancesBaseline) }
      return ([.runnerStoppedUnexpectedly(runner: snapshot.name)], true)
    case .idle, .busy:
      // Up and taking work, so whatever stop was expected has been and gone —
      // which is what a restart looks like when the scan misses the gap. A
      // post-click answer inside the completion grace can still precede the
      // ordered stop settling in launchd, so it cannot spend intent yet.
      stops.removeAll { stop in
        maySpend(stop)
          && (runningObservationCompletesRestart(stop)
            || !preservesExpectedStop(stop))
      }
      storeExpectedStops(stops, for: label)
      return ([], true)
    case .disconnected:
      // GitHub is offline, but the resolver only reaches this state after
      // launchd answered that the service is running. That answer can lag a
      // completed Stop, so defer both the banner and baseline until either the
      // stopped observation arrives or the bounded completion grace expires.
      // Cancellation must expose this same transition on the next scan.
      let deferred = stops.contains(where: defersDisconnection)
      stops.removeAll { maySpend($0) && !defersDisconnection($0) }
      storeExpectedStops(stops, for: label)
      if deferred { return ([], false) }
      return (
        changed ? [.runnerDisconnected(runner: snapshot.name)] : [],
        true
      )
    // `.unknown` is this app failing to read the machine, not the machine
    // failing, and `.starting` is a runner in the middle of the handshake. Both
    // are states with nothing to report yet.
    case .unknown(let reason):
      // Every GitHub-side unknown also follows a successful local "running"
      // probe. Only launchd's own unreadable result leaves the stop uncertain.
      if reason != .serviceStateUnreadable {
        stops.removeAll { stop in
          maySpend(stop)
            && (runningObservationCompletesRestart(stop)
              || !preservesExpectedStop(stop))
        }
        storeExpectedStops(stops, for: label)
      }
      return ([], true)
    case nil:
      // Settling only covers `.disconnected`, whose launchd evidence is
      // likewise conclusive even though the presentation hides it.
      stops.removeAll { stop in
        maySpend(stop)
          && (runningObservationCompletesRestart(stop)
            || !preservesExpectedStop(stop))
      }
      storeExpectedStops(stops, for: label)
      return ([], true)
    }
  }

  private mutating func storeExpectedStops(_ stops: [ExpectedStop], for label: String) {
    if stops.isEmpty {
      expectedStops.removeValue(forKey: label)
    } else {
      expectedStops[label] = stops
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
