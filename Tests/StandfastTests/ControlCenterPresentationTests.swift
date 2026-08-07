import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let controlCenterNow = Date(timeIntervalSince1970: 1_785_962_174)

private func standfastSource(_ name: String) -> String {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = repository.appendingPathComponent("Sources/Standfast/\(name)")
  return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
}

private func controlCenterSnapshot(
  _ display: DisplayState = .resolved(.idle),
  scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  jobs: JobHistory = .empty, operation: ServiceOperation? = nil,
  version: RunnerVersion? = nil, qualifier: String? = nil,
  isJobHistoryAvailable: Bool = true, isServiceActionReserved: Bool = false
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac",
      directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
      agentName: "build-mac", scope: scope),
    display: display, qualifier: qualifier, jobs: jobs, readAt: controlCenterNow,
    isJobHistoryAvailable: isJobHistoryAvailable, version: version,
    isServiceActionReserved: isServiceActionReserved, operation: operation)
}

private func card(
  _ snapshot: RunnerSnapshot, measurement: DiskMeasurement? = nil,
  latestRelease: RunnerVersion? = nil
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    snapshot, measurement: measurement, latestRelease: latestRelease,
    isMaintenanceWorking: false, maintenanceNotice: nil, now: controlCenterNow)
}

@MainActor
private struct PresentationConfirmation: CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> Bool { false }
}

@MainActor
private func presentationModel(
  _ sandbox: FleetSandbox, diskCommands: RecordingCommandRunner = RecordingCommandRunner()
) -> RunnerFleetModel {
  let housekeeping = HousekeepingModel(
    usage: DiskUsage(commandRunner: diskCommands),
    housekeeper: Housekeeper(files: PresentationUntouchableFiles()),
    confirmation: PresentationConfirmation(), probe: { _ in .busy })
  return RunnerFleetModel(
    discover: sandbox.discover, resolver: sandbox.resolver,
    controller: ServiceController(commandRunner: RecordingCommandRunner()),
    notifications: NotificationSettings(
      delivery: FakeNotificationDelivery(), defaults: scratchDefaults()),
    sleep: SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults()),
    housekeeping: housekeeping, versions: sandbox.versions, releases: sandbox.releases,
    opener: FakeURLOpener(), serviceConfirmation: RejectingServiceConfirmation(),
    refreshInterval: nil)
}

private struct PresentationUntouchableFiles: DestructiveFileOperations {
  func createDirectory(at url: URL) throws {}
  func move(_ url: URL, to destination: URL) throws {}
  func remove(_ url: URL) throws {}
}

// MARK: - Stable accessibility identity

@Test func controlCenterAccessibilityRootsAreStableAndNonlocalized() {
  #expect(ControlCenterAccessibility.header == "dev.standfast.control-center.header")
  #expect(ControlCenterAccessibility.refresh == "dev.standfast.control-center.refresh")
  #expect(ControlCenterAccessibility.notice == "dev.standfast.control-center.notice")
}

@Test func runnerAccessibilityIDsUseReversibleUTF8InsteadOfRuntimeHashing() {
  let first = ControlCenterAccessibility.runner("a/b")
  let repeated = ControlCenterAccessibility.runner("a/b")

  #expect(first == repeated)
  #expect(first.card == "dev.standfast.control-center.runner.612f62.card")
  #expect(first.status == "dev.standfast.control-center.runner.612f62.status")
  #expect(first.focus == "dev.standfast.control-center.runner.612f62.focus")
  #expect(first.start.hasSuffix(".action.start"))
  #expect(first.stop.hasSuffix(".action.stop"))
  #expect(first.restart.hasSuffix(".action.restart"))
  #expect(first.github.hasSuffix(".github"))
  #expect(first.jobs.hasSuffix(".jobs"))
  #expect(first.maintenance.hasSuffix(".maintenance"))
}

