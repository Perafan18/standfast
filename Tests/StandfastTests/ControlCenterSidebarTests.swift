import Foundation
import RunnerKit
import Testing

@testable import Standfast

// Titles are compared against the L10n constants: the host may speak Spanish,
// and what is pinned here is which group gets a header and when.

private let sidebarNow = Date(timeIntervalSince1970: 1_785_962_174)

private let gitLabScope = RunnerScope.gitLab(
  instance: GitLabInstance(url: "https://gitlab.example.com")!)

private func sidebarSnapshot(
  _ name: String, scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  installation: RunnerInstallation = .launchAgent,
  display: DisplayState = .resolved(.idle)
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: scope, installation: installation),
    display: display, readAt: sidebarNow)
}

private func sidebarCard(_ snapshot: RunnerSnapshot) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: sidebarNow)
}

private func sidebarCard(
  _ name: String, scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  installation: RunnerInstallation = .launchAgent,
  display: DisplayState = .resolved(.idle)
) -> RunnerCardPresentation {
  sidebarCard(
    sidebarSnapshot(name, scope: scope, installation: installation, display: display))
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

@Test func theOverviewRowCountsWhatOnlyTheOverviewShows() {
  // A selected runner hides the Overview, and with it the runners it says
  // need somebody, discovery's notice and the Mac's heat. The badge is what
  // still says they are there.
  func presentation(
    notice: ControlCenterNoticePresentation?,
    cards: [RunnerCardPresentation] = [sidebarCard("build-mac")]
  ) -> ControlCenterPresentation {
    ControlCenterPresentation(
      header: .building(
        overview: .building(snapshots: [], notice: nil), readAt: nil, now: sidebarNow),
      cards: cards, empty: nil, notice: notice)
  }
  let unreadable = presentation(notice: .unreadableRunners(paths: ["/tmp/a.plist"]))
  let heat = ThermalNotice.lines(pressure: .critical, overrunning: true)

  #expect(presentation(notice: nil).overviewWarningCount(thermalLines: []) == 0)
  #expect(unreadable.overviewWarningCount(thermalLines: []) == 1)
  #expect(
    presentation(notice: .launchAgentsUnavailable(directory: "/tmp/LaunchAgents"))
      .overviewWarningCount(thermalLines: []) == 1)
  // Two lines, one warning: the second only says what the heat is doing.
  #expect(heat.count == 2)
  #expect(presentation(notice: nil).overviewWarningCount(thermalLines: heat) == 1)
  #expect(unreadable.overviewWarningCount(thermalLines: heat) == 2)

  // One for each runner Needs Attention lists, which leaves out a runner
  // somebody stopped on purpose.
  let fleet = [
    sidebarCard("build-mac", display: .resolved(.disconnected)),
    sidebarCard("test-mac", display: .resolved(.unknown(.noAnswer))),
    sidebarCard("idle-mac"),
    sidebarCard("off-mac", display: .resolved(.stopped)),
  ]
  #expect(fleet.filter(\.needsAttention).count == 2)
  #expect(
    presentation(notice: nil, cards: fleet).overviewWarningCount(thermalLines: []) == 2)
  #expect(
    presentation(notice: .unreadableRunners(paths: ["/tmp/a.plist"]), cards: fleet)
      .overviewWarningCount(thermalLines: heat) == 4)
}

@Test func theOverviewRowSaysInWordsWhatItsBadgeCounts() {
  // VoiceOver hears no badge as a warning: it is a number beside the row, and
  // the fleet's summary names neither discovery nor heat.
  let snapshots = [
    sidebarSnapshot("build-mac", display: .resolved(.disconnected)),
    sidebarSnapshot("test-mac"),
  ]
  func presentation(
    notice: ControlCenterNoticePresentation?, snapshots: [RunnerSnapshot]
  ) -> ControlCenterPresentation {
    ControlCenterPresentation(
      header: .building(
        overview: .building(snapshots: snapshots, notice: nil), readAt: nil,
        now: sidebarNow),
      cards: snapshots.map(sidebarCard), empty: nil, notice: notice)
  }
  let warned = presentation(
    notice: .unreadableRunners(paths: ["/tmp/a.plist"]), snapshots: snapshots)
  let heat = ThermalNotice.lines(pressure: .serious, overrunning: false)

  #expect(
    warned.overviewAccessibilityValue(thermalLines: heat)
      == [
        warned.header.summary, L10n.runnerAttention(1), L10n.someRunnersUnreadableTitle,
        L10n.thermalSerious,
      ].joined(separator: ". "))
  // Nothing to warn about: the fleet alone, as the row always said.
  let quiet = presentation(notice: nil, snapshots: [sidebarSnapshot("test-mac")])
  #expect(quiet.overviewAccessibilityValue(thermalLines: []) == quiet.header.summary)

  let source = standfastSource("ControlCenterView.swift")
  #expect(source.contains("presentation.overviewAccessibilityValue("))
  #expect(source.contains(".accessibilityValue(accessibilityValue)"))
  #expect(!source.contains(".accessibilityValue(header.summary)"))
}
