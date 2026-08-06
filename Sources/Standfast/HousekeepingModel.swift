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
protocol CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> Bool
}

struct AlertConfirmation: CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> Bool {
    // A menu bar app is an accessory: without this the alert opens behind
    // whatever the user was looking at, with no Dock icon to click to find it.
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = prompt.title
    alert.informativeText = prompt.message
    alert.addButton(withTitle: prompt.confirm)
    alert.addButton(withTitle: prompt.cancel)
    // Return cancels. `NSAlert` makes the first button the default, and the
    // first button has to be the destructive one because macOS draws it on the
    // right — so the key equivalents are swapped back by hand. Somebody
    // dismissing a stack of windows with the Return key must not delete four
    // gigabytes on the way past.
    alert.buttons.first?.keyEquivalent = ""
    alert.buttons.last?.keyEquivalent = "\r"
    return alert.runModal() == .alertFirstButtonReturn
  }
}

/// What the last action had to say, and which runner it was about.
struct HousekeepingReport: Equatable {
  let label: String
  let text: String
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
  /// One report for the whole model rather than one per runner, because only
  /// one action runs at a time — but it carries the label of the runner it is
  /// about, and nothing reads it without one. The submenu is drawn once per
  /// runner, so "nothing was deleted: build-mac picked up work" under
  /// build-intel's Maintenance menu is a sentence about the wrong machine, on
  /// exactly the two-runner Mac this app is built for.
  @Published private var report: HousekeepingReport?

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
  ///     on purpose — it is `launchctl` and a call to GitHub — and it is called
  ///     from the same thread as the deletion, so that nothing at all can
  ///     happen between the answer and the rename.
  ///   - clock: read for the age of a measurement, which is the one number here
  ///     nothing refreshes for the user.
  init(
    usage: DiskUsage = DiskUsage(),
    housekeeper: Housekeeper = Housekeeper(),
    confirmation: any CleanupConfirming = AlertConfirmation(),
    probe: @escaping @Sendable (DiscoveredRunner) -> RunnerState = {
      RunnerStateResolver().blockingState(for: $0)
    },
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

  /// Drops what is known about runners that are no longer installed, so an
  /// uninstalled runner's numbers do not sit in memory for the life of the app.
  func keepOnly(_ labels: Set<String>) {
    measurements = measurements.filter { labels.contains($0.key) }
  }

  func measurement(for runner: DiscoveredRunner) -> DiskMeasurement? {
    measurements[runner.label]
  }

  func isWorking(on runner: DiscoveredRunner) -> Bool { working.contains(runner.label) }

  /// Anything the last action has to say about *this* runner, and nil for every
  /// other one. The only way the report is read.
  func notice(for runner: DiscoveredRunner) -> String? {
    report?.label == runner.label ? report?.text : nil
  }

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
    case .measure: measure(snapshot.runner)
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
    guard let report = measurements[runner.label]?.report else { return }
    let bytes = report.bytes(of: target.kind)
    // Gated on this runner's own state, never on the fleet's, and checked here
    // as well as in the view: a dialogue about deleting the cache of a runner
    // that is mid-build is a dialogue that should never have opened.
    guard bytes > 0, !working.contains(runner.label),
      snapshot.display.allowsHousekeeping
    else { return }
    guard confirmation.confirm(.cleaning(target, in: runner, bytes: bytes)) else { return }

    let housekeeper = housekeeper
    let probe = probe
    perform(on: runner, failurePath: target.directory(in: runner)) {
      // Everything up to the rename happens before the check inside
      // `blockingClean`, and the check is the last thing before it.
      try? housekeeper.blockingClean(target, in: runner) {
        probe(runner).allowsHousekeeping
      }
    }
  }

  private func trimLogs(on snapshot: RunnerSnapshot) {
    let runner = snapshot.runner
    guard let report = measurements[runner.label]?.report else { return }
    let plan = report.rotation
    guard !plan.isEmpty, !working.contains(runner.label),
      snapshot.display.allowsHousekeeping
    else { return }
    guard confirmation.confirm(.trimmingLogs(in: runner, plan: plan)) else { return }

    let housekeeper = housekeeper
    let retention = retention
    let probe = probe
    let now = clock()
    perform(on: runner, failurePath: runner.diagnosticsDirectory) {
      // Re-planned in there, against the directory as it is at that moment
      // rather than against the listing the menu was drawn from. A listener
      // that rotated in between would otherwise leave the plan naming a file
      // that has since become the active log.
      housekeeper.blockingRotateDiagnostics(
        in: runner, retention: retention, now: now,
        isStillSafe: { probe(runner).allowsHousekeeping })
    }
  }

  /// - Parameters:
  ///   - work: blocking, and run off both pools.
  ///   - failurePath: what to name in the menu when it did not work, which by
  ///     the time anything can fail means a directory this app cannot write to.
  private func perform(
    on runner: DiscoveredRunner, failurePath: URL,
    _ work: @escaping @Sendable () -> HousekeepingOutcome?
  ) {
    let label = runner.label
    report = nil
    working.insert(label)
    let name = runner.displayName
    run {
      let outcome = await offCooperativePool(work)
      self.working.remove(label)
      self.report = Self.notice(for: outcome, runner: name, path: failurePath)
        .map { HousekeepingReport(label: label, text: $0) }
      // The numbers on screen now describe a directory that is not there any
      // more, and the next thing the user does is look at them.
      if outcome == .done { self.measure(runner) }
    }
  }

  static func notice(
    for outcome: HousekeepingOutcome?, runner: String, path: URL
  ) -> String? {
    switch outcome {
    // Nothing to say. What was asked for happened, and the rows underneath are
    // about to redraw with the new numbers, which is the report.
    case .done, .nothingToDo: nil
    // The one outcome that has to be reported: the user asked for something,
    // agreed to it, and did not get it.
    case .refused: L10n.cleanupRefused(runner)
    // By the time anything can throw, the only thing left that can go wrong is
    // the filesystem saying no.
    case nil: L10n.cleanupFailed(PathText.abbreviated(path))
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
