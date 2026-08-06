import Foundation
import RunnerKit
import SwiftUI

/// One runner and what to show for it.
struct RunnerSnapshot: Identifiable, Equatable {
  let runner: DiscoveredRunner
  let display: DisplayState
  /// Where this runner is registered, and nil when its name already says which
  /// runner it is. Decided for the fleet rather than for the runner, because
  /// whether a name identifies anything is a question about the other runners;
  /// see `repeatedNames(among:)`.
  let qualifier: String?
  /// What this runner's own listener log says it has been doing.
  let jobs: JobHistory
  /// When the scan behind this snapshot read the machine.
  ///
  /// Carried into the row rather than left to the clock so that every number
  /// in it describes one moment. A running job's elapsed time measured against
  /// `Date()` would tick on while the state beside it stayed as it was read
  /// half a minute ago, and the row would be quietly describing two different
  /// machines.
  let readAt: Date
  var id: String { runner.label }

  init(
    runner: DiscoveredRunner, display: DisplayState, qualifier: String? = nil,
    jobs: JobHistory = .empty, readAt: Date = .distantPast
  ) {
    self.runner = runner
    self.display = display
    self.qualifier = qualifier
    self.jobs = jobs
    self.readAt = readAt
  }
}

/// What the menu has to say beyond the runner rows themselves.
enum FleetNotice: Equatable {
  /// Nothing installed and nothing that failed to read. The expected result on
  /// a Mac that has never had a runner, where the answer is to install one
  /// rather than to fix anything.
  case noRunnersInstalled
  /// LaunchAgents that announced themselves as runners and could not be
  /// resolved. The paths, never a count: a plist duplicated in Finder
  /// describes one runner and appears here twice, so "2 unreadable runners"
  /// would be a number this app made up.
  case unreadable([URL])

  static func resolving(runners: [DiscoveredRunner], unreadable: [URL]) -> FleetNotice? {
    // Unreadable wins wherever it appears, including next to runners that did
    // resolve. A runner silently missing from the menu is worse than a line of
    // noise, and this is the only case here a user can act on.
    if !unreadable.isEmpty { return .unreadable(unreadable) }
    return runners.isEmpty ? .noRunnersInstalled : nil
  }
}

@MainActor
final class RunnerFleetModel: ObservableObject {
  @Published private(set) var snapshots: [RunnerSnapshot] = []
  @Published private(set) var notice: FleetNotice?
  /// When the scan behind what is on screen *started* reading, and nil until
  /// one has. Stamped at the start rather than on arrival on purpose: a `gh`
  /// that hangs for thirty seconds leaves a stale menu, and a mark taken when
  /// the answer landed would describe it as fresh.
  @Published private(set) var lastReadAt: Date?

  /// Which events reach the user, held here rather than beside this model so
  /// that the one place a scan turns into a notification is testable. Every bug
  /// this app has shipped was a wiring bug, and `App.swift` is the one file no
  /// test can read.
  let notifications: NotificationSettings
  let sleep: SleepGuard

  private let discover: @Sendable () -> DiscoveryResult
  private let resolver: RunnerStateResolver
  private let controller: ServiceController
  private let clock: @Sendable () -> Date
  private let probeDelay: TimeInterval
  private let refreshInterval: TimeInterval?
  private var settling: SettlingWindow
  /// What the last scan said, so this one can report what changed. Held here
  /// for the same reason `settling` is: no single scan can own it.
  private var watcher = FleetWatcher()
  /// One per runner, carrying how much of its listener log has already been
  /// read. Held here for the same reason `settling` is: it is state about a
  /// runner that no single scan can own.
  private var jobLogs: [String: JobLogReader] = [:]
  private var inFlight: Task<Void, Never>?
  private var refreshRequested = false
  private var ticker: Task<Void, Never>?
  /// Actions still running, each removing itself when it finishes. Kept only
  /// so `quiesce()` has something to wait on.
  private var actions: [UUID: Task<Void, Never>] = [:]