@Test func trickyDurableLabelsProduceUniqueAccessibilityNamespaces() {
  let labels = ["runner.a/b", "runner/a.b", "ñ", "n\u{0303}", "🔥", "A B", ""]
  let identifiers = labels.map { ControlCenterAccessibility.runner($0).card }

  #expect(Set(identifiers).count == labels.count)
}

@Test func jobAccessibilityIDsUseAStableLocaleIndependentTimestamp() {
  let runner = ControlCenterAccessibility.runner("a/b")
  let instant = Date(timeIntervalSinceReferenceDate: 123.5)

  #expect(
    runner.job(JobRow.ID(startedAt: instant, occurrence: 0))
      == "dev.standfast.control-center.runner.612f62.jobs.job.405ee00000000000.0")
}

@Test func sameSecondHistoryRowsKeepUniqueDeterministicAXIDs() {
  let startedAt = controlCenterNow.addingTimeInterval(-3_600)
  let records = [
    JobRecord(
      name: "first", startedAt: startedAt,
      finishedAt: startedAt.addingTimeInterval(10), result: .succeeded),
    JobRecord(
      name: "second", startedAt: startedAt,
      finishedAt: startedAt.addingTimeInterval(20), result: .failed),
  ]
  let firstCard = card(controlCenterSnapshot(jobs: JobHistory(records: records)))
  let secondCard = card(controlCenterSnapshot(jobs: JobHistory(records: records)))
  guard case .available(let firstRows, false) = firstCard.history,
    case .available(let secondRows, false) = secondCard.history
  else {
    Issue.record("same-second jobs did not reach available history")
    return
  }
  let identifiers = ControlCenterAccessibility.runner(firstCard.id)
  let firstIDs = firstRows.map { identifiers.job($0.id) }
  let secondIDs = secondRows.map { identifiers.job($0.id) }

  #expect(firstRows.count == 2)
  #expect(Set(firstRows.map(\.id)).count == 2)
  #expect(Set(firstIDs).count == 2)
  #expect(firstIDs == secondIDs)
}

@Test func controlCenterSourceRendersOnlyTheCompletePresentation() {
  let controlCenter = standfastSource("ControlCenterView.swift")

  #expect(controlCenter.contains("fleet.controlCenterPresentation(now: Date())"))
  #expect(!controlCenter.contains("fleet.controlCenterCards"))
  #expect(!controlCenter.contains("fleet.snapshots"))
}

@Test func redesignedViewsUseOneSurfaceAndNativeDisclosureSections() {
  let source =
    standfastSource("ControlCenterView.swift")
    + standfastSource("RunnerCardView.swift")

  #expect(!source.contains("GroupBox"))
  #expect(!source.contains("LabeledContent"))
  #expect(!source.contains("ControlGroup"))
  #expect(source.components(separatedBy: "DisclosureGroup").count - 1 == 2)
  #expect(source.contains(".accessibilityElement(children: .contain)"))
  #expect(!source.contains(".lineLimit(1)"))
  #expect(
    source.contains(
      "L10n.runnerInScope(action.accessibilityLabel, card.title)"))
  #expect(
    source.contains(
      ".accessibilityIdentifier(identifiers.maintenanceAction(offer.kind))"))
  #expect(!source.contains("detail: job.outcome.label"))
}

@Test func maintenanceActionsHaveDeterministicKindScopedAccessibilityIDs() {
  let runner = ControlCenterAccessibility.runner("/Users/me/actions-runner")
  let first = MaintenanceOffer.Kind.allCases.map(runner.maintenanceAction)
  let second = MaintenanceOffer.Kind.allCases.map(runner.maintenanceAction)

  #expect(
    first
      == [
        "\(runner.maintenance).action.measure",
        "\(runner.maintenance).action.clean-tool-cache",
        "\(runner.maintenance).action.clean-action-cache",
        "\(runner.maintenance).action.clean-standfast-trash",
        "\(runner.maintenance).action.trim-logs",
      ])
  #expect(Set(first).count == MaintenanceOffer.Kind.allCases.count)
  #expect(first == second)
}

