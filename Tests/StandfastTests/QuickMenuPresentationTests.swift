import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let quickMenuNow = Date(timeIntervalSince1970: 1_785_962_174)

private func quickRunner(
  _ name: String, scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  label: String? = nil, agentId: Int = 7, installation: RunnerInstallation = .launchAgent
) -> DiscoveredRunner {
  DiscoveredRunner(
    label: label ?? "actions.runner.test.\(name)",
    directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: agentId,
    agentName: name, scope: scope, installation: installation)
}

private func quickSnapshot(
  _ name: String, _ display: DisplayState, scope: RunnerScope? = nil,
  label: String? = nil, agentId: Int = 7, jobs: JobHistory = .empty,
  operation: ServiceOperation? = nil, isServiceActionReserved: Bool = false,
  installation: RunnerInstallation = .launchAgent
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: quickRunner(
      name, scope: scope ?? .repository(owner: "acme", name: "widget"),
      label: label, agentId: agentId, installation: installation),
    display: display, jobs: jobs, readAt: quickMenuNow,
    isServiceActionReserved: isServiceActionReserved, operation: operation)
}

private func quickMenu(
  _ snapshots: [RunnerSnapshot], notice: FleetNotice? = nil, thermal: [String] = []
) -> QuickMenuPresentation {
  let overview = FleetOverviewPresentation.building(
    snapshots: snapshots, notice: notice)
  return QuickMenuPresentation.building(
    snapshots: snapshots, overview: overview, thermalLines: thermal,
    readAt: nil, now: quickMenuNow)
}

private func echoes(
  in presentation: QuickMenuPresentation
) -> [QuickMenuPresentation.RunnerEcho] {
  presentation.items.compactMap {
    guard case .runner(let echo) = $0 else { return nil }
    return echo
  }
}

private func discoveryLines(in presentation: QuickMenuPresentation) -> [String] {
  presentation.items.compactMap {
    guard case .discovery(let line) = $0 else { return nil }
    return line
  }
}

// MARK: - Stable runner identity

@Test func oneRunnerUsesItsOwnNameAndShortState() {
  let menu = quickMenu([quickSnapshot("build-mac", .resolved(.idle))])

  #expect(
    echoes(in: menu).map(\.title)
      == ["build-mac · \(L10n.stateReadyShort)"])
}

@Test func duplicateRunnerNamesUseUniqueShortRepositoryNames() {
  let menu = quickMenu([
    quickSnapshot(
      "mac-mini-m4", .resolved(.idle),
      scope: .repository(owner: "acme", name: "widget")),
    quickSnapshot(
      "mac-mini-m4", .resolved(.stopped),
      scope: .repository(owner: "acme", name: "gadget")),
  ])

  #expect(
    echoes(in: menu).map(\.title) == [
      "mac-mini-m4 · widget · \(L10n.stateReadyShort)",
      "mac-mini-m4 · gadget · \(L10n.stateStoppedShort)",
    ])
}

@Test func sameRepositorySlugUnderDifferentOwnersUsesFullScopes() {
  let menu = quickMenu([
    quickSnapshot(
      "mac-mini-m4", .resolved(.idle),
      scope: .repository(owner: "acme", name: "app")),
    quickSnapshot(
      "mac-mini-m4", .resolved(.stopped),
      scope: .repository(owner: "other", name: "app")),
  ])

  #expect(
    echoes(in: menu).map(\.title) == [
      "mac-mini-m4 · acme/app · \(L10n.stateReadyShort)",
      "mac-mini-m4 · other/app · \(L10n.stateStoppedShort)",
    ])
}

@Test func organizationAndEnterpriseCollisionsUseTheirFullScopes() {
  let menu = quickMenu([
    quickSnapshot(
      "mac-mini-m4", .resolved(.idle), scope: .organization("acme-org")),
    quickSnapshot(
      "mac-mini-m4", .resolved(.stopped), scope: .enterprise("acme-enterprise")),
  ])

  #expect(
    echoes(in: menu).map(\.title) == [
      "mac-mini-m4 · acme-org · \(L10n.stateReadyShort)",
      "mac-mini-m4 · acme-enterprise · \(L10n.stateStoppedShort)",
    ])
}

@Test func qualifiedRunnersUseTheScopedPresentationFormatter() {
  let formatting = QuickMenuPresentation.RunnerIdentityFormatting(
    runner: { name, state in "two<\(name)|\(state)>" },
    runnerInScope: { name, scope, state in
      "three<\(name)|\(scope)|\(state)>"
    },
    scopeWithID: { scope, id in "identity<\(scope)|\(id)>" })
  let snapshots = [
    quickSnapshot("solo", .resolved(.idle)),
    quickSnapshot(
      "build", .resolved(.idle),
      scope: .repository(owner: "acme", name: "widget")),
    quickSnapshot(
      "build", .resolved(.stopped),
      scope: .repository(owner: "acme", name: "gadget")),
  ]
  let menu = QuickMenuPresentation.building(
    snapshots: snapshots,
    overview: .building(snapshots: snapshots, notice: nil),
    thermalLines: [], readAt: nil, now: quickMenuNow,
    identityFormatting: formatting)

  #expect(
    echoes(in: menu).map(\.title) == [
      "two<solo|\(L10n.stateReadyShort)>",
      "three<build|widget|\(L10n.stateReadyShort)>",
      "three<build|gadget|\(L10n.stateStoppedShort)>",
    ])
}

