import Foundation
import RunnerKit

// Everything the menu shows, as values a test can read: one runner's state,
// one runner's row, the notice's lines, and the single state the icon carries.
// The views in `App.swift` render these and decide nothing.

/// What one runner's row shows.
///
/// Deliberately not a `RunnerState`. `.starting` is not a state the resolver
/// can ever return: the resolver is stateless and per-runner by design, and
/// what separates a runner that is still registering from one that will never
/// register is the fact that somebody pressed a button three seconds ago.
/// Only the app knows that, so only the app can name this case.
enum DisplayState: Equatable, Sendable {
  case resolved(RunnerState)
  /// Started moments ago; GitHub has not acknowledged it yet.
  case starting

  /// Nil while settling, which is what keeps a runner mid-handshake out of the
  /// menu bar summary instead of counted as the fault it currently looks like.
  var resolvedState: RunnerState? {
    if case .resolved(let state) = self { return state }
    return nil
  }
}

extension DisplayState {
  /// The icon carries the state, because that is the whole point of living in
  /// the menu bar: the answer should be readable without a click.
  var symbolName: String {
    switch self {
    case .resolved(.idle): "checkmark.circle"
    case .resolved(.busy): "gearshape.2.fill"
    case .resolved(.disconnected): "exclamationmark.triangle"
    case .resolved(.stopped): "moon.zzz"
    case .resolved(.unknown): "questionmark.circle"
    case .starting: "arrow.triangle.2.circlepath"
    }
  }

  var summary: String {
    switch self {
    case .resolved(.idle): L10n.stateIdle
    case .resolved(.busy): L10n.stateBusy
    case .resolved(.disconnected): L10n.stateDisconnected
    case .resolved(.stopped): L10n.stateStopped
    case .resolved(.unknown(.cliUnavailable)): L10n.stateUnknownNoCLI
    case .resolved(.unknown(.notAuthenticated)): L10n.stateUnknownNotAuthenticated
    case .resolved(.unknown(.noAnswer)): L10n.stateUnknownNoAnswer
    case .resolved(.unknown(.serviceStateUnreadable)): L10n.stateUnknownNoLocalAnswer
    case .starting: L10n.stateStarting
    }
  }

  /// Whether this runner's LaunchAgent is loaded, which is the only fact the
  /// buttons need.
  ///
  /// Every case but `.stopped` was reached through a `launchctl` that answered
  /// yes: the resolver short-circuits to `.stopped` when the agent is not
  /// loaded, so even `.unknown` — where it is GitHub that went quiet, not the
  /// process — means the service is up.
  ///
  /// The one case that is a guess is `.unknown(.serviceStateUnreadable)`, where
  /// `launchctl` itself is what did not answer. It is guessed *this* way on
  /// purpose: a running runner drawn as stopped loses Stop and Restart, which
  /// is the button bug this unit was written to prevent, while a stopped one
  /// drawn as running merely offers a Stop that does nothing. Enabling all
  /// three instead would mean a row where Start and Stop are lit at once, and
  /// a menu that offers both is a menu that has stopped claiming to know.
  private var isServiceRunning: Bool { self != .resolved(.stopped) }

  /// Read off *this* runner, never off the menu bar summary.
  ///
  /// The summary of one idle runner and one stopped runner is `.idle`, which
  /// is right for the icon and disastrous for a button: gating Start on it
  /// leaves the stopped runner with no way to be started, ever.
  var canStart: Bool { !isServiceRunning }
  var canStop: Bool { isServiceRunning }
  /// Restart is Stop-then-Start, so it needs something to stop. A stopped
  /// runner has Start for that, and offering both would be two buttons for
  /// one outcome.
  var canRestart: Bool { isServiceRunning }
}

/// One runner's slice of the menu, as data.
///
/// Pulled out of the view on purpose. Every bug this unit was written to
/// prevent was a wiring bug — an action gated on the fleet summary, a name
/// read from the wrong field, a count printed instead of a list — and a
/// `View` body is the one thing in this app a test cannot make an assertion
/// about. The view below renders this and decides nothing.
struct RunnerRow: Equatable {
  let title: String
  /// What this runner is building and how long it has been at it, and nil when
  /// it is not building anything.
  let progress: String?
  /// The last requested service-operation outcome, if there is one to report.
  let operation: ServiceOperationPresentation?
  let actions: [Action]
  /// The jobs before this one, newest first.
  let recentJobs: [RecentJob]

  struct Action: Equatable {
    let kind: Kind
    let label: String
    let isEnabled: Bool

    enum Kind: Hashable, CaseIterable {
      case start, stop, restart, openOnGitHub
    }
  }

  /// One finished job. Carries its own identity rather than being rendered by
  /// its text: two runs of the same job that took the same time produce the
  /// same line, and `ForEach` over repeated identifiers is undefined. A start
  /// time is unique per runner because a runner runs one job at a time.
  struct RecentJob: Equatable, Identifiable {
    let id: Date
    let text: String
  }

  /// How many finished jobs the menu lists.
  ///
  /// Five: enough to see whether the last few builds went through, few enough
  /// that the submenu they live in is one glance rather than a scroll. This is
  /// a menu bar, not a log viewer — past five the question is one for GitHub's
  /// own run list, which "Open on GitHub" is two rows above.
  static let recentJobsShown = 5

  func action(_ kind: Action.Kind) -> Action? { actions.first { $0.kind == kind } }
}

