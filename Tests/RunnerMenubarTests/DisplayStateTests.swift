import RunnerKit
import Testing

@testable import RunnerMenubar

/// Every state a row can be in, so a new one cannot be added without a test
/// failing until it is given copy and button rules.
private let everyDisplayState: [DisplayState] = [
  .resolved(.idle), .resolved(.busy), .resolved(.disconnected), .resolved(.stopped),
  .resolved(.unknown(.cliUnavailable)), .resolved(.unknown(.notAuthenticated)),
  .resolved(.unknown(.noAnswer)), .resolved(.unknown(.serviceStateUnreadable)),
  .starting,
]

// MARK: - What each state says
//
// Compared against the L10n constants rather than against literal English:
// this Mac runs in Spanish, so the literals would only be testing which
// language the test host booted in. What is worth pinning is the wiring —
// which state reaches which line — and that is language-independent.

@Test func eachStateSaysItsOwnThing() {
  #expect(DisplayState.resolved(.idle).summary == L10n.stateIdle)
  #expect(DisplayState.resolved(.busy).summary == L10n.stateBusy)
  #expect(DisplayState.resolved(.disconnected).summary == L10n.stateDisconnected)
  #expect(DisplayState.resolved(.stopped).summary == L10n.stateStopped)
  #expect(DisplayState.starting.summary == L10n.stateStarting)
}

@Test func eachUnknownReasonGetsItsOwnLine() {
  // The whole reason `UnknownReason` carries four cases: the fix differs, and
  // one shared "could not tell" would leave the user with nothing to try.
  #expect(
    DisplayState.resolved(.unknown(.cliUnavailable)).summary == L10n.stateUnknownNoCLI)
  #expect(
    DisplayState.resolved(.unknown(.notAuthenticated)).summary
      == L10n.stateUnknownNotAuthenticated)
  #expect(
    DisplayState.resolved(.unknown(.noAnswer)).summary == L10n.stateUnknownNoAnswer)
  #expect(
    DisplayState.resolved(.unknown(.serviceStateUnreadable)).summary
      == L10n.stateUnknownNoLocalAnswer)
}

@Test func noTwoStatesReadTheSame() {
  let summaries = Set(everyDisplayState.map(\.summary))
  #expect(summaries.count == everyDisplayState.count)
  #expect(!summaries.contains(""))
}

@Test func eachStateHasItsOwnIcon() {
  // Except the three unknowns, which share one on purpose — the icon says
  // "could not tell" and the menu line says why.
  #expect(DisplayState.resolved(.idle).symbolName == "checkmark.circle")
  #expect(DisplayState.resolved(.busy).symbolName == "gearshape.2.fill")
  #expect(DisplayState.resolved(.disconnected).symbolName == "exclamationmark.triangle")
  #expect(DisplayState.resolved(.stopped).symbolName == "moon.zzz")
  #expect(DisplayState.resolved(.unknown(.noAnswer)).symbolName == "questionmark.circle")
  #expect(DisplayState.starting.symbolName != DisplayState.resolved(.idle).symbolName)
  #expect(!everyDisplayState.contains { $0.symbolName.isEmpty })
}

// MARK: - Which buttons a row offers

@Test func onlyAStoppedRunnerCanBeStarted() {
  for state in everyDisplayState {
    #expect(state.canStart == (state == .resolved(.stopped)))
  }
}

@Test func aRunningRunnerCanBeStoppedAndRestarted() {
  for state in everyDisplayState where state != .resolved(.stopped) {
    #expect(state.canStop)
    #expect(state.canRestart)
  }
}

@Test func aStoppedRunnerOffersNeitherStopNorRestart() {
  // Restart is stop-then-start and needs something to stop; Start is already
  // the button for this row.
  #expect(!DisplayState.resolved(.stopped).canStop)
  #expect(!DisplayState.resolved(.stopped).canRestart)
}

@Test func anUnknownRunnerCanStillBeStoppedAndRestarted() {
  // `unknown` never means the process is known to be down: for three of the
  // four reasons it is GitHub that went quiet, and the resolver short-circuits
  // to `.stopped` before it ever asks GitHub. The fourth, where `launchctl`
  // itself did not answer, is a guess — deliberately this one, because a live
  // runner with Stop and Restart greyed out is the failure that matters.
  for reason: UnknownReason in [
    .cliUnavailable, .notAuthenticated, .noAnswer, .serviceStateUnreadable,
  ] {
    #expect(!DisplayState.resolved(.unknown(reason)).canStart)
    #expect(DisplayState.resolved(.unknown(reason)).canStop)
    #expect(DisplayState.resolved(.unknown(reason)).canRestart)
  }
}

@Test func aSettlingRunnerCanBeStoppedButNotStartedAgain() {
  #expect(!DisplayState.starting.canStart)
  #expect(DisplayState.starting.canStop)
}