@Test func aRepeatedFullScopeUsesTheStableGitHubRunnerID() {
  let first = quickSnapshot(
    "mac-mini-m4", .resolved(.idle),
    scope: .repository(owner: "acme", name: "widget"),
    label: "actions.runner.acme-widget.first", agentId: 123)
  let second = quickSnapshot(
    "mac-mini-m4", .resolved(.idle),
    scope: .repository(owner: "acme", name: "widget"),
    label: "actions.runner.acme-widget.second", agentId: 456)

  #expect(
    echoes(in: quickMenu([first, second])).map(\.title) == [
      "mac-mini-m4 · acme/widget · #123 · \(L10n.stateReadyShort)",
      "mac-mini-m4 · acme/widget · #456 · \(L10n.stateReadyShort)",
    ])
}

@Test func corruptRepeatedGitHubIDsUseStableDiscoveryOrdinals() {
  let first = quickSnapshot(
    "mac-mini-m4", .resolved(.idle),
    scope: .repository(owner: "acme", name: "widget"),
    label: "actions.runner.acme-widget.first", agentId: 123)
  let second = quickSnapshot(
    "mac-mini-m4", .resolved(.idle),
    scope: .repository(owner: "acme", name: "widget"),
    label: "actions.runner.acme-widget.second", agentId: 123)

  #expect(
    echoes(in: quickMenu([first, second])).map(\.title) == [
      "mac-mini-m4 · acme/widget · #1 · \(L10n.stateReadyShort)",
      "mac-mini-m4 · acme/widget · #2 · \(L10n.stateReadyShort)",
    ])
}

@Test func delimiterContainingNamesStayDistinctWhenStatesConverge() {
  let separatedStates = [
    quickSnapshot(
      "build · widget", .resolved(.idle),
      label: "actions.runner.test.delimited", agentId: 101),
    quickSnapshot(
      "build", .resolved(.stopped),
      scope: .repository(owner: "acme", name: "widget"),
      label: "actions.runner.test.widget", agentId: 102),
    quickSnapshot(
      "build", .resolved(.busy),
      scope: .repository(owner: "acme", name: "gadget"),
      label: "actions.runner.test.gadget", agentId: 103),
  ]
  let convergedStates = [
    quickSnapshot(
      "build · widget", .resolved(.idle),
      label: "actions.runner.test.delimited", agentId: 101),
    quickSnapshot(
      "build", .resolved(.idle),
      scope: .repository(owner: "acme", name: "widget"),
      label: "actions.runner.test.widget", agentId: 102),
    quickSnapshot(
      "build", .resolved(.busy),
      scope: .repository(owner: "acme", name: "gadget"),
      label: "actions.runner.test.gadget", agentId: 103),
  ]

  #expect(
    echoes(in: quickMenu(separatedStates)).map(\.title) == [
      "build · widget · #101 · \(L10n.stateReadyShort)",
      "build · widget · #102 · \(L10n.stateStoppedShort)",
      "build · gadget · \(L10n.stateRunningShort)",
    ])
  #expect(
    echoes(in: quickMenu(convergedStates)).map(\.title) == [
      "build · widget · #101 · \(L10n.stateReadyShort)",
      "build · widget · #102 · \(L10n.stateReadyShort)",
      "build · gadget · \(L10n.stateRunningShort)",
    ])
}

@Test func everyRunnerRemainsVisibleInDiscoveryOrderAcrossStates() {
  let snapshots = [
    quickSnapshot("ready", .resolved(.idle)),
    quickSnapshot("starting", .starting),
    quickSnapshot("stopped", .resolved(.stopped)),
    quickSnapshot("running", .resolved(.busy)),
    quickSnapshot("offline", .resolved(.disconnected)),
    quickSnapshot("unknown", .resolved(.unknown(.noAnswer))),
  ]

  #expect(
    echoes(in: quickMenu(snapshots)).map(\.id) == [
      "actions.runner.test.ready",
      "actions.runner.test.starting",
      "actions.runner.test.stopped",
      "actions.runner.test.running",
      "actions.runner.test.offline",
      "actions.runner.test.unknown",
    ])
}

@Test func quickMenuHasNoAggregateFleetItem() {
  let menu = quickMenu([quickSnapshot("ready", .resolved(.idle))])

  guard case .runner(let runner) = menu.items.first else {
    Issue.record("the discovered runner was not the first menu item")
    return
  }
  #expect(runner.id == "actions.runner.test.ready")
}

