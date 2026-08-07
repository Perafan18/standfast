import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let quickMenuNow = Date(timeIntervalSince1970: 1_785_962_174)

private func quickRunner(_ name: String) -> DiscoveredRunner {
  DiscoveredRunner(
    label: "actions.runner.acme-widget.\(name)",
    directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
    agentName: name, scope: .repository(owner: "acme", name: "widget"))
}

private func quickSnapshot(
  _ name: String, _ display: DisplayState, jobs: JobHistory = .empty,
  operation: ServiceOperation? = nil, isServiceActionReserved: Bool = false
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: quickRunner(name), display: display, jobs: jobs, readAt: quickMenuNow,
    isServiceActionReserved: isServiceActionReserved, operation: operation)
}

private func quickMenu(
  _ snapshots: [RunnerSnapshot], notice: FleetNotice? = nil, thermal: [String] = []
) -> QuickMenuPresentation {
  QuickMenuPresentation.building(
    snapshots: snapshots, notice: notice, thermalLines: thermal,
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

// MARK: - Runner echoes

@Test func anEmptyFleetCollapsesToItsAggregateAndFixedRows() {
  // Removing the aggregate row would make an empty menu look like a loading
  // failure rather than the true "nothing installed" state.
  let menu = quickMenu([])

  #expect(
    menu.items == [
      .fleet(L10n.quickMenuFleet(L10n.noRunnersFound)),
      .freshness(L10n.checkedNever),
      .refresh, .openControlCenter, .openSettings, .quit,
    ])
}

@Test func aHealthyIdleRunnerStaysInTheAggregate() {
  // Treating ordinary idle as an echo turns every quiet multi-runner Mac into
  // the long menu this projection exists to prevent.
  let menu = quickMenu([quickSnapshot("idle", .resolved(.idle))])

  #expect(echoes(in: menu).isEmpty)
  #expect(menu.items.first == .fleet(L10n.quickMenuFleet(L10n.stateIdle)))
}

@Test func aBusyRunnerGetsOneProgressEcho() {
  // Dropping busy runners would hide the one job somebody opened the menu to
  // check; the running job is the observable reason the echo appears.
  let job = JobRecord(name: "testflight", startedAt: quickMenuNow.addingTimeInterval(-80))
  let menu = quickMenu([
    quickSnapshot(
      "busy", .resolved(.busy), jobs: JobHistory(records: [job], running: job))
  ])

  let busyEchoes = echoes(in: menu)
  #expect(busyEchoes.count == 1)
  let echo = busyEchoes[0]
  #expect(echo.id == "actions.runner.acme-widget.busy")
  #expect(echo.title == L10n.runnerRow("busy", L10n.stateBusy))
  #expect(echo.progress?.contains("testflight") == true)
  #expect(!echo.canStart)
}

@Test func stoppedAndDisconnectedRunnersEchoButOnlyStoppedCanStart() {
  // A broad canStart flag would offer Start while a disconnected service is
  // already running, which is a destructive duplicate operation.
  let menu = quickMenu([
    quickSnapshot("stopped", .resolved(.stopped)),
    quickSnapshot("offline", .resolved(.disconnected)),
  ])

  #expect(
    echoes(in: menu).map(\.id) == [
      "actions.runner.acme-widget.stopped", "actions.runner.acme-widget.offline",
    ])
  #expect(echoes(in: menu).map(\.canStart) == [true, false])
}

@Test func unknownStartingAndOperationOutcomesRemainVisible() {
  // Losing an operation outcome after the command returns turns the feedback
  // into a silent action; starting must remain visible until GitHub confirms it.
  let operation = ServiceOperation(
    action: .start, phase: .requestAccepted, changedAt: quickMenuNow)
  let menu = quickMenu([
    quickSnapshot("unknown", .resolved(.unknown(.noAnswer))),
    quickSnapshot("starting", .starting),
    quickSnapshot("operation", .resolved(.idle), operation: operation),
  ])

  #expect(
    echoes(in: menu).map(\.id) == [
      "actions.runner.acme-widget.unknown", "actions.runner.acme-widget.operation",
      "actions.runner.acme-widget.starting",
    ])
  #expect(echoes(in: menu)[1].operation == operation.presentation)
}

@Test func anOperationOutcomeOutranksAnOtherwiseStartingRunner() {
  // An operation is actionable feedback, unlike ordinary settling. Leaving it
  // behind starting would hide the command result under a transient state.
  let operation = ServiceOperation(
    action: .start, phase: .requestAccepted, changedAt: quickMenuNow)
  let menu = quickMenu([
    quickSnapshot("starting", .starting, operation: operation),
    quickSnapshot("busy", .resolved(.busy)),
  ])

  #expect(
    echoes(in: menu).map(\.id) == [
      "actions.runner.acme-widget.starting", "actions.runner.acme-widget.busy",
    ])
}