@Test func controlCenterGeometryTokensAreWiredWithoutChangingItsSceneID() {
  let app = standfastSource("App.swift")
  let controlCenter = standfastSource("ControlCenterView.swift")

  #expect(app.contains("id: \"control-center\""))
  #expect(app.contains("width: StandfastTheme.controlCenterDefaultWidth"))
  #expect(app.contains("height: StandfastTheme.controlCenterDefaultHeight"))
  #expect(controlCenter.contains("minWidth: StandfastTheme.controlCenterMinimumWidth"))
}

@Test func prominentRunnerActionsUseTheMeasuredButtonTextToken() {
  let source = standfastSource("RunnerCardView.swift")
  let foreground = ".foregroundStyle(palette.primaryButtonText.color)"

  #expect(source.components(separatedBy: foreground).count - 1 == 2)
  #expect(
    source.contains(
      "serviceButtonLabel(action)\n"
        + "        \(foreground)\n"
        + "        .buttonStyle(.borderedProminent)"))
  #expect(
    source.contains(
      "navigationButton(action)\n"
        + "          \(foreground)\n"
        + "          .buttonStyle(.borderedProminent)"))
}

// MARK: - Card projection

@Test func headerKeepsAggregateAttentionAndFreshnessAsSeparateFacts() {
  let snapshots = [
    controlCenterSnapshot(.resolved(.busy)),
    controlCenterSnapshot(.resolved(.disconnected)),
    controlCenterSnapshot(.resolved(.stopped)),
  ]
  let readAt = controlCenterNow.addingTimeInterval(-245)

  let subject = ControlCenterHeaderPresentation.building(
    snapshots: snapshots, readAt: readAt, now: controlCenterNow)

  #expect(subject.summary == L10n.stateBusy)
  #expect(subject.shortSummary == L10n.stateRunningShort)
  #expect(subject.symbolName == "gearshape.2.fill")
  #expect(subject.tone == .active)
  #expect(subject.attention == L10n.runnerAttention(1))
  #expect(subject.freshness == L10n.checkedAgo("4m"))
}

@Test func zeroAttentionDisappearsAndStoppedDoesNotCountAsAttention() {
  let subject = ControlCenterHeaderPresentation.building(
    snapshots: [
      controlCenterSnapshot(.resolved(.idle)),
      controlCenterSnapshot(.resolved(.stopped)),
    ], readAt: controlCenterNow, now: controlCenterNow)

  #expect(subject.summary == L10n.stateIdle)
  #expect(subject.tone == .healthy)
  #expect(subject.attention == nil)
}

@Test func anEmptyHeaderIsNeutralWithoutInventingAnAggregate() {
  let subject = ControlCenterHeaderPresentation.building(
    snapshots: [], readAt: nil, now: controlCenterNow)

  #expect(subject.summary == L10n.noRunnersFound)
  #expect(subject.shortSummary == L10n.noRunnersFound)
  #expect(subject.symbolName == FleetSummary.noRunnersSymbolName)
  #expect(subject.tone == .neutral)
  #expect(subject.attention == nil)
  #expect(subject.freshness == L10n.checkedNever)
}

@Test func aHealthyRunnerCardCarriesIdentityStateScopeAndItsRealCapabilities() throws {
  let subject = card(controlCenterSnapshot())

  #expect(subject.id == "actions.runner.acme-widget.build-mac")
  #expect(subject.title == "build-mac")
  #expect(subject.state == L10n.stateIdle)
  #expect(subject.stateSymbolName == "checkmark.circle")
  #expect(subject.scope == "acme/widget")
  #expect(subject.progress == nil)
  #expect(subject.actions.map(\.kind) == RunnerRow.Action.Kind.allCases)
  #expect(subject.actions.first { $0.kind == .start }?.isEnabled == false)
  #expect(subject.actions.first { $0.kind == .stop }?.isEnabled == true)
  #expect(subject.actions.first { $0.kind == .restart }?.isEnabled == true)
  #expect(
    subject.githubDestination
      == .workflowRuns(try #require(URL(string: "https://github.com/acme/widget/actions"))))
  #expect(
    subject.actions.first { $0.kind == .openOnGitHub }?.label
      == L10n.viewRuns())
}

