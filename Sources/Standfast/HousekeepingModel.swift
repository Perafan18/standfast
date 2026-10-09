import AppKit
import Foundation
import RunnerKit

/// One reading of a runner's disk, and when it was taken.
struct DiskMeasurement: Equatable {
  /// Nil when `du` could not be run at all, which the menu has to be able to
  /// say rather than draw as a runner using no disk.
  let report: DiskReport?
  let readAt: Date
}

/// The seam over `NSAlert`, which puts a modal window on the screen of whatever
/// machine it runs on — including the one running the test suite, where nobody
/// is there to dismiss it.
@MainActor
/// What came back from asking, and the reason this is not a `Bool`.
///
/// "The user said no" and "nobody could be asked" both stop a deletion, and
/// only one of them is worth a sentence on screen. Collapsing them into false
/// is how a locked screen turned a click into silence (D-R20).
enum CleanupConfirmationResult: Equatable, Sendable {
  case accepted
  case cancelled
  case unavailable
}

@MainActor
protocol CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> CleanupConfirmationResult
}

struct AlertConfirmation: CleanupConfirming {
  /// Whether this login session's screen is locked.
  ///
  /// Injected because `AlertConfirmation` otherwise has no seam a test can
  /// reach — and the untestable half is exactly where the silent failure
  /// lived. This is the only thing the type decides before AppKit takes over.
  private let isScreenLocked: @MainActor () -> Bool

  init(isScreenLocked: @escaping @MainActor () -> Bool = AlertConfirmation.screenIsLocked) {
    self.isScreenLocked = isScreenLocked
  }

  /// A locked screen presents no modal and returns no answer, so the alert
  /// below would be a dialogue nobody can see and a click that does nothing.
  static func screenIsLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
      return false
    }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
  }

  func confirm(_ prompt: CleanupPrompt) -> CleanupConfirmationResult {
    guard !isScreenLocked() else { return .unavailable }
    // A menu bar app is an accessory: without this the alert opens behind
    // whatever the user was looking at, with no Dock icon to click to find it.
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = prompt.title
    alert.informativeText = prompt.message
    alert.addButton(withTitle: prompt.confirm)
    alert.addButton(withTitle: prompt.cancel)
    alert.buttons.first?.keyEquivalent = CleanupKeys.destructive
    alert.buttons.last?.keyEquivalent = CleanupKeys.cancel
    return alert.runModal() == .alertFirstButtonReturn ? .accepted : .cancelled
  }
}

/// Which keys the delete dialogue answers to.
///
/// Its own value because `AlertConfirmation` has no seam a test can reach — it
/// opens a modal window, and a suite that reached it would hang on whatever
/// machine ran it — while this is the whole of what that unit decides.
///
/// `NSAlert` hands the *first* button the Return key, and the first button has
/// to be the destructive one because macOS draws it on the right. So Return
/// would delete four gigabytes for somebody clearing a stack of windows with
/// it, and the key comes off. It does not go on Cancel either, which is what
/// this used to do: `NSAlert` gives Cancel the Escape key by matching its
/// title, so overwriting it left the dialogue with no way out at all — measured
/// as `[("Delete", ""), ("Cancel", "\r")]`, no button carrying `\u{1B}`. In
/// Spanish it was worse: the title match is against the English word, so
/// "Cancelar" was never given Escape in the first place.
///
/// Escape is set by hand for that reason, and Return is left doing nothing. A
/// button carries one key equivalent, and of the two this is the one worth
/// having: Escape is what every other dialogue on the machine answers to, and
/// the property that matters is only ever that Return does not delete.
enum CleanupKeys {
  static let destructive = ""
  static let cancel = "\u{1B}"
}

/// Measures what a runner is costing this Mac, and deletes the parts of that
/// which can be deleted.
///
/// Separate from `RunnerFleetModel` because the two have opposite rhythms. That
/// one reads the machine every fifteen seconds all day; this one reads it when
/// somebody asks, and writes to it only after they have said so twice.
@MainActor
final class HousekeepingModel: ObservableObject {
  @Published private(set) var measurements: [String: DiskMeasurement] = [:]
  /// Runners with a measurement or a deletion in flight, by label.
  @Published private(set) var working: Set<String> = []
  /// What the last action on each runner had to say, by label.
  ///
  /// One per runner rather than one for the model, because `working` is indexed
  /// by runner and so two of them can be acting at once — on exactly the
  /// two-runner Mac this app is built for, where clearing one runner's four
  /// gigabytes takes long enough to go and clear the other's. A single slot let
  /// whichever finished last overwrite the other, and what it overwrote could
  /// be a refusal: the one outcome the user asked for, agreed to, and did not
  /// get.
  @Published private var reports: [String: String] = [:]

