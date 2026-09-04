import Testing

@testable import RunnerKit

// MARK: - The order of precedence

@Test func busyBeatsEverything() {
  #expect(AggregateState.summarising([.idle, .busy, .stopped]) == .busy)
  #expect(AggregateState.summarising([.disconnected, .busy]) == .busy)
  #expect(AggregateState.summarising([.unknown(.noAnswer), .busy]) == .busy)
}

@Test func disconnectedBeatsIdleBecauseItNeedsAttention() {
  #expect(AggregateState.summarising([.idle, .disconnected]) == .disconnected)
  #expect(AggregateState.summarising([.stopped, .disconnected]) == .disconnected)
}

@Test func unknownOutranksIdleButNotDisconnected() {
  #expect(AggregateState.summarising([.idle, .unknown(.noAnswer)]) == .unknown(.noAnswer))
  #expect(
    AggregateState.summarising([.disconnected, .unknown(.noAnswer)]) == .disconnected)
}

@Test func managedFleetRotationDoesNotOutrankAnotherReadySlot() {
  #expect(
    AggregateState.summarising([.unknown(.managedFleetWaiting), .idle]) == .idle)
  #expect(
    AggregateState.summarising([.unknown(.managedFleetWaiting)])
      == .unknown(.managedFleetWaiting))
}

@Test func idleBeatsStopped() {
  // One runner waiting for work is the more useful headline: it says the
  // machine is available, which "stopped" would deny.
  #expect(AggregateState.summarising([.stopped, .idle]) == .idle)
}

// MARK: - Unanimous inputs

@Test func allStoppedReportsStopped() {
  #expect(AggregateState.summarising([.stopped, .stopped]) == .stopped)
}

@Test func idleWhenEverythingIsFine() {
  #expect(AggregateState.summarising([.idle, .idle]) == .idle)
}

@Test func oneRunnerSummarisesToItself() {
  // Every state, unchanged, so the summary of a one-runner machine — which is
  // most machines — cannot quietly differ from what that runner reports.
  let each: [RunnerState] = [
    .idle, .busy, .disconnected, .stopped,
    .unknown(.cliUnavailable), .unknown(.notAuthenticated), .unknown(.noAnswer),
  ]
  for state in each {
    #expect(AggregateState.summarising([state]) == state)
  }
}

// MARK: - The reason has to survive

@Test func keepsTheReasonOfTheUnknownItReports() {
  // The whole point of UnknownReason is that the menu can name the fix.
  // Collapsing it here would undo that one level up.
  #expect(
    AggregateState.summarising([.idle, .unknown(.cliUnavailable)])
      == .unknown(.cliUnavailable))
  #expect(
    AggregateState.summarising([.idle, .unknown(.notAuthenticated)])
      == .unknown(.notAuthenticated))
}

@Test func reportsTheFirstUnknownWhenRunnersDisagreeOnWhy() {
  // Arbitrary but deliberate: with two different causes there is no single
  // right headline, and the menu lists every runner underneath anyway.
  #expect(
    AggregateState.summarising([.unknown(.cliUnavailable), .unknown(.noAnswer)])
      == .unknown(.cliUnavailable))
  #expect(
    AggregateState.summarising([.unknown(.noAnswer), .unknown(.cliUnavailable)])
      == .unknown(.noAnswer))
}

// MARK: - Nothing to summarise

@Test func noRunnersAtAllIsItsOwnAnswer() {
  // Fresh install on a machine with no runner: the menu must say so instead
  // of implying something is broken. "Stopped" would send the user looking
  // for a service to start that was never installed.
  #expect(AggregateState.summarising([]) == nil)
}
