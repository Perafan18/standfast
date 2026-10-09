import RunnerKit
import Testing

@testable import Standfast

/// Every state a row can be in, so a new one cannot be added without a test
/// failing until it is given copy and button rules.
private let everyDisplayState: [DisplayState] = [
  .resolved(.idle), .resolved(.busy), .resolved(.disconnected), .resolved(.stopped),
  .resolved(.unknown(.cliUnavailable)), .resolved(.unknown(.notAuthenticated)),
  .resolved(.unknown(.noAnswer)), .resolved(.unknown(.serviceStateUnreadable)),
  .resolved(.unknown(.tokenRefused)), .resolved(.unknown(.tokenUnreadable)),
  .resolved(.unknown(.gitLabTokenUnreadable)), .resolved(.unknown(.gitLabPaused)),
  .resolved(.unknown(.gitLabInsecure)),
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

@Test func eachStateHasTheExactCompactVocabulary() {
  #expect(DisplayState.resolved(.idle).shortSummary == L10n.stateReadyShort)
  #expect(DisplayState.resolved(.busy).shortSummary == L10n.stateRunningShort)
  #expect(
    DisplayState.resolved(.disconnected).shortSummary
      == L10n.stateDisconnectedShort)
  #expect(DisplayState.resolved(.stopped).shortSummary == L10n.stateStoppedShort)
  #expect(DisplayState.starting.shortSummary == L10n.stateStartingShort)
  // The unknown states have their own rule, and their own test below: the
  // badge names the layer that went quiet rather than sharing one word.
}

@Test func stateToneDoesNotCollapseStateOrAttentionSemantics() {
  #expect(DisplayState.resolved(.idle).tone == .healthy)
  #expect(DisplayState.resolved(.busy).tone == .active)
  #expect(DisplayState.resolved(.disconnected).tone == .attention)
  #expect(DisplayState.resolved(.stopped).tone == .stopped)
  #expect(DisplayState.starting.tone == .active)
  #expect(DisplayState.resolved(.unknown(.noAnswer)).tone == .attention)

  #expect(DisplayState.resolved(.disconnected).needsAttention)
  #expect(DisplayState.resolved(.unknown(.cliUnavailable)).needsAttention)
  #expect(!DisplayState.resolved(.stopped).needsAttention)
  #expect(!DisplayState.resolved(.busy).needsAttention)
}

@Test func eachUnknownReasonGetsItsOwnLine() {
  // The whole reason `UnknownReason` carries a case per fix: the fix differs, and
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
  #expect(
    DisplayState.resolved(.unknown(.noToken)).summary == L10n.stateUnknownNoToken)
  #expect(
    DisplayState.resolved(.unknown(.rateLimited)).summary
      == L10n.stateUnknownRateLimited)
  #expect(
    DisplayState.resolved(.unknown(.tokenRefused)).summary
      == L10n.stateUnknownTokenRefused)
  #expect(
    DisplayState.resolved(.unknown(.tokenUnreadable)).summary
      == L10n.stateUnknownTokenUnreadable)
  #expect(
    DisplayState.resolved(.unknown(.gitLabTokenUnreadable)).summary
      == L10n.stateUnknownGitLabTokenUnreadable)
  #expect(
    DisplayState.resolved(.unknown(.gitLabPaused)).summary
      == L10n.stateUnknownGitLabPaused)
  #expect(
    DisplayState.resolved(.unknown(.gitLabInsecure)).summary
      == L10n.stateUnknownGitLabInsecure)
}

@Test func aRefusedTokenNeverSendsTheUserToGh() {
  // With a token stored `gh` is never run, so a line naming it points at a fix
  // that cannot work.
  let state = DisplayState.resolved(.unknown(.tokenRefused))
  for line in [state.summary, state.shortSummary] {
    #expect(line.range(of: #"\bgh\b"#, options: .regularExpression) == nil, "\(line)")
  }
  #expect(state.shortSummary == L10n.stateLayerGitHubRefusedToken)
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
    .cliUnavailable, .notAuthenticated, .noAnswer, .serviceStateUnreadable, .tokenRefused,
    .tokenUnreadable,
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

@Test func onlyAConnectedRunnerIsGoingToBeHandedWork() {
  // Not a synonym for `needsAttention`. A runner somebody stopped on purpose
  // raises no alarm and still will not pick up what is queued for it, and that
  // gap is the one the queued-work line exists to fill.
  #expect(DisplayState.resolved(.idle).canReceiveWork)
  #expect(DisplayState.resolved(.busy).canReceiveWork)
  #expect(DisplayState.starting.canReceiveWork)
  #expect(!DisplayState.resolved(.stopped).canReceiveWork)
  #expect(!DisplayState.resolved(.disconnected).canReceiveWork)
  #expect(!DisplayState.resolved(.unknown(.noAnswer)).canReceiveWork)
  // The one that would otherwise look like the same predicate.
  #expect(!DisplayState.resolved(.stopped).needsAttention)
}

@Test func theBadgeNamesTheLayerThatWentQuietRatherThanShrugging() {
  // The rest of UI-034. D-R16 gave the long sentence a stable grammar for the
  // two layers — "running locally, GitHub not answering" — and left the badge
  // beside it saying `Unknown` for both. Codex, reading the screenshots
  // without the repository: *"the layers were named where it hurt; there is
  // still no visible, stable grammar for all of them."*
  //
  // Every reason GitHub can be quiet for is one layer. The local probe
  // refusing is the other, and its instruction points somewhere else entirely.
  for reason in [UnknownReason.cliUnavailable, .notAuthenticated, .noAnswer] {
    #expect(
      DisplayState.resolved(.unknown(reason)).shortSummary
        == L10n.stateLayerGitHubSilent)
  }
  // Not "not answering" for these two: nothing was asked in the first, and
  // GitHub answered very clearly in the second.
  #expect(
    DisplayState.resolved(.unknown(.noToken)).shortSummary
      == L10n.stateLayerGitHubNotAsked)
  #expect(
    DisplayState.resolved(.unknown(.rateLimited)).shortSummary
      == L10n.stateLayerGitHubRateLimited)
  #expect(
    DisplayState.resolved(.unknown(.serviceStateUnreadable)).shortSummary
      == L10n.stateLayerLocalUnreadable)
  // A Keychain that withheld the token means nothing was sent to either host.
  #expect(
    DisplayState.resolved(.unknown(.tokenUnreadable)).shortSummary
      == L10n.stateLayerGitHubNotAsked)
  #expect(
    DisplayState.resolved(.unknown(.gitLabTokenUnreadable)).shortSummary
      == L10n.stateLayerGitLabNotAsked)
  // Nor does an instance served over http, which is never sent the token.
  #expect(
    DisplayState.resolved(.unknown(.gitLabInsecure)).shortSummary
      == L10n.stateLayerGitLabNotAsked)
  // GitLab answered, and very clearly: neither "not asked" nor "not answering".
  #expect(
    DisplayState.resolved(.unknown(.gitLabPaused)).shortSummary
      == L10n.stateLayerGitLabPaused)
}

@Test func aRunnerPausedInGitLabTakesNoWorkAndKeepsItsServiceButtons() {
  // Paused in GitLab is not stopped here: the service is the one running, so
  // Stop and Restart stay. What it will not do is take the job waiting for it.
  let paused = DisplayState.resolved(.unknown(.gitLabPaused))

  #expect(!paused.canReceiveWork)
  #expect(paused.canStop && paused.canRestart && !paused.canStart)
}