  private let usage: DiskUsage
  private let housekeeper: Housekeeper
  private let confirmation: any CleanupConfirming
  private let probe: @Sendable (DiscoveredRunner) -> RunnerState
  private let retention: DiagnosticsRetention
  private let clock: @Sendable () -> Date
  /// Work still running, each entry removing itself when it finishes. Kept only
  /// so `quiesce()` has something to wait on.
  private var tasks: [UUID: Task<Void, Never>] = [:]

  /// - Parameters:
  ///   - probe: how this asks whether a runner is safe to touch *now*. Blocking
  ///     on purpose — it is a call to GitHub and possibly `launchctl` — and it
  ///     is called from the same thread as the deletion, so that nothing at all
  ///     can happen between the answer and the rename.
  ///   - clock: read for the age of a measurement, which is the one number here
  ///     nothing refreshes for the user.
  init(
    usage: DiskUsage = DiskUsage(),
    housekeeper: Housekeeper = Housekeeper(),
    confirmation: any CleanupConfirming = AlertConfirmation(),
    probe: @escaping @Sendable (DiscoveredRunner) -> RunnerState,
    retention: DiagnosticsRetention = .standard,
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.usage = usage
    self.housekeeper = housekeeper
    self.confirmation = confirmation
    self.probe = probe
    self.retention = retention
    self.clock = clock
  }

  /// The one the app builds, which is the one that decides *which* of the
  /// resolver's two verdicts guards a deletion.
  ///
  /// Its own entry point rather than a default value on `probe:` above, because
  /// a default argument is wiring no test can reach — and this is the single
  /// line the whole safety of the file rests on.
  ///
  /// `blockingConfirmedState` and never `blockingState`. That one lets
  /// `launchctl` settle `.stopped` alone, and `.stopped` is a state this app is
  /// willing to delete four gigabytes in. A runner started by hand with
  /// `./run.sh` — GitHub's own documented way to debug a failing job — leaves
  /// the LaunchAgent plist on disk, so this app still lists it, and takes the
  /// label out of `launchctl list`. It would be mid-build behind a verdict that
  /// says nothing is running.
  convenience init(
    usage: DiskUsage = DiskUsage(),
    housekeeper: Housekeeper = Housekeeper(),
    confirmation: any CleanupConfirming = AlertConfirmation(),
    resolver: RunnerStateResolver = RunnerStateResolver(),
    retention: DiagnosticsRetention = .standard,
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.init(
      usage: usage, housekeeper: housekeeper, confirmation: confirmation,
      probe: resolver.blockingConfirmedState, retention: retention, clock: clock)
  }

  /// Drops what is known about runners that are no longer installed, so an
  /// uninstalled runner's numbers do not sit in memory for the life of the app.
  func keepOnly(_ labels: Set<String>) {
    measurements = measurements.filter { labels.contains($0.key) }
    reports = reports.filter { labels.contains($0.key) }
  }

  func measurement(for runner: DiscoveredRunner) -> DiskMeasurement? {
    measurements[runner.label]
  }

  func isWorking(on runner: DiscoveredRunner) -> Bool { working.contains(runner.label) }

  /// Anything the last action has to say about *this* runner, and nil for every
  /// other one. The only way a report is read.
  ///
  /// The submenu is drawn once per runner, so "nothing was deleted: build-mac
  /// picked up work" under build-intel's Maintenance menu is a sentence about
  /// the wrong machine.
  func notice(for runner: DiscoveredRunner) -> String? { reports[runner.label] }

  /// The one way the menu acts, so the view has nothing to wire up wrongly.
  ///
  /// - Parameter snapshot: the whole snapshot rather than the runner, because
  ///   every destructive branch below is gated on this runner's own state and
  ///   that is what carries it. Reading it back off the machine here would mean
  ///   `launchctl` and a network call on the main actor, which is the one place
  ///   in this app nothing may block.
  func perform(_ kind: MaintenanceOffer.Kind, on snapshot: RunnerSnapshot) {
    if let target = kind.target {
      clean(target, on: snapshot)
      return
    }
    switch kind {
    case .measure:
      // Fresh numbers the user asked for retire whatever the last action said,
      // unless `measure` ignores the click: the one already running may be the
      // re-measure behind a refusal still worth reading.
      if !working.contains(snapshot.runner.label) { reports[snapshot.runner.label] = nil }
      measure(snapshot.runner)
    case .cleanStandfastTrash: cleanStandfastTrash(on: snapshot)
    case .trimLogs: trimLogs(on: snapshot)
    // Handled above, by the one place that knows which directory each is.
    case .cleanToolCache, .cleanActionCache: break
    }
  }

