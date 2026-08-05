import Foundation

/// Boils several runners down to the one state the menu bar icon can show.
///
/// There is only one icon and there may be any number of runners, so something
/// has to be chosen. The order is by how much each state asks of a human:
/// work in progress first, then what needs fixing, then the quiet states. The
/// menu itself still lists every runner, so nothing is hidden — only ranked.
public enum AggregateState {
  /// Nil for no runners at all. A Mac without runners is not a broken Mac, and
  /// reporting "stopped" would send the user hunting for a service to start
  /// that was never installed in the first place.
  public static func summarising(_ states: [RunnerState]) -> RunnerState? {
    if states.isEmpty { return nil }
    // Something is being built right now: the one thing a person might be
    // waiting on, so it outranks even the problems.
    if states.contains(.busy) { return .busy }
    // Then the states that need a human. `disconnected` outranks `unknown`
    // because it is a definite fault, where unknown only means this app could
    // not see well enough to say.
    if states.contains(.disconnected) { return .disconnected }
    // Kept whole rather than rebuilt as a bare `.unknown`: the reason is what
    // lets the menu name the fix, and dropping it here would waste the work
    // done to keep it. The first one wins — with runners failing for different
    // reasons there is no single right headline.
    if let unknown = states.first(where: { if case .unknown = $0 { true } else { false } })
    {
      return unknown
    }
    // Idle over stopped: "this machine is available" is the more useful
    // headline, and "stopped" would deny it.
    if states.contains(.idle) { return .idle }
    return .stopped
  }
}