@Test func threeRunnerBudgetKeepsAttentionBeforeWorkAndStarting() {
  // Sorting by name or input alone would let an ordinary active job hide a
  // disconnected runner, which is exactly the triage information this menu
  // is meant to surface.
  let operation = ServiceOperation(
    action: .stop, phase: .requestAccepted, changedAt: quickMenuNow)
  let menu = quickMenu([
    quickSnapshot("starting", .starting),
    quickSnapshot("busy", .resolved(.busy)),
    quickSnapshot("stopped", .resolved(.stopped)),
    quickSnapshot("unknown", .resolved(.unknown(.cliUnavailable))),
    quickSnapshot("offline", .resolved(.disconnected)),
    quickSnapshot("operation", .resolved(.idle), operation: operation),
  ])

  #expect(
    echoes(in: menu).map(\.id) == [
      "actions.runner.acme-widget.stopped", "actions.runner.acme-widget.unknown",
      "actions.runner.acme-widget.offline",
    ])
  #expect(menu.items.first == .fleet(L10n.quickMenuMoreRunners(3)))
}

// MARK: - Bounded shape

@Test func normalQuickMenuNeverExceedsTenNamedRows() {
  // A fourth echo must be summarized, not appended: a menu that needs a
  // scrollbar has failed its three-second glance contract.
  let menu = quickMenu([
    quickSnapshot("one", .resolved(.stopped)),
    quickSnapshot("two", .resolved(.disconnected)),
    quickSnapshot("three", .resolved(.unknown(.noAnswer))),
    quickSnapshot("four", .starting),
  ])

  #expect(menu.namedRowCount <= 10)
  #expect(menu.namedRowCount == 9)
}

@Test func discoveryAndTwoThermalLinesStayWithinTheAlertBudget() {
  // Discovery and thermal information are the only alert rows allowed to add
  // to the normal budget; counting each unreadable path here would overflow it.
  let menu = quickMenu(
    [
      quickSnapshot("one", .resolved(.stopped)),
      quickSnapshot("two", .resolved(.disconnected)),
      quickSnapshot("three", .resolved(.unknown(.noAnswer))),
      quickSnapshot("four", .starting),
    ],
    notice: .unreadable([
      URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b"),
    ]),
    thermal: [L10n.thermalSerious, L10n.thermalSlowingJobs])

  #expect(menu.namedRowCount <= 14)
  #expect(
    menu.items.filter {
      if case .discovery = $0 { return true }
      return false
    }.count == 1)
  #expect(
    menu.items.filter {
      if case .thermal = $0 { return true }
      return false
    }.count == 2)
}

@Test func operationBearingRunnersStayOneTopLevelElementEach() {
  // Runner detail belongs inside one native submenu. Rendering its title,
  // progress, operation feedback, and action as siblings would turn these
  // nine/twelve top-level elements into eighteen/twenty-one menu rows.
  let operation = ServiceOperation(
    action: .start, phase: .requestAccepted, changedAt: quickMenuNow)
  let snapshots = (1...3).map { index in
    let job = JobRecord(
      name: "build-\(index)", startedAt: quickMenuNow.addingTimeInterval(-80))
    return quickSnapshot(
      "runner-\(index)", .resolved(.busy),
      jobs: JobHistory(records: [job], running: job), operation: operation)
  }

  let normal = quickMenu(snapshots)
  let alerted = quickMenu(
    snapshots,
    notice: .unreadable([URL(fileURLWithPath: "/tmp/unreadable")]),
    thermal: [L10n.thermalSerious, L10n.thermalSlowingJobs])
  let runnerMenus: [QuickMenuPresentation.RunnerEcho] =
    normal.emission.elements.compactMap { element in
      guard case .runnerMenu(let runner) = element else { return nil }
      return runner
    }

  #expect(echoes(in: normal).count == 3)
  #expect(runnerMenus.count == 3)
  #expect(runnerMenus.allSatisfy { $0.progress != nil && $0.operation != nil })
  #expect(normal.emission.elements.count == 9)
  #expect(normal.emission.elements.count <= 10)
  #expect(alerted.emission.elements.count == 12)
  #expect(alerted.emission.elements.count <= 14)
}

@Test func emittedItemsContainOnlyQuickActionsAndReadOnlyEchoes() {
  // Reintroducing a row action, history, maintenance, preference toggle, or
  // confirmation here would put a destructive or stateful control back in the
  // menu instead of the Control Center or Settings.
  let menu = quickMenu([
    quickSnapshot(
      "stopped", .resolved(.stopped), isServiceActionReserved: true),
    quickSnapshot("busy", .resolved(.busy)),
  ])

  #expect(
    menu.items == [
      .fleet(L10n.quickMenuFleet(L10n.stateBusy)),
      .runner(
        .init(
          id: "actions.runner.acme-widget.stopped",
          title: L10n.runnerRow("stopped", L10n.stateStopped),
          progress: nil,
          operation: nil,
          canStart: false)),
      .runner(
        .init(
          id: "actions.runner.acme-widget.busy",
          title: L10n.runnerRow("busy", L10n.stateBusy),
          progress: nil,
          operation: nil,
          canStart: false)),
      .freshness(L10n.checkedNever),
      .refresh,
      .openControlCenter,
      .openSettings,
      .quit,
    ])
}
