import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let rankNow = Date(timeIntervalSince1970: 1_785_962_174)

private func rankSnapshot(
  _ name: String, _ display: DisplayState, operation: ServiceOperation? = nil
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: .repository(owner: "acme", name: "widget")),
    display: display, readAt: rankNow, operation: operation)
}

private func rankCard(_ snapshot: RunnerSnapshot) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: rankNow, fleetSize: 1)
}

private func rankCard(
  _ name: String, _ display: DisplayState, operation: ServiceOperation? = nil
) -> RunnerCardPresentation {
  rankCard(rankSnapshot(name, display, operation: operation))
}

/// The Control Center as the model would build it from these snapshots, so the
/// header's count and the Overview's lists come from one fleet.
private func controlCenter(_ snapshots: [RunnerSnapshot]) -> ControlCenterPresentation {
  ControlCenterPresentation(
    header: .building(
      overview: .building(snapshots: snapshots, notice: nil), readAt: nil, now: rankNow),
    cards: snapshots.map(rankCard), empty: nil, notice: nil)
}

private func failed(_ action: ServiceOperationAction = .start) -> ServiceOperation {
  ServiceOperation(action: action, phase: .failed(.scriptMissing), changedAt: rankNow)
}

// MARK: - The rank

@Test func eachStateRanksByHowSoonSomebodyHasToAnswerForIt() {
  let ranks: [(DisplayState, Int)] = [
    (.resolved(.disconnected), 0),
    (.resolved(.unknown(.noAnswer)), 0),
    (.resolved(.unknown(.serviceStateUnreadable)), 0),
    (.resolved(.stopped), 1),
    (.resolved(.busy), 3),
    (.starting, 3),
    // Waiting on its supervisor is a slot working, not one in trouble.
    (.resolved(.unknown(.managedFleetWaiting)), 3),
    (.resolved(.idle), 4),
  ]
  for (display, rank) in ranks {
    #expect(rankCard("build-mac", display).attentionRank == rank, "\(display)")
  }
}

@Test func aFailedOrderRanksWithTheRunnersInTrouble() {
  // A healthy runner whose last Restart failed is a runner somebody has to look
  // at; its green state is only half of what is true about it.
  let card = rankCard("build-mac", .resolved(.idle), operation: failed(.restart))

  #expect(card.needsAttention)
  #expect(card.attentionRank == 0)
}

@Test func anUncertainOrAcceptedOrderDoesNotRaiseTheRunner() {
  // "I do not know whether it worked" is not a failure, and ranking it as one
  // would cry wolf on the outcome this app most often reports.
  for phase in [ServiceOperationPhase.requestAccepted, .uncertain(.commandTimedOut)] {
    let card = rankCard(
      "build-mac", .resolved(.idle),
      operation: ServiceOperation(action: .restart, phase: phase, changedAt: rankNow))
    #expect(!card.needsAttention, "\(phase)")
    #expect(card.attentionRank == 4, "\(phase)")
  }
}

@Test func aStoppedRunnerRanksHighButIsNotCountedAsNeedingAttention() {
  // Stopped is usually somebody's decision. It sorts above the working runners
  // so it is easy to find, and stays out of "needs attention".
  let card = rankCard("build-mac", .resolved(.stopped))

  #expect(!card.needsAttention)
  #expect(card.attentionRank == 1)
}

// MARK: - The Overview's lists

@Test func theOverviewListsRunnersInTroubleFirstThenByName() {
  let presentation = controlCenter([
    rankSnapshot("alpha", .resolved(.idle)),
    rankSnapshot("foxtrot", .resolved(.unknown(.rateLimited))),
    rankSnapshot("bravo", .resolved(.stopped)),
    rankSnapshot("charlie", .resolved(.disconnected)),
    rankSnapshot("delta", .resolved(.busy)),
    rankSnapshot("echo", .resolved(.idle), operation: failed()),
  ])

  #expect(
    presentation.runnersByAttention.map(\.title)
      == ["charlie", "echo", "foxtrot", "bravo", "delta", "alpha"])
  #expect(
    presentation.runnersNeedingAttention.map(\.title) == ["charlie", "echo", "foxtrot"])
  // The lists sort; the cards themselves stay in discovery order.
  #expect(
    presentation.cards.map(\.title)
      == ["alpha", "foxtrot", "bravo", "charlie", "delta", "echo"])
}

@Test func theNeedsAttentionListIsExactlyWhatTheHeaderCounts() {
  // The header says "2 runners need attention" and the section under it has
  // to show two. Filtering by tone would add the stopped runner and drop the
  // healthy one whose Stop failed.
  let presentation = controlCenter([
    rankSnapshot("build-mac", .resolved(.idle), operation: failed(.stop)),
    rankSnapshot("deploy-mac", .resolved(.disconnected)),
    rankSnapshot("gl-docs", .resolved(.stopped)),
    rankSnapshot("test-mac", .resolved(.busy)),
  ])

  #expect(presentation.runnersNeedingAttention.map(\.title) == ["build-mac", "deploy-mac"])
  #expect(presentation.header.attention == L10n.runnerAttention(2))
}

@Test func aFleetWithNothingToAnswerForHasNoAttentionListAndNoHeaderLine() {
  let presentation = controlCenter([
    rankSnapshot("build-mac", .resolved(.idle)),
    rankSnapshot("gl-docs", .resolved(.stopped)),
  ])

  #expect(presentation.runnersNeedingAttention.isEmpty)
  #expect(presentation.header.attention == nil)
}

@Test func namesSortTheWayFinderSortsThem() {
  let presentation = controlCenter([
    rankSnapshot("mac-10", .resolved(.idle)),
    rankSnapshot("Mac-3", .resolved(.idle)),
    rankSnapshot("mac-2", .resolved(.idle)),
  ])

  #expect(presentation.runnersByAttention.map(\.title) == ["mac-2", "Mac-3", "mac-10"])
}

@Test func runnersWithOneNameKeepTheirDiscoveryOrder() {
  let first = RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac",
      directory: URL(fileURLWithPath: "/tmp/widget"), agentId: 7,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "widget")),
    display: .resolved(.idle), readAt: rankNow)
  let second = RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-gadget.build-mac",
      directory: URL(fileURLWithPath: "/tmp/gadget"), agentId: 8,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "gadget")),
    display: .resolved(.idle), readAt: rankNow)

  #expect(
    controlCenter([first, second]).runnersByAttention.map(\.id) == [first.id, second.id])
  #expect(
    controlCenter([second, first]).runnersByAttention.map(\.id) == [second.id, first.id])
}