  // MARK: - Measuring

  /// Taken when somebody asks for it and at no other time.
  ///
  /// No timer and no staleness rule. `du` is a full metadata walk of every file
  /// the runner owns — 0.24 s warm on the 4.5 GB this was measured against, and
  /// seconds on a Mac that has just woken or a home directory on a network
  /// volume — where the refresh loop runs every fifteen seconds all day. What
  /// makes reading on demand honest rather than lazy is the line underneath
  /// saying how old the number is.
  func measure(_ runner: DiscoveredRunner) {
    let label = runner.label
    // A second `du` on top of the first would answer the same question twice
    // and let the slower of the two overwrite the newer answer.
    guard !working.contains(label) else { return }
    let now = clock()
    working.insert(label)
    let usage = usage
    let retention = retention
    run {
      // The same rule as everything else that touches this machine: `du` blocks
      // until it has walked every file the runner owns, and the cooperative
      // pool has one thread per core and runs the main actor's work too.
      let report = await offCooperativePool {
        usage.blockingReport(for: runner, retention: retention, now: now)
      }
      self.measurements[label] = DiskMeasurement(report: report, readAt: now)
      self.working.remove(label)
    }
  }

  // MARK: - Deleting

  private func clean(_ target: CleanupTarget, on snapshot: RunnerSnapshot) {
    let runner = snapshot.runner
    guard let measurement = measurements[runner.label], let report = measurement.report
    else { return }
    let bytes = report.bytes(of: target.kind)
    // Gated on this runner's own state, never on the fleet's, and checked here
    // as well as in the view: a dialogue about deleting the cache of a runner
    // that is mid-build is a dialogue that should never have opened.
    guard bytes > 0, !working.contains(runner.label),
      snapshot.display.allowsHousekeeping
    else { return }
    let prompt = CleanupPrompt.cleaning(
      target, in: runner, bytes: bytes,
      measuredAgo: clock().timeIntervalSince(measurement.readAt))
    switch confirmation.confirm(prompt) {
    case .accepted: break
    // What the previous attempt said is no longer about the last thing done.
    case .cancelled:
      reports[runner.label] = nil
      return
    // Said where it was asked, in the same place a failed cleanup reports
    // itself. Somebody who pressed Cancel already knows what they did; only
    // the case where the app could not ask gets a sentence.
    case .unavailable:
      reports[runner.label] = L10n.cleanupConfirmationUnavailable
      return
    }

    let housekeeper = housekeeper
    let probe = probe
    perform(on: runner, failurePath: target.directory(in: runner)) {
      var verdict: RunnerState?
      // Everything up to the rename happens before the check inside
      // `blockingClean`, and the check is the last thing before it.
      let outcome = try housekeeper.blockingClean(target, in: runner) {
        let state = probe(runner)
        verdict = state
        return state.allowsHousekeeping
      }
      return (outcome, verdict)
    }
  }

  private func trimLogs(on snapshot: RunnerSnapshot) {
    let runner = snapshot.runner
    guard let report = measurements[runner.label]?.report else { return }
    let plan = report.rotation
    guard !plan.isEmpty, !working.contains(runner.label),
      snapshot.display.allowsHousekeeping
    else { return }
    switch confirmation.confirm(.trimmingLogs(in: runner, plan: plan)) {
    case .accepted: break
    case .cancelled:
      reports[runner.label] = nil
      return
    case .unavailable:
      reports[runner.label] = L10n.cleanupConfirmationUnavailable
      return
    }

    let housekeeper = housekeeper
    let retention = retention
    let probe = probe
    let now = clock()
    perform(on: runner, failurePath: runner.diagnosticsDirectory) {
      var verdict: RunnerState?
      // Re-planned in there against the directory as it is at that moment, and
      // held to what the user agreed to. Re-planning is what keeps a file that
      // has since become the active log out of the sweep; the plan going in is
      // what keeps the sweep from taking more than the number in the dialogue,
      // which was drawn from a measurement of any age at all.
      let outcome = try housekeeper.blockingRotateDiagnostics(
        in: runner, retention: retention, now: now, agreedTo: plan,
        isStillSafe: {
          let state = probe(runner)
          verdict = state
          return state.allowsHousekeeping
        })
      return (outcome, verdict)
    }
  }

