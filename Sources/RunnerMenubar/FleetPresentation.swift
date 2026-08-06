import Foundation
import RunnerKit

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
  let actions: [Action]

  struct Action: Equatable {
    let kind: Kind
    let label: String
    let isEnabled: Bool

    enum Kind: Hashable, CaseIterable {
      case start, stop, restart, openOnGitHub
    }
  }

  func action(_ kind: Action.Kind) -> Action? { actions.first { $0.kind == kind } }
}

extension RunnerSnapshot {
  var row: RunnerRow {
    RunnerRow(
      // `displayName`, not `agentName`: the `.runner` file does not always
      // carry a name, and that runner would render as a blank row followed by
      // four buttons belonging to nobody.
      title: L10n.runnerRow(runner.displayName, display.summary),
      // Every action reads this runner's own state. Nothing here consults the
      // fleet summary, which is for the icon and only the icon.
      actions: [
        .init(kind: .start, label: L10n.start, isEnabled: display.canStart),
        .init(kind: .stop, label: L10n.stop, isEnabled: display.canStop),
        .init(kind: .restart, label: L10n.restart, isEnabled: display.canRestart),
        // Always available: a runner GitHub cannot see is the one you most
        // want to go and look at.
        .init(kind: .openOnGitHub, label: L10n.openOnGitHub, isEnabled: true),
      ])
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
    case .unreadable(let paths):
      // The paths themselves, never a count: going and looking at the file is
      // the entire point, the file name alone does not say where it is, and a
      // plist duplicated in Finder describes one runner while appearing twice.
      // The overflow line carries no number for that same reason.
      [L10n.someRunnersUnreadable]
        + paths.prefix(Self.pathsShown).map {
          ($0.path as NSString).abbreviatingWithTildeInPath
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