@Test func aCardKeepsTheRawRunnerNameAndScopeSeparateEvenWhenQualified() {
  let subject = card(
    controlCenterSnapshot(qualifier: "acme/widget"))

  #expect(subject.title == "build-mac")
  #expect(subject.scope == "acme/widget")
  #expect(subject.title != "build-mac (acme/widget)")
}

@Test func everyCardKeepsCompactStateSeparateFromItsLongStateDetail() {
  let cases: [(DisplayState, String, String)] = [
    (.resolved(.idle), L10n.stateReadyShort, L10n.stateIdle),
    (.resolved(.busy), L10n.stateRunningShort, L10n.stateBusy),
    (
      .resolved(.disconnected), L10n.stateDisconnectedShort,
      L10n.stateDisconnected
    ),
    (.resolved(.stopped), L10n.stateStoppedShort, L10n.stateStopped),
    (.starting, L10n.stateStartingShort, L10n.stateStarting),
  ]

  for (display, compact, detail) in cases {
    let subject = card(controlCenterSnapshot(display))
    #expect(subject.compactState == compact)
    #expect(subject.state == detail)
  }
}

@Test func everyUnknownSharesCompactUnknownButKeepsItsLongRecoveryReason() {
  let cases: [(UnknownReason, String)] = [
    (.cliUnavailable, L10n.stateUnknownNoCLI),
    (.notAuthenticated, L10n.stateUnknownNotAuthenticated),
    (.noAnswer, L10n.stateUnknownNoAnswer),
    (.serviceStateUnreadable, L10n.stateUnknownNoLocalAnswer),
  ]
  let subjects = cases.map { reason, _ in
    card(controlCenterSnapshot(.resolved(.unknown(reason))))
  }

  #expect(
    subjects.map(\.compactState) == Array(repeating: L10n.stateUnknownShort, count: 4))
  #expect(subjects.map(\.state) == cases.map { $0.1 })
  #expect(Set(subjects.map(\.state)).count == 4)
}

@Test func aBusyRunnerCardNamesTheActiveJob() {
  let running = JobRecord(
    name: "testflight", startedAt: controlCenterNow.addingTimeInterval(-80))
  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy), jobs: JobHistory(records: [running], running: running)))

  #expect(subject.state == L10n.stateBusy)
  #expect(subject.stateSymbolName == "gearshape.2.fill")
  #expect(subject.progress?.contains("testflight") == true)
  #expect(subject.progress?.contains(DurationText.precise(80)) == true)
}

@Test func aStoppedRunnerCardOffersStartButNotStopOrRestart() {
  let subject = card(controlCenterSnapshot(.resolved(.stopped)))

  #expect(subject.state == L10n.stateStopped)
  #expect(subject.stateSymbolName == "moon.zzz")
  #expect(subject.actions.first { $0.kind == .start }?.isEnabled == true)
  #expect(subject.actions.first { $0.kind == .stop }?.isEnabled == false)
  #expect(subject.actions.first { $0.kind == .restart }?.isEnabled == false)
}

@Test func anUnknownRunnerCardKeepsTheSpecificRecoveryInstruction() {
  let subject = card(
    controlCenterSnapshot(.resolved(.unknown(.notAuthenticated))))

  #expect(subject.state == L10n.stateUnknownNotAuthenticated)
  #expect(subject.stateSymbolName == "questionmark.circle")
  #expect(subject.state.contains("gh auth login"))
}

