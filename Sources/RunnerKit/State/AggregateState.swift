import Foundation

/// Boils several runners down to the one state the menu bar icon can show.
///
/// There is only one icon and there may be any number of runners, so something
/// has to be chosen. The order is by how much each state asks of a human:
/// what needs fixing first, then work in progress, then the quiet states. The
/// menu itself still lists every runner, so nothing is hidden — only ranked.
public enum AggregateState {
  /// Nil for no runners at all. A Mac without runners is not a broken Mac, and
  /// reporting "stopped" would send the user hunting for a service to start
  /// that was never installed in the first place.
  public static func summarising(_ states: [RunnerState]) -> RunnerState? {
    if states.isEmpty { return nil }
    // A definite fault first: `disconnected` is the one state that asks a
    // human to do something now, and it outranks even work in progress — a
    // busy runner is not something anybody acts on. It also outranks
    // `unknown`, where this app only could not see well enough to say.
    if states.contains(.disconnected) { return .disconnected }
    // Something is being built right now: the one thing a person might be
    // waiting on, ahead of the states that merely could not be read.
    if states.contains(.busy) { return .busy }
    // Kept whole rather than rebuilt as a bare `.unknown`: the reason is what
    // lets the menu name the fix, and dropping it here would waste the work
    // done to keep it. Two reasons are deliberate states rather than failures
    // to read — a managed slot between ephemeral registrations and a runner
    // somebody paused in GitLab to drain it — so they wait behind another
    // runner that is already idle. The first actionable unknown wins — with
    // runners failing for different reasons there is no single right headline.
    func isDeliberatelyWaiting(_ state: RunnerState) -> Bool {
      state == .unknown(.managedFleetWaiting) || state == .unknown(.gitLabPaused)
    }
    if let unknown = states.first(where: {
      if case .unknown = $0 { return !isDeliberatelyWaiting($0) }
      return false
    }) {
      return unknown
    }
    // Idle over stopped: "this machine is available" is the more useful
    // headline, and "stopped" would deny it.
    if states.contains(.idle) { return .idle }
    if let waiting = states.first(where: isDeliberatelyWaiting) {
      return waiting
    }
    return .stopped
  }
}
