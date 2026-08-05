import RunnerKit
import Testing

@testable import RunnerMenubar

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
