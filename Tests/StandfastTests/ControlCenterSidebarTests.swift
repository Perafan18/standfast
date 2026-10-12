import Foundation
import RunnerKit
import Testing

@testable import Standfast

// Titles are compared against the L10n constants: the host may speak Spanish,
// and what is pinned here is which group gets a header and when.

private let sidebarNow = Date(timeIntervalSince1970: 1_785_962_174)

private let gitLabScope = RunnerScope.gitLab(
  instance: GitLabInstance(url: "https://gitlab.example.com")!)

private func sidebarCard(
  _ name: String, scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  installation: RunnerInstallation = .launchAgent,
  display: DisplayState = .resolved(.idle)
) -> RunnerCardPresentation {
  let snapshot = RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: scope, installation: installation),
    display: display, readAt: sidebarNow)
  return RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: sidebarNow, fleetSize: 1)
}

private func gitLabCard(_ name: String) -> RunnerCardPresentation {
  sidebarCard(name, scope: gitLabScope, installation: .gitLabService)
}

private func slotCard(_ name: String) -> RunnerCardPresentation {
  sidebarCard(name, scope: .organization("acme"), installation: .managedFleet)
}

@Test func aMacWithRunnersOnOneServiceGetsNoGroupHeader() {
  // A header over every runner on the Mac says nothing the window title does
  // not, and costs a row at the top of the list.
  let sections = ControlCenterSidebar.grouping(cards: [
    sidebarCard("build-mac"), sidebarCard("test-mac"),
  ])

  #expect(sections.map(\.group) == [.gitHub])
  #expect(sections.map(\.title) == [nil])
  #expect(sections.flatMap(\.cards).map(\.title) == ["build-mac", "test-mac"])
}

@Test func runnersOnTwoServicesAreHeadedByServiceInAFixedOrder() {
  let sections = ControlCenterSidebar.grouping(cards: [
    gitLabCard("gl-docs"), slotCard("slot-1"), sidebarCard("build-mac"),
    gitLabCard("gl-site"), sidebarCard("test-mac"), slotCard("slot-2"),
  ])

  #expect(sections.map(\.group) == [.gitHub, .gitLab, .managedFleet])
  #expect(sections.map(\.title) == [L10n.gitHub, L10n.gitLab, L10n.managedFleet])
  #expect(
    sections.map { $0.cards.map(\.title) } == [
      ["build-mac", "test-mac"], ["gl-docs", "gl-site"], ["slot-1", "slot-2"],
    ])
}

@Test func twoNonEmptyGroupsAreEnoughForHeaders() {
  let sections = ControlCenterSidebar.grouping(cards: [
    slotCard("slot-1"), gitLabCard("gl-docs"),
  ])

  #expect(sections.map(\.group) == [.gitLab, .managedFleet])
  #expect(sections.map(\.title) == [L10n.gitLab, L10n.managedFleet])
}

@Test func aMacWithOnlyFleetSlotsGetsNoHeaderEither() {
  let sections = ControlCenterSidebar.grouping(cards: [slotCard("slot-1")])

  #expect(sections.map(\.group) == [.managedFleet])
  #expect(sections.map(\.title) == [nil])
}

@Test func anEmptyFleetHasNoSidebarGroups() {
  #expect(ControlCenterSidebar.grouping(cards: []).isEmpty)
}

@Test func theSidebarKeepsDiscoveryOrderWhateverEachRunnerIsDoing() {
  // A row that jumps when its runner changes state is a row somebody clicks by
  // mistake. The Overview is the one list that sorts.
  let cards = [
    sidebarCard("alpha", display: .resolved(.idle)),
    sidebarCard("bravo", display: .resolved(.stopped)),
    sidebarCard("charlie", display: .resolved(.disconnected)),
    sidebarCard("delta", display: .resolved(.busy)),
  ]
  let presentation = ControlCenterPresentation(
    header: .building(
      overview: .building(snapshots: [], notice: nil), readAt: nil, now: sidebarNow),
    cards: cards, empty: nil, notice: nil)

  #expect(
    presentation.sidebar.flatMap(\.cards).map(\.title)
      == ["alpha", "bravo", "charlie", "delta"])
  // Otherwise the order above could be a sort that happens to agree.
  #expect(
    presentation.runnersByAttention.map(\.title)
      == ["charlie", "bravo", "delta", "alpha"])
}

@Test func aRunnerIsGroupedByWhoDecidesWhatCanBeDoneToIt() {
  #expect(sidebarCard("build-mac").group == .gitHub)
  #expect(sidebarCard("org-mac", scope: .organization("acme")).group == .gitHub)
  #expect(sidebarCard("by-hand", installation: .manual).group == .gitHub)
  #expect(gitLabCard("gl-docs").group == .gitLab)
  #expect(slotCard("slot-1").group == .managedFleet)
  // A slot registered on GitLab is still its supervisor's.
  #expect(
    sidebarCard("gl-slot", scope: gitLabScope, installation: .managedFleet).group
      == .managedFleet)
}