@Test func theLatestServiceOperationFeedbackReachesTheCard() {
  let operation = ServiceOperation(
    action: .restart, phase: .uncertain(.restartStartTimedOut),
    changedAt: controlCenterNow)

  let subject = card(controlCenterSnapshot(operation: operation))

  #expect(subject.operation == operation.presentation)
  #expect(subject.operation?.title == L10n.serviceOperationRestartStartTimedOutTitle)
  #expect(subject.operation?.symbolName == "questionmark.circle")
}

@Test func anInFlightOperationIsTheOnlyThingThatOutranksTheCurrentJob() {
  let running = JobRecord(
    name: "deploy", startedAt: controlCenterNow.addingTimeInterval(-80))
  let operation = ServiceOperation(
    action: .restart, phase: .inFlight, changedAt: controlCenterNow)
  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy), jobs: JobHistory(records: [running], running: running),
      operation: operation, isServiceActionReserved: true))

  #expect(subject.focus == .operation(operation.presentation))
  #expect(subject.operationFeedback == nil)
}

@Test func terminalOperationFeedbackCannotHideTheCurrentJob() {
  let running = JobRecord(
    name: "deploy", startedAt: controlCenterNow.addingTimeInterval(-80))
  let operation = ServiceOperation(
    action: .restart, phase: .failed(.unexpectedFailure),
    changedAt: controlCenterNow)
  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy), jobs: JobHistory(records: [running], running: running),
      operation: operation))

  #expect(subject.focus == .currentJob(L10n.jobRunning("deploy", "1m 20s")))
  #expect(subject.operationFeedback == operation.presentation)
}

@Test func lastPastJobOutranksTheLongStateWhenNothingIsRunning() {
  let finished = JobRecord(
    name: "testflight", startedAt: controlCenterNow.addingTimeInterval(-3_600),
    finishedAt: controlCenterNow.addingTimeInterval(-3_433), result: .succeeded)
  let subject = card(
    controlCenterSnapshot(jobs: JobHistory(records: [finished])))

  #expect(subject.focus == .lastJob(JobRow.building(finished)))
}

@Test func longStateIsTheFallbackWhenThereIsNoOperationOrJob() {
  let subject = card(controlCenterSnapshot(.resolved(.disconnected)))
  #expect(subject.focus == .state(L10n.stateDisconnected))
}

@Test func finishedJobHistoryReachesTheCardWithoutRepeatingTheActiveJob() {
  let active = JobRecord(
    name: "deploy", startedAt: controlCenterNow.addingTimeInterval(-80))
  let finished = JobRecord(
    name: "testflight", startedAt: controlCenterNow.addingTimeInterval(-3_600),
    finishedAt: controlCenterNow.addingTimeInterval(-3_433), result: .succeeded)

  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy), jobs: JobHistory(records: [active, finished], running: active)))

  #expect(subject.recentJobs.map(\.text) == ["testflight — \(L10n.jobSucceeded) (2m 47s)"])
  #expect(!subject.recentJobs.contains { $0.text.contains("deploy") })
}

@Test func unavailableHistoryPreservesWarmLastKnownRows() {
  let finished = JobRecord(
    name: "testflight", startedAt: controlCenterNow.addingTimeInterval(-3_600),
    finishedAt: controlCenterNow.addingTimeInterval(-3_433), result: .succeeded)
  let subject = card(
    controlCenterSnapshot(
      jobs: JobHistory(records: [finished]), isJobHistoryAvailable: false))

  #expect(
    subject.history
      == .unavailable(lastKnownRows: [JobRow.building(finished)]))
}

@Test func runningJobDoesNotConsumeAHistorySlotOrCreateFalseTruncation() {
  let running = JobRecord(
    name: "deploy", startedAt: controlCenterNow.addingTimeInterval(-80))
  let past = (1...RunnerRow.recentJobsShown).map { index in
    JobRecord(
      name: "past-\(index)",
      startedAt: controlCenterNow.addingTimeInterval(-Double(index * 3_600)),
      finishedAt: controlCenterNow.addingTimeInterval(-Double(index * 3_600) + 120),
      result: .succeeded)
  }
  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy),
      jobs: JobHistory(records: [running] + past, running: running)))

  #expect(
    subject.history
      == .available(rows: past.map(JobRow.building), isTruncated: false))
}

