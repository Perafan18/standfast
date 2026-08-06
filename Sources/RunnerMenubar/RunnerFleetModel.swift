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
  var id: String { runner.label }

  init(runner: DiscoveredRunner, display: DisplayState, qualifier: String? = nil) {
    self.runner = runner
    self.display = display
    self.qualifier = qualifier
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

  private let discover: @Sendable () -> DiscoveryResult
  private let resolver: RunnerStateResolver
  private let controller: ServiceController
  private let clock: @Sendable () -> Date
  private let probeDelay: TimeInterval
  private var settling: SettlingWindow
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
    self.clock = clock
    self.probeDelay = probeDelay
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
        refresh()
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
    inFlight = Task { [discover, resolver] in
      let scan = await Self.scan(discover: discover, resolver: resolver)
      apply(scan, readAt: readAt)
      inFlight = nil
      if refreshRequested {
        refreshRequested = false
        refresh()
      }
    }
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
    discover: @escaping @Sendable () -> DiscoveryResult, resolver: RunnerStateResolver
  ) async -> (found: DiscoveryResult, states: [RunnerState]) {
    let found = await offCooperativePool { discover() }
    var states: [RunnerState] = []
    for runner in found.runners { states.append(await resolver.state(for: runner)) }
    return (found, states)
  }

  /// - Parameter readAt: when this scan started reading the machine, which is
  ///   not when it finished. Only the settling window cares, and it cares a
  ///   lot: see `SettlingWindow.display(_:for:readAt:)`.
  private func apply(
    _ scan: (found: DiscoveryResult, states: [RunnerState]), readAt: Date
  ) {
    // A runner that has been uninstalled since it was started would otherwise
    // leave its deadline behind, with nothing left to ever read and clear it.
    settling.keepOnly(Set(scan.found.runners.map(\.label)))
    let repeated = RunnerSnapshot.repeatedNames(among: scan.found.runners)
    snapshots = zip(scan.found.runners, scan.states).map { runner, state in
      RunnerSnapshot(
        runner: runner,
        display: settling.display(state, for: runner.label, readAt: readAt),
        // Only where the name alone would not say which runner this is.
        qualifier: repeated.contains(runner.displayName) ? runner.scope.displayName : nil)
    }
    notice = FleetNotice.resolving(
      runners: scan.found.runners, unreadable: scan.found.unreadable)
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
    perform(on: runner, thenSettles: false) { controller, directory in
      try await controller.stop(in: directory)
    }
  }

  func restart(_ runner: DiscoveredRunner) {
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
      var succeeded = true
      do {
        try await work(controller, directory)
      } catch {
        // Nowhere to put this, and two different things arrive here: a missing
        // `svc.sh`, where nothing ran at all, and `CommandError.timedOut`,
        // where the command was killed after 30s having quite possibly already
        // done its work. The second one costs a settling window that should
        // have opened, so a start that is going fine can still be reported as
        // `.disconnected`. Accepted for now over the alternative — opening a
        // window for an action that never happened, which would dress a
        // half-uninstalled runner up as "Starting…" for thirty seconds. The
        // re-probe below is the only honest report either way.
        succeeded = false
      }
      if thenSettles && succeeded { settling.open(for: label, at: clock()) }
      // `svc.sh` returns before launchd has settled, so an immediate re-probe
      // reports the state we just left.
      try? await Task.sleep(for: .seconds(probeDelay))
      refresh()
      actions[id] = nil
    }
  }
}