  private func cleanStandfastTrash(on snapshot: RunnerSnapshot) {
    let runner = snapshot.runner
    guard let measurement = measurements[runner.label], let report = measurement.report
    else { return }
    let bytes = report.legacyTrashBytes
    guard bytes > 0, !working.contains(runner.label),
      snapshot.display.allowsHousekeeping
    else { return }
    switch confirmation.confirm(
      .cleaningStandfastTrash(
        in: runner, bytes: bytes,
        measuredAgo: clock().timeIntervalSince(measurement.readAt)))
    {
    case .accepted: break
    case .cancelled:
      reports[runner.label] = nil
      return
    case .unavailable:
      reports[runner.label] = L10n.cleanupConfirmationUnavailable
      return
    }

    let housekeeper = housekeeper
    let trash = runner.workDirectory.appendingPathComponent(Housekeeper.trashFolder)
    perform(on: runner, failurePath: trash) {
      (try housekeeper.blockingCleanLegacyTrash(in: runner), nil)
    }
  }

  /// - Parameters:
  ///   - work: blocking, and run off both pools. Returns what the safety probe
  ///     answered, if it was asked, so a refusal can say why.
  ///   - failurePath: what to name in the menu when it did not work and did not
  ///     say which directory it was about.
  private func perform(
    on runner: DiscoveredRunner, failurePath: URL,
    _ work: @escaping @Sendable () throws -> (HousekeepingOutcome, RunnerState?)
  ) {
    let label = runner.label
    reports[label] = nil
    working.insert(label)
    let name = runner.displayName
    run {
      let answer = await offCooperativePool {
        () -> (
          outcome: HousekeepingOutcome?, verdict: RunnerState?, path: URL,
          didModify: Bool
        ) in
        do {
          let (outcome, verdict) = try work()
          return (outcome, verdict, failurePath, false)
        } catch let failure as HousekeepingFailure {
          // The operation knows which directory the failed write was about and
          // whether an earlier write may have changed it; neither can be
          // recovered from the generic path at this boundary.
          return (nil, nil, failure.directory, failure.didModify)
        } catch {
          return (nil, nil, failurePath, false)
        }
      }
      self.working.remove(label)
      self.reports[label] = Self.notice(
        for: answer.outcome, runner: name, path: answer.path,
        didModify: answer.didModify, verdict: answer.verdict)
      // A success changed the disk. `nothingToDo` proves the measurement that
      // justified the confirmation was stale: the named bytes disappeared
      // before this reached them. Either way the next thing the user does is
      // look at numbers that need to be read again.
      if answer.outcome == .done || answer.outcome == .nothingToDo
        || answer.outcome == .refusedAfterChange || answer.didModify
      {
        self.measure(runner)
      }
    }
  }

  /// - Parameter verdict: what the safety probe answered, and nil when it was
  ///   never asked.
  static func notice(
    for outcome: HousekeepingOutcome?, runner: String, path: URL,
    didModify: Bool = false, verdict: RunnerState? = nil
  ) -> String? {
    switch outcome {
    // Nothing to say. What was asked for happened, and the rows underneath are
    // about to redraw with the new numbers, which is the report.
    case .done, .nothingToDo: return nil
    // The one outcome that has to be reported: the user asked for something,
    // agreed to it, and did not get it. Only GitHub saying busy is evidence
    // of a job; any other refusing verdict is a state nobody could confirm.
    case .refused, .refusedAfterChange:
      return verdict == .busy
        ? L10n.cleanupRefused(runner) : L10n.cleanupUnconfirmed(runner)
    // By the time anything can throw, the only thing left that can go wrong is
    // the filesystem saying no.
    case nil:
      let path = PathText.abbreviated(path)
      return didModify ? L10n.cleanupPartiallyFailed(path) : L10n.cleanupFailed(path)
    }
  }

  /// Keeps hold of the work so `quiesce()` has something to wait on, and lets
  /// it drop itself when it is done.
  ///
  /// The body stays on the main actor and hops off inside itself, which is what
  /// makes every line that touches `@Published` state ordinary main-actor code
  /// — the same shape `RunnerFleetModel` uses for an action.
  private func run(_ body: @escaping @MainActor () async -> Void) {
    let id = UUID()
    tasks[id] = Task {
      await body()
      tasks[id] = nil
    }
  }

  /// Waits out everything this model has running. The menu never needs this —
  /// it watches `@Published` — but a test does.
  func quiesce() async {
    while let task = tasks.values.first { await task.value }
  }
}