@Test func historyReportsTrueTruncationAfterRemovingTheRunningJob() {
  let running = JobRecord(
    name: "deploy", startedAt: controlCenterNow.addingTimeInterval(-80))
  let past = (1...(RunnerRow.recentJobsShown + 1)).map { index in
    JobRecord(
      name: "past-\(index)",
      startedAt: controlCenterNow.addingTimeInterval(-Double(index * 3_600)),
      finishedAt: controlCenterNow.addingTimeInterval(-Double(index * 3_600) + 120),
      result: .succeeded)
  }
  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy),
      jobs: JobHistory(records: [running] + past, running: running)))

  #expect(
    subject.history
      == .available(
        rows: Array(past.prefix(RunnerRow.recentJobsShown)).map(JobRow.building),
        isTruncated: true))
}

@Test func serviceActionsCarrySemanticEmphasisConfirmationAndAccessibility() {
  let stopped = card(controlCenterSnapshot(.resolved(.stopped)))
  #expect(
    stopped.action(.start)
      == RunnerCardAction(
        kind: .start, label: L10n.start,
        accessibilityLabel: L10n.startRunner("build-mac"),
        symbolName: "play.fill", isEnabled: true, emphasis: .prominent,
        requiresConfirmation: false))
  #expect(stopped.action(.stop)?.emphasis == ActionEmphasis.none)
  #expect(stopped.action(.restart)?.emphasis == ActionEmphasis.none)

  let idle = card(controlCenterSnapshot(.resolved(.idle)))
  #expect(idle.action(.stop)?.emphasis == .standard)
  #expect(idle.action(.stop)?.requiresConfirmation == false)
  #expect(idle.action(.restart)?.emphasis == .standard)
  #expect(idle.action(.restart)?.requiresConfirmation == false)

  for display: DisplayState in [
    .resolved(.busy), .resolved(.disconnected),
    .resolved(.unknown(.noAnswer)), .starting,
  ] {
    let subject = card(controlCenterSnapshot(display))
    #expect(subject.action(.stop)?.emphasis == .standard)
    #expect(subject.action(.stop)?.requiresConfirmation == true)
    #expect(subject.action(.restart)?.emphasis == .standard)
    #expect(subject.action(.restart)?.requiresConfirmation == true)
  }
}

@Test func activeWorkMakesNavigationProminentWithoutChangingItsAXCopy() {
  let subject = card(controlCenterSnapshot(.resolved(.busy)))
  let action = subject.action(.openOnGitHub)

  #expect(action?.label == L10n.viewRuns())
  #expect(action?.accessibilityLabel == L10n.openWorkflowRuns)
  #expect(action?.symbolName == "arrow.up.right.square")
  #expect(action?.isEnabled == true)
  #expect(action?.emphasis == .prominent)
  #expect(action?.requiresConfirmation == false)
}

@Test func reservedServiceActionsAreDisabledNoneAndNeverAskForConfirmation() {
  let subject = card(
    controlCenterSnapshot(
      .resolved(.busy), isServiceActionReserved: true))

  for kind: RunnerRow.Action.Kind in [.start, .stop, .restart] {
    #expect(subject.action(kind)?.isEnabled == false)
    #expect(subject.action(kind)?.emphasis == ActionEmphasis.none)
    #expect(subject.action(kind)?.requiresConfirmation == false)
  }
  #expect(subject.action(.openOnGitHub)?.isEnabled == true)
}