// MARK: - Runner submenu content

@Test func everyRunnerIsEmittedAsASubmenuEvenWhenIdle() {
  let menu = quickMenu([quickSnapshot("ready", .resolved(.idle))])
  let echo = echoes(in: menu).first

  #expect(echo?.longState == L10n.stateIdle)
  #expect(
    menu.emission.elements.contains {
      if case .runnerMenu = $0 { return true }
      return false
    })
  #expect(menu.emission.elements.count == 6)
}

@Test func runnerSubmenuPreservesProgressOperationAndContextualStart() throws {
  let job = JobRecord(name: "testflight", startedAt: quickMenuNow.addingTimeInterval(-80))
  let operation = ServiceOperation(
    action: .start, phase: .requestAccepted, changedAt: quickMenuNow)
  let menu = quickMenu([
    quickSnapshot(
      "busy", .resolved(.busy),
      jobs: JobHistory(records: [job], running: job), operation: operation),
    quickSnapshot("stopped", .resolved(.stopped)),
    quickSnapshot(
      "reserved", .resolved(.stopped), isServiceActionReserved: true),
  ])

  let runnerEchoes = echoes(in: menu)
  #expect(runnerEchoes.count == 3)
  #expect(runnerEchoes[0].progress?.contains("testflight") == true)
  #expect(runnerEchoes[0].operation == operation.presentation)
  #expect(runnerEchoes.map(\.canStart) == [false, true, false])
  #expect(
    menu.emission.elements.filter {
      if case .runnerMenu = $0 { return true }
      return false
    }.count == 3)
}

@Test func startIsOfferedOnlyOnARunnerStandfastCanStart() {
  // Start is `svc.sh start`, and only a LaunchAgent has one. Offered anywhere
  // else, the click is refused without a word while the Control Center shows
  // the same runner's Start disabled.
  let menu = quickMenu([
    quickSnapshot("service", .resolved(.stopped)),
    quickSnapshot("by-hand", .resolved(.stopped), installation: .manual),
    quickSnapshot(
      "gitlab", .resolved(.stopped),
      scope: .gitLab(instance: GitLabInstance(url: "https://gitlab.example.com")!),
      installation: .gitLabService),
    quickSnapshot("fleet", .resolved(.stopped), installation: .managedFleet),
  ])

  #expect(echoes(in: menu).map(\.canStart) == [true, false, false, false])
}

// MARK: - Discovery summaries

@Test func conclusiveEmptyDiscoveryShowsNoRunnersDirectly() throws {
  let notice = try #require(FleetNotice.resolving(runners: [], unreadable: []))
  let menu = quickMenu([], notice: notice)

  #expect(discoveryLines(in: menu) == [L10n.noRunnersFound])
  #expect(echoes(in: menu).isEmpty)
}

@Test func emptyUnresolvedDiscoverySaysItIsCheckingWithoutClaimingNoRunners() {
  let menu = quickMenu([])

  #expect(discoveryLines(in: menu) == [L10n.checkingRunners])
  #expect(!menu.items.contains(.discovery(L10n.noRunnersFound)))
}

@Test func launchAgentsFailureReportsUnavailableAndNeverClaimsNoRunners() throws {
  let directory = URL(fileURLWithPath: "/tmp/LaunchAgents")
  let notice = try #require(
    FleetNotice.resolving(
      runners: [], unreadable: [],
      failure: .launchAgentsUnreadable(directory)))
  let menu = quickMenu([], notice: notice)

  #expect(
    discoveryLines(in: menu)
      == [L10n.launchAgentsUnreadable + " /tmp/LaunchAgents"])
  #expect(!discoveryLines(in: menu).contains(L10n.noRunnersFound))
}

@Test func unreadableRunnerNoticeNamesAPathAndCompactlySignalsMore() throws {
  let first = URL(fileURLWithPath: "/tmp/actions.runner.a.plist")
  let second = URL(fileURLWithPath: "/tmp/actions.runner.b.plist")
  let notice = try #require(
    FleetNotice.resolving(runners: [], unreadable: [first, second]))
  let menu = quickMenu([], notice: notice)

  #expect(
    discoveryLines(in: menu)
      == [
        L10n.someRunnersUnreadable + " /tmp/actions.runner.a.plist "
          + L10n.moreUnreadable
      ])
  #expect(!discoveryLines(in: menu).contains(L10n.noRunnersFound))
}

@Test func thermalLinesRemainCappedWithoutHidingRunners() {
  let menu = quickMenu(
    (1...5).map { quickSnapshot("runner-\($0)", .resolved(.idle)) },
    thermal: ["one", "two", "three"])

  #expect(echoes(in: menu).count == 5)
  #expect(
    menu.items.filter {
      if case .thermal = $0 { return true }
      return false
    }.count == 2)
}