  /// - Parameters:
  ///   - discover: a call rather than a `RunnerDiscovery`, because *where* the
  ///     scan runs is as much a part of this model's job as what it finds —
  ///     `discover()` reads the filesystem on whatever thread invokes it — and
  ///     only a call a test can wrap makes that checkable.
  ///   - probeDelay: how long to let launchd settle before re-probing after an
  ///     action.
  ///   - refreshInterval: nil to leave the model driven only by explicit
  ///     refreshes, which is what tests want.
  init(
    discover: @escaping @Sendable () -> DiscoveryResult = {
      RunnerDiscovery().discover()
    },
    resolver: RunnerStateResolver = RunnerStateResolver(),
    controller: ServiceController = ServiceController(),
    settling: SettlingWindow = SettlingWindow(),
    notifications: NotificationSettings = NotificationSettings(),
    sleep: SleepGuard = SleepGuard(),
    clock: @escaping @Sendable () -> Date = Date.init,
    probeDelay: TimeInterval = 2,
    // 15s: fast enough that "did my build start?" is answered by looking up,
    // slow enough not to spend a GitHub API call every second all day.
    refreshInterval: TimeInterval? = 15
  ) {
    self.discover = discover
    self.resolver = resolver
    self.controller = controller
    self.settling = settling
    self.notifications = notifications
    self.sleep = sleep
    self.clock = clock
    self.probeDelay = probeDelay
    self.refreshInterval = refreshInterval
    refresh()
    guard let refreshInterval else { return }
    // A sleeping task rather than a `Timer`: a scheduled timer runs in the
    // default run loop mode, and an open NSMenu puts the run loop in event
    // tracking mode — so the one moment the user is looking at the menu is
    // exactly when a timer would stop refreshing it.
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(refreshInterval))
        guard let self else { return }
        tick()
      }
    }
  }

  deinit { ticker?.cancel() }

  // MARK: - Reading

  func refresh() {
    guard inFlight == nil else {
      // Remembered rather than dropped. N runners at up to a 30s `gh` timeout
      // each can easily outlast the 15s tick that starts the next scan, and
      // the request most likely to arrive during a slow one is the re-probe
      // after an action — the single answer the user is actually waiting for.
      refreshRequested = true
      return
    }
    // Stamped before anything is read, and carried all the way to `apply`. A
    // scan can take tens of seconds, so the answer it hands back describes the
    // machine as it was when it started, not as it is when it lands — and the
    // settling window has to be able to tell, or a reading taken before the
    // user pressed Restart gets to close the window that click opened.
    let readAt = clock()
    inFlight = Task { [discover, resolver, jobLogs] in
      let scan = await Self.scan(
        discover: discover, resolver: resolver, readers: jobLogs)
      apply(scan, readAt: readAt)
      inFlight = nil
      if refreshRequested {
        refreshRequested = false
        refresh()
      }
    }
  }

  /// The refresh the ticker asks for, which is not the refresh the menu asks
  /// for — and the difference is the whole of the fix.
  ///
  /// A tick is dropped where an explicit request is remembered. Remembering
  /// both, which is what this used to do, is how a `gh` slower than the
  /// interval turned the ticker into a loop: every tick that landed during a
  /// scan left a request pending, so the scan restarted the instant it
  /// finished, and then again, for as long as the network stayed bad. No
  /// pause, an API call per pass, and a radio that never gets to sleep —
  /// spending the most battery exactly when the machine can least afford it.
  ///
  /// Dropping loses nothing. A tick asks for a fresh reading, and a scan
  /// already running is one.
  func tick() {
    guard inFlight == nil else { return }
    // And a reading younger than the interval is one this tick has nothing to
    // add to. `readAt` is when the machine was read rather than when the
    // answer landed, which is what makes it the right clock here: a scan that
    // overran leaves the next tick due the moment it arrives, and that is the
    // same loop by a slower route. It also means a Refresh now pushes the next
    // automatic reading out, which is what a user who has just refreshed
    // wanted.
    if let refreshInterval, let lastReadAt,
      clock().timeIntervalSince(lastReadAt) < refreshInterval
    {
      return
    }
    refresh()
  }

  /// Waits out everything this model has running: actions, the refresh each of
  /// them ends with, and any refresh a running one asked for. The scene never
  /// needs this — it watches `@Published` — but a test does.
  func quiesce() async {
    while true {
      if let action = actions.values.first {
        await action.value
        continue
      }
      guard let refresh = inFlight else { return }
      await refresh.value
    }
  }

  /// Off both pools, and sequential.
  ///
  /// This function is `nonisolated async`, which means it runs on the
  /// cooperative pool — one thread per core, shared with every other `Task` in
  /// the app, main actor included. Nothing that blocks may run here, and both
  /// halves of a scan block: `discover()` reads a directory and two files per
  /// runner, and the resolver parks a thread inside `waitUntilExit()` twice.
  /// Both are handed to `offCooperativePool`, the resolver by way of its own
  /// async facade.
  ///
  /// Sequential because parallelism is not what makes this fast enough — there
  /// are rarely more than a handful of runners, and the coalescing in
  /// `refresh()` is what stops a slow scan from piling up.
  private nonisolated static func scan(
    discover: @escaping @Sendable () -> DiscoveryResult, resolver: RunnerStateResolver,
    readers: [String: JobLogReader]
  ) async -> Scan {
    let found = await offCooperativePool { discover() }
    var states: [RunnerState] = []
    var jobs: [JobHistory] = []
    var readers = readers
    for runner in found.runners {
      states.append(await resolver.state(for: runner))
      // The same rule as discovery, for the same reason: this is file I/O, and
      // the cheap path — a directory listing and a `stat` — is only the usual
      // one. A cold read is hundreds of kilobytes, off a home directory that
      // may well be on a network volume.
      let reader = readers[runner.label] ?? JobLogReader()
      let diagnostics = runner.diagnosticsDirectory
      let read = await offCooperativePool { () -> (JobHistory, JobLogReader) in
        var reader = reader
        return (reader.read(diagnosticsIn: diagnostics), reader)
      }
      jobs.append(read.0)
      readers[runner.label] = read.1
    }
    return Scan(found: found, states: states, jobs: jobs, readers: readers)
  }

  /// One scan's answer. A named type rather than a tuple because it crosses a
  /// thread boundary and has to be `Sendable` where a caller can see it.
  private struct Scan: Sendable {
    let found: DiscoveryResult
    let states: [RunnerState]
    let jobs: [JobHistory]
    let readers: [String: JobLogReader]
  }

  /// - Parameter readAt: when this scan started reading the machine, which is
  ///   not when it finished. The settling window cares a lot — see
  ///   `SettlingWindow.display(_:for:readAt:)` — and so does the elapsed time
  ///   on a running job, which is measured from it.
  private func apply(_ scan: Scan, readAt: Date) {
    let installed = Set(scan.found.runners.map(\.label))
    // A runner that has been uninstalled since it was started would otherwise
    // leave its deadline behind, with nothing left to ever read and clear it.
    settling.keepOnly(installed)
    // And its log reader would hold a few hundred parsed jobs for a runner
    // that no longer exists, for as long as the app runs.
    jobLogs = scan.readers.filter { installed.contains($0.key) }
    watcher.keepOnly(installed)
    let repeated = RunnerSnapshot.repeatedNames(among: scan.found.runners)
    snapshots = zip(scan.found.runners, zip(scan.states, scan.jobs)).map {
      runner, rest in
      RunnerSnapshot(
        runner: runner,
        display: settling.display(rest.0, for: runner.label, readAt: readAt),
        // Only where the name alone would not say which runner this is.
        qualifier: repeated.contains(runner.displayName)
          ? runner.scope.displayName : nil,
        jobs: rest.1,
        readAt: readAt)
    }
    notice = FleetNotice.resolving(
      runners: scan.found.runners, unreadable: scan.found.unreadable)
    lastReadAt = readAt
    // Read from what the menu is about to show rather than from the scan, so a
    // runner the settling window is covering for cannot be announced as
    // disconnected while the menu says it is starting.
    notifications.deliver(watcher.events(in: snapshots))
    sleep.update(busy: snapshots.contains { $0.display.resolvedState == .busy })
  }

  /// Whether some runner's job has already taken longer than that job usually
  /// takes here. What turns the thermal line from a fact about the hardware
  /// into an explanation of what the user is looking at.
  var isOverrunning: Bool {
    snapshots.contains { $0.jobProgress?.isOverTypical == true }
  }

  // MARK: - Acting

  /// The one way the menu acts on a runner, so the view has nothing to wire
  /// up wrongly.
  func perform(_ kind: RunnerRow.Action.Kind, on runner: DiscoveredRunner) {
    switch kind {
    case .start: start(runner)
    case .stop: stop(runner)
    case .restart: restart(runner)
    case .openOnGitHub: openSettings(runner)
    }
  }

  /// No hop anywhere in here: every one of the controller's entry points is
  /// `async` and makes its own, which is where it belongs — the thread a
  /// blocking call needs is the callee's business, not something each caller
  /// has to remember.
  func start(_ runner: DiscoveredRunner) {
    perform(on: runner, thenSettles: true) { controller, directory in
      try await controller.start(in: directory)
    }
  }

  func stop(_ runner: DiscoveredRunner) {
    settling.close(for: runner.label)
    // Told before the command runs rather than after it returns: `svc.sh stop`
    // takes a moment and a scan can land inside it, and a stop this app ordered
    // must never be reported back to the person who ordered it — not even when
    // the reading arrives early.
    watcher.expectStop(for: runner.label)
    perform(on: runner, thenSettles: false) { controller, directory in
      try await controller.stop(in: directory)
    }
  }

  func restart(_ runner: DiscoveredRunner) {
    // A restart takes the service down first, so it looks exactly like a stop
    // to anything reading `launchctl` in the 1.5s gap.
    watcher.expectStop(for: runner.label)
    perform(on: runner, thenSettles: true) { controller, directory in
      try await controller.restart(in: directory)
    }
  }

  func openSettings(_ runner: DiscoveredRunner) {
    NSWorkspace.shared.open(runner.scope.settingsURL)
  }

  private func perform(
    on runner: DiscoveredRunner,
    thenSettles: Bool,
    _ work: @escaping @Sendable (ServiceController, URL) async throws -> Void
  ) {
    let controller = controller
    let directory = runner.directory
    let label = runner.label
    let id = UUID()
    actions[id] = Task {
      var ranSomething = true
      do {
        try await work(controller, directory)
      } catch CommandError.timedOut {
        // The command was killed at the deadline, which says nothing at all
        // about whether it worked. `svc.sh start` is a `launchctl load` and a
        // handful of shell; when it takes more than thirty seconds it is the
        // machine that is slow, and the load has usually already happened —
        // which is precisely when a runner needs the longest to register, and
        // so needs the window most. Treating this as a failure raised the
        // warning triangle over a start that had gone through.
        //
        // A window opened over a start that did not take costs thirty seconds
        // of "Starting…" and then the truth, because the window only ever
        // holds back `.disconnected` and a failed start reports `.stopped`.
        // That is the cheaper of the two mistakes by a wide margin.
      } catch {
        // Nothing ran. A missing `svc.sh` throws before a process is launched,
        // and opening a window here would dress a half-uninstalled runner up
        // as "Starting…" for thirty seconds over an action that never
        // happened.
        ranSomething = false
      }
      if thenSettles && ranSomething { settling.open(for: label, at: clock()) }
      // `svc.sh` returns before launchd has settled, so an immediate re-probe
      // reports the state we just left.
      try? await Task.sleep(for: .seconds(probeDelay))
      refresh()
      actions[id] = nil
    }
  }
}