@Test func installedAndAvailableVersionsReachTheCardMaintenanceSection() {
  let subject = card(
    controlCenterSnapshot(version: RunnerVersion(2, 335, 0)),
    latestRelease: RunnerVersion(2, 336, 0))

  #expect(
    subject.maintenance.version
      == L10n.runnerVersionOutdated("2.335.0", "2.336.0"))
}

@Test func manualMeasurementsAndSafeCleanupOffersReachTheCard() {
  let measurement = measured(toolCache: 4_000_000, logs: 800_000)

  let subject = card(controlCenterSnapshot(), measurement: measurement)

  #expect(subject.maintenance.usage.contains { $0.contains(L10n.diskToolCache("4 MB")) })
  #expect(subject.maintenance.offer(.measure)?.isEnabled == true)
  #expect(subject.maintenance.offer(.cleanToolCache)?.isEnabled == true)
  #expect(subject.maintenance.measured == L10n.diskMeasuredJustNow)
}

@Test func organizationCardsLabelTheirHonestRunnerSettingsDestination() throws {
  let subject = card(
    controlCenterSnapshot(scope: .organization("acme")))

  #expect(
    subject.githubDestination
      == .runnerSettings(
        try #require(
          URL(string: "https://github.com/organizations/acme/settings/actions/runners"))))
  #expect(
    subject.actions.first { $0.kind == .openOnGitHub }?.label
      == L10n.viewSettings())
  #expect(
    subject.actions.first { $0.kind == .openOnGitHub }?.accessibilityLabel
      == L10n.openRunnerSettings)
}

// MARK: - Empty fleet

@Test func emptyControlCenterUsesInstallGuidanceOnlyForANoRunnerNotice() {
  #expect(
    ControlCenterEmptyPresentation.building(notice: .noRunnersInstalled)
      == .noRunnersInstalled)
}

@Test func emptyControlCenterCarriesTheUnavailableLaunchAgentsDirectory() {
  #expect(
    ControlCenterEmptyPresentation.building(
      notice: .launchAgentsUnreadable(
        URL(fileURLWithPath: "/tmp/Library/LaunchAgents")))
      == .launchAgentsUnavailable(directory: "/tmp/Library/LaunchAgents"))
}

@Test func emptyControlCenterCarriesEveryUnreadableRunnerPath() {
  #expect(
    ControlCenterEmptyPresentation.building(
      notice: .unreadable([
        URL(fileURLWithPath: "/tmp/actions.runner.a.plist"),
        URL(fileURLWithPath: "/tmp/actions.runner.b.plist"),
      ]))
      == .unreadableRunners(paths: [
        "/tmp/actions.runner.a.plist", "/tmp/actions.runner.b.plist",
      ]))
}

// MARK: - Fleet lifecycle and side effects

@Test @MainActor func anEmptyFleetBuildsNoCards() async throws {
  let sandbox = try FleetSandbox()
  defer { sandbox.cleanUp() }
  let fleet = presentationModel(sandbox)

  await fleet.quiesce()

  #expect(fleet.controlCenterCards(now: controlCenterNow).isEmpty)
  #expect(fleet.controlCenterPresentation(now: controlCenterNow).cards.isEmpty)
  #expect(
    fleet.controlCenterPresentation(now: controlCenterNow).empty
      == .noRunnersInstalled)
  #expect(fleet.controlCenterPresentation(now: controlCenterNow).notice == nil)
}

@Test @MainActor func unavailableLaunchAgentsHaveOneEmptyStateOwner() async throws {
  let sandbox = try FleetSandbox()
  defer { sandbox.cleanUp() }
  sandbox.set(discoveryFailure: .launchAgentsUnreadable(sandbox.launchAgents))
  let fleet = presentationModel(sandbox)

  await fleet.quiesce()

  let subject = fleet.controlCenterPresentation(now: controlCenterNow)
  #expect(subject.cards.isEmpty)
  #expect(
    subject.empty
      == .launchAgentsUnavailable(directory: sandbox.launchAgents.path))
  #expect(subject.notice == nil)
}

