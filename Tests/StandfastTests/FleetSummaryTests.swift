import RunnerKit
import Testing

@testable import Standfast

// MARK: - The icon is the only thing the summary drives

@Test func summaryFollowsTheAggregateOfWhatIsKnown() {
  #expect(
    FleetSummary.summarising([.resolved(.idle), .resolved(.busy)]) == .resolved(.busy))
  #expect(
    FleetSummary.summarising([.resolved(.idle), .resolved(.stopped)])
      == .resolved(.idle))
  #expect(
    FleetSummary.summarising([.resolved(.idle), .resolved(.disconnected)])
      == .resolved(.disconnected))
}

@Test func aSettlingRunnerDoesNotDragTheIconIntoAWarning() {
  // The point of the settling window, one level up. The runner is reporting
  // `.disconnected` underneath; letting that reach the aggregate would raise
  // the warning triangle over a start that is going fine.
  #expect(
    FleetSummary.summarising([.starting, .resolved(.idle)]) == .resolved(.idle))
  #expect(
    FleetSummary.summarising([.starting, .resolved(.stopped)]) == .resolved(.stopped))
}

@Test func settlingIsTheAnswerWhenNothingElseIsKnown() {
  // Every runner on the machine was just started. There is no resolved state
  // to summarise, and the aggregate's own "nothing here" answer would show the
  // icon for a Mac with no runners installed.
  #expect(FleetSummary.summarising([.starting]) == .starting)
  #expect(FleetSummary.summarising([.starting, .starting]) == .starting)
}

@Test func noRunnersHasNoSummary() {
  #expect(FleetSummary.summarising([]) == nil)
}

// MARK: - Aggregate accessibility

@Test func everyAggregateStateHasLocalizedAccessibilitySpeech() {
  // A missing case here leaves the menu-bar image with a status glyph VoiceOver
  // can name but no value to explain, including the common no-runners setup.
  let cases: [(DisplayState?, String)] = [
    (nil, L10n.noRunnersFound),
    (.resolved(.idle), L10n.stateIdle),
    (.resolved(.busy), L10n.stateBusy),
    (.resolved(.disconnected), L10n.stateDisconnected),
    (.resolved(.stopped), L10n.stateStopped),
    (.resolved(.unknown(.cliUnavailable)), L10n.stateUnknownNoCLI),
    (.resolved(.unknown(.notAuthenticated)), L10n.stateUnknownNotAuthenticated),
    (.resolved(.unknown(.noAnswer)), L10n.stateUnknownNoAnswer),
    (.resolved(.unknown(.serviceStateUnreadable)), L10n.stateUnknownNoLocalAnswer),
    (.starting, L10n.stateStarting),
  ]

  for (state, expected) in cases {
    let value = FleetSummary.accessibilityValue(for: state)
    #expect(value == expected)
    #expect(!value.isEmpty)
  }
}

// MARK: - Symbols

@Test func aMacWithNoRunnersDoesNotLookLikeAFailure() {
  // Distinct from the unknown question mark: "nothing installed" and "could
  // not tell" send the user to two completely different places.
  #expect(FleetSummary.symbolName(for: []) == FleetSummary.noRunnersSymbolName)
  #expect(
    FleetSummary.noRunnersSymbolName
      != DisplayState.resolved(.unknown(.noAnswer)).symbolName)
}

@Test func theIconIsTheSummarysIcon() {
  #expect(
    FleetSummary.symbolName(for: [.resolved(.idle), .resolved(.busy)])
      == DisplayState.resolved(.busy).symbolName)
  #expect(FleetSummary.symbolName(for: [.starting]) == DisplayState.starting.symbolName)
}