extension RunnerSnapshot {
  /// The names carried by more than one runner on this machine.
  ///
  /// `config.sh` proposes the hostname as the runner's name and nearly
  /// everybody presses enter, so one Mac registered against two repositories
  /// arrives here as two runners called `mac-mini-m4` — two identical rows,
  /// each with its own four buttons, and no way to tell which is which. That is
  /// the likeliest multi-runner setup there is, which makes it the one this has
  /// to answer for.
  ///
  /// A question about the fleet, and unanswerable from one runner: whether a
  /// name identifies anything depends entirely on the others. Nothing else
  /// about a row works this way — every button is still read off its own
  /// runner's state, which is what stops a stopped runner from being made
  /// unstartable by a busy neighbour.
  static func repeatedNames(among runners: [DiscoveredRunner]) -> Set<String> {
    let counts = runners.reduce(into: [String: Int]()) { counts, runner in
      counts[runner.displayName, default: 0] += 1
    }
    return Set(counts.filter { $0.value > 1 }.keys)
  }

  /// The name this row leads with: the runner's own, plus where it is
  /// registered when that is what tells it apart from another runner here.
  ///
  /// Only when it is needed. `acme/widget-factory` is most of a menu bar
  /// row's width, and a Mac with one runner gains nothing from carrying it —
  /// there is nothing to disambiguate it from. GitHub will not accept two
  /// runners with the same name in the same scope, so the scope is always
  /// enough to separate the runners that collide.
  var name: String {
    guard let qualifier else { return runner.displayName }
    return L10n.runnerInScope(runner.displayName, qualifier)
  }

  /// What this runner is building, and nil when it is not building anything.
  ///
  /// A property rather than a call at the one place it is rendered, because it
  /// is read twice now: the row prints it, and the thermal line asks whether it
  /// has overrun.
  var jobProgress: JobProgress? {
    JobProgress.reading(jobs, display: display, at: readAt)
  }

  var row: RunnerRow {
    RunnerRow(
      // `displayName`, not `agentName`: the `.runner` file does not always
      // carry a name, and that runner would render as a blank row followed by
      // four buttons belonging to nobody.
      title: L10n.runnerRow(name, display.summary),
      progress: jobProgress?.line,
      operation: operation?.presentation,
      // Every action reads this runner's own state. Nothing here consults the
      // fleet summary, which is for the icon and only the icon.
      actions: [
        .init(
          kind: .start, label: L10n.start,
          isEnabled: display.canStart && !isServiceActionReserved),
        .init(
          kind: .stop, label: L10n.stop,
          isEnabled: display.canStop && !isServiceActionReserved),
        .init(
          kind: .restart, label: L10n.restart,
          isEnabled: display.canRestart && !isServiceActionReserved),
        // Always available: a runner GitHub cannot see is the one you most
        // want to go and look at.
        .init(kind: .openOnGitHub, label: L10n.openOnGitHub, isEnabled: true),
      ],
      recentJobs: jobs.records
        // The running job already has a line of its own, with the one thing
        // this list cannot give it: how long it has been going.
        .filter { $0 != jobs.running }
        .prefix(RunnerRow.recentJobsShown)
        .map { RunnerRow.RecentJob(id: $0.startedAt, text: $0.historyLine) })
  }
}

extension FleetNotice {
  /// How many paths the menu will print before it stops.
  ///
  /// A menu bar menu that runs off the screen is not more informative than one
  /// that does not. Ten is far past any real machine and still short of a
  /// directory somebody has been copying plists around in.
  static let pathsShown = 10

  /// The lines this notice puts in the menu, in order.
  var lines: [String] {
    switch self {
    case .noRunnersInstalled:
      [L10n.noRunnersFound]
    case .launchAgentsUnreadable(let directory):
      [L10n.launchAgentsUnreadable, PathText.abbreviated(directory)]
    case .unreadable(let paths):
      // The paths themselves, never a count: going and looking at the file is
      // the entire point, the file name alone does not say where it is, and a
      // plist duplicated in Finder describes one runner while appearing twice.
      // The overflow line carries no number for that same reason.
      [L10n.someRunnersUnreadable]
        + paths.prefix(Self.pathsShown).map {
          PathText.abbreviated($0)
        }
        + (paths.count > Self.pathsShown ? [L10n.moreUnreadable] : [])
    }
  }
}

/// The single state the menu bar icon shows for the whole machine.
enum FleetSummary {
  /// Nothing installed. Its own symbol rather than the unknown question mark:
  /// a Mac with no runners is not a Mac this app failed to read, and the two
  /// have completely different answers.
  static let noRunnersSymbolName = "circle.dashed"

  /// Nil when there is nothing at all to summarise.
  static func summarising(_ displays: [DisplayState]) -> DisplayState? {
    guard !displays.isEmpty else { return nil }
    // Settling runners are held out of the aggregate rather than folded into
    // it. What they resolve to right now is the `.disconnected` this app has
    // decided not to believe yet, and letting it through the back door would
    // raise the warning triangle over a start that is going fine.
    let known = displays.compactMap(\.resolvedState)
    guard let aggregate = AggregateState.summarising(known) else { return .starting }
    return .resolved(aggregate)
  }

  static func symbolName(for displays: [DisplayState]) -> String {
    summarising(displays)?.symbolName ?? noRunnersSymbolName
  }
}