@Test @MainActor func unreadableOnlyDiscoveryHasOneEmptyStateOwner() async throws {
  let sandbox = try FleetSandbox()
  defer { sandbox.cleanUp() }
  let unreadable = sandbox.launchAgents.appendingPathComponent(
    "actions.runner.broken.plist")
  try Data("not a property list".utf8).write(to: unreadable)
  let fleet = presentationModel(sandbox)

  await fleet.quiesce()

  let subject = fleet.controlCenterPresentation(now: controlCenterNow)
  #expect(subject.cards.isEmpty)
  guard case .unreadableRunners(let paths)? = subject.empty else {
    Issue.record("unreadable-only discovery lost its empty recovery state")
    return
  }
  #expect(paths.count == 1)
  #expect(paths[0].hasSuffix("/LaunchAgents/actions.runner.broken.plist"))
  #expect(subject.notice == nil)
}

@Test @MainActor func mixedDiscoveryKeepsRecoveryNoticeBesideValidCards() async throws {
  let sandbox = try FleetSandbox(serviceRunning: true)
  defer { sandbox.cleanUp() }
  try sandbox.addRunner()
  let unreadable = sandbox.launchAgents.appendingPathComponent(
    "actions.runner.broken.plist")
  try Data("not a property list".utf8).write(to: unreadable)
  let fleet = presentationModel(sandbox)

  await fleet.quiesce()

  let subject = fleet.controlCenterPresentation(now: controlCenterNow)
  #expect(subject.cards.count == 1)
  #expect(subject.empty == nil)
  guard case .unreadableRunners(let paths)? = subject.notice else {
    Issue.record("mixed discovery lost its unreadable-runner notice")
    return
  }
  #expect(paths.count == 1)
  #expect(paths[0].hasSuffix("/LaunchAgents/actions.runner.broken.plist"))
}

@Test @MainActor func healthyRunnerHasNeitherEmptyStateNorRecoveryNotice() async throws {
  let sandbox = try FleetSandbox(serviceRunning: true)
  defer { sandbox.cleanUp() }
  try sandbox.addRunner()
  let fleet = presentationModel(sandbox)

  await fleet.quiesce()

  let subject = fleet.controlCenterPresentation(now: controlCenterNow)
  #expect(subject.cards.count == 1)
  #expect(subject.empty == nil)
  #expect(subject.notice == nil)
}

@Test @MainActor func aConclusiveUninstallRemovesItsCard() async throws {
  let sandbox = try FleetSandbox(serviceRunning: true)
  defer { sandbox.cleanUp() }
  try sandbox.addRunner()
  let fleet = presentationModel(sandbox)
  await fleet.quiesce()
  #expect(fleet.controlCenterCards(now: controlCenterNow).count == 1)

  try sandbox.removeRunner()
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.controlCenterCards(now: controlCenterNow).isEmpty)
}

@Test @MainActor func buildingPresentationsDoesNotProbeTheMachineAgain() async throws {
  let sandbox = try FleetSandbox(serviceRunning: true)
  defer { sandbox.cleanUp() }
  try sandbox.addRunner()
  let diskCommands = RecordingCommandRunner()
  let fleet = presentationModel(sandbox, diskCommands: diskCommands)
  await fleet.quiesce()
  let scans = sandbox.scanCount
  let probes = sandbox.probeCount
  let releaseChecks = sandbox.releaseCheckCount
  let diskInvocations = diskCommands.invocations

  _ = fleet.quickMenuPresentation(thermalLines: [], now: controlCenterNow)
  _ = fleet.controlCenterCards(now: controlCenterNow)
  _ = fleet.controlCenterPresentation(now: controlCenterNow)

  #expect(sandbox.scanCount == scans)
  #expect(sandbox.probeCount == probes)
  #expect(sandbox.releaseCheckCount == releaseChecks)
  #expect(diskCommands.invocations == diskInvocations)
}
