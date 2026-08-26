import AppKit
import Combine
import Foundation
import RunnerKit
import SwiftUI
import Testing

@testable import Standfast

private let controlCenterNow = Date(timeIntervalSince1970: 1_785_962_174)

private func reflectedReference<T: AnyObject>(
  _ type: T.Type, in value: Any, remainingDepth: Int = 3
) -> T? {
  if let reference = value as? T { return reference }
  guard remainingDepth > 0 else { return nil }
  for child in Mirror(reflecting: value).children {
    if let reference = reflectedReference(
      type, in: child.value, remainingDepth: remainingDepth - 1)
    {
      return reference
    }
  }
  return nil
}

private struct ProminentForegroundRenderProbe: View {
  let foregroundInsideLabel: Bool

  private var sentinel: Color {
    Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
  }

  var body: some View {
    if foregroundInsideLabel {
      Button {
      } label: {
        Label("Sentinel", systemImage: "square.fill")
          .foregroundStyle(sentinel)
      }
      .buttonStyle(.borderedProminent)
    } else {
      Button {
      } label: {
        Label("Sentinel", systemImage: "square.fill")
      }
      .foregroundStyle(sentinel)
      .buttonStyle(.borderedProminent)
    }
  }
}

@MainActor
private func sentinelPixelCount<V: View>(in root: V) throws -> Int {
  let size = NSSize(width: 260, height: 90)
  let rendered =
    root
    .font(.system(size: 28, weight: .bold))
    .tint(Color(.sRGB, red: 0, green: 0.3, blue: 0.7, opacity: 1))
    .frame(width: size.width, height: size.height)
    .background(Color.white)
    .environment(\.colorScheme, .light)
  let hosting = NSHostingView(rootView: rendered)
  hosting.frame = NSRect(origin: .zero, size: size)
  hosting.layoutSubtreeIfNeeded()
  hosting.displayIfNeeded()
  let bitmap = try #require(
    hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
  hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

  var count = 0
  for x in 0..<bitmap.pixelsWide {
    for y in 0..<bitmap.pixelsHigh {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
        continue
      }
      if color.redComponent > 0.75, color.greenComponent < 0.35,
        color.blueComponent > 0.75, color.alphaComponent > 0.5
      {
        count += 1
      }
    }
  }
  return count
}

private func controlCenterSnapshot(
  _ display: DisplayState = .resolved(.idle),
  scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  jobs: JobHistory = .empty, operation: ServiceOperation? = nil,
  version: InstalledRunnerVersion = .absent, qualifier: String? = nil,
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
  latestRelease: RunnerVersion? = nil, fleetSize: Int = 1
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    snapshot, measurement: measurement, latestRelease: latestRelease,
    isMaintenanceWorking: false, maintenanceNotice: nil, now: controlCenterNow,
    fleetSize: fleetSize)
}

@Test func aSmallFleetNeverFoldsACardTheOperatorDidNotFold() {
  for tone in [StateTone.healthy, .active, .attention, .stopped, .neutral] {
    for size in 1...RunnerCardPresentation.compactFleetThreshold {
      #expect(
        !RunnerCardPresentation.startsCollapsed(tone: tone, fleetSize: size),
        "tone \(tone) at fleet size \(size)")
    }
  }
}

@Test func aLargeFleetFoldsOnlyTheRunnersWithNothingToAnswerFor() {
  let large = RunnerCardPresentation.compactFleetThreshold + 1

  #expect(RunnerCardPresentation.startsCollapsed(tone: .healthy, fleetSize: large))
  #expect(RunnerCardPresentation.startsCollapsed(tone: .active, fleetSize: large))

  // The states that are the reason somebody opened the window stay open, no
  // matter how many runners are on the machine.
  for tone in [StateTone.attention, .stopped, .neutral] {
    #expect(
      !RunnerCardPresentation.startsCollapsed(tone: tone, fleetSize: large),
      "tone \(tone)")
    #expect(
      !RunnerCardPresentation.startsCollapsed(tone: tone, fleetSize: 40),
      "tone \(tone) on a very large fleet")
  }
}

@MainActor
private struct PresentationConfirmation: CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> CleanupConfirmationResult { .cancelled }
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

@Test @MainActor func controlCenterObservesTheFleetsExactHousekeepingPublisher()
  async throws
{
  let sandbox = try FleetSandbox()
  defer { sandbox.cleanUp() }
  let fleet = presentationModel(sandbox)
  await fleet.quiesce()
  let view = ControlCenterView(fleet: fleet)
  let wrapper = try #require(
    Mirror(reflecting: view).children.first { $0.label == "_housekeeping" }?.value)
  let observed = try #require(
    reflectedReference(HousekeepingModel.self, in: wrapper))

  #expect(observed === fleet.housekeeping)
  var publications = 0
  let cancellation = observed.objectWillChange.sink { publications += 1 }

  observed.keepOnly([])

  #expect(publications > 0)
  withExtendedLifetime(cancellation) {}
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

  #expect(controlCenter.contains("TimelineView(.periodic(from: .now, by: 2))"))
  #expect(
    controlCenter.contains(
      "fleet.controlCenterPresentation(now: timeline.date)"))
  #expect(!controlCenter.contains("controlCenterPresentation(now: Date())"))
  #expect(!controlCenter.contains("fleet.controlCenterCards"))
  #expect(!controlCenter.contains("fleet.snapshots"))
}

@Test func bothSurfacesTakeTheScanStateFromTheModelRatherThanDefaultingIt() {
  // `isScanning` defaults to false at both builders so the suite's many
  // fixtures do not have to answer a question they are not asking. That default
  // is exactly what would swallow a surface wired up without it, and the two
  // call sites that matter are in one file.
  let model = standfastSource("RunnerFleetModel.swift")
  let compact = model.filter { !$0.isWhitespace }

  // Both, counted. Asserting each call site with a substring that the other
  // one also contains proves only that one of them is wired.
  #expect(compact.components(separatedBy: "isScanning:isScanning").count - 1 == 2)
  #expect(
    compact.contains(
      "thermalLines:thermalLines,readAt:lastReadAt,now:now,isScanning:isScanning,"
        + "lastAttemptFailed:lastAttemptFailed"))
  #expect(
    compact.contains(
      "header:.building(overview:overview,readAt:lastReadAt,now:now,isScanning:isScanning,"
        + "lastAttemptFailed:lastAttemptFailed)"
    ))
}

@Test func theHeaderSaysAScanIsRunningRatherThanAgeingTheLastOne() {
  let overview = FleetOverviewPresentation.building(
    snapshots: [controlCenterSnapshot()], notice: nil)
  let readAt = controlCenterNow.addingTimeInterval(-245)

  let scanning = ControlCenterHeaderPresentation.building(
    overview: overview, readAt: readAt, now: controlCenterNow, isScanning: true)
  let settled = ControlCenterHeaderPresentation.building(
    overview: overview, readAt: readAt, now: controlCenterNow, isScanning: false)

  #expect(scanning.freshness == L10n.checkingRunners)
  #expect(settled.freshness == L10n.checkedAgo("4m"))
  // Only the freshness line moves. The aggregate a scan has not answered yet
  // is still the one on screen, and saying otherwise would invent a state.
  #expect(scanning.summary == settled.summary)
  #expect(scanning.symbolName == settled.symbolName)
  #expect(scanning.tone == settled.tone)
}

@Test func timelineDateMovesTheHeaderAcrossTheFreshnessBoundary() {
  let readAt = Date(timeIntervalSince1970: 1_000)
  let overview = FleetOverviewPresentation.building(
    snapshots: [controlCenterSnapshot()], notice: nil)
  let fresh = ControlCenterHeaderPresentation.building(
    overview: overview, readAt: readAt,
    now: readAt.addingTimeInterval(FleetStatus.justNow - 0.1))
  let stale = ControlCenterHeaderPresentation.building(
    overview: overview, readAt: readAt,
    now: readAt.addingTimeInterval(FleetStatus.justNow))

  #expect(fresh.freshness == L10n.checkedJustNow)
  #expect(stale.freshness == L10n.checkedAgo("10s"))
}

@Test func redesignedViewsUseOneSurfaceAndNativeDisclosureSections() {
  let source =
    standfastSource("ControlCenterView.swift")
    + standfastSource("RunnerCardView.swift")

  #expect(!source.contains("GroupBox"))
  #expect(!source.contains("LabeledContent"))
  #expect(!source.contains("ControlGroup"))
  // Count constructions, not the word. Prose about `DisclosureGroup` in a
  // comment used to move this number, which made an explanation of the code
  // indistinguishable from a change to it.
  #expect(source.components(separatedBy: "DisclosureGroup(isExpanded:").count - 1 == 2)
  // Both sections open from the whole row. On macOS the group toggles from its
  // triangle alone, so without this the label is a decoy: it reads as the
  // control and ignores the click.
  let cardSource = standfastSource("RunnerCardView.swift")
  #expect(
    cardSource.components(separatedBy: "disclosureLabel(isExpanded:").count - 1 == 2)
  #expect(cardSource.contains(".onTapGesture { isExpanded.wrappedValue.toggle() }"))
  #expect(cardSource.contains(".contentShape(Rectangle())"))
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

@Test func runnerCardSeparatorUsesTheMeasuredStructuralBoundary() {
  let source = standfastSource("RunnerCardView.swift")
  let compact = source.filter { !$0.isWhitespace }

  #expect(!compact.contains("Divider()"))
  #expect(
    compact.contains(
      "Rectangle().fill(palette.structuralBorder.color)"
        + ".frame(height:StandfastTheme.Stroke.structural)"))
  #expect(StandfastTheme.Stroke.structural >= 1)

  for appearance in StandfastTheme.Appearance.allCases {
    let standard = StandfastTheme.palette(for: appearance)
    let increased = StandfastTheme.palette(for: appearance, increasedContrast: true)
    let standardRatio = standard.structuralBorder.contrastRatio(
      against: standard.surface)
    let increasedRatio = increased.structuralBorder.contrastRatio(
      against: increased.surface)

    #expect(standardRatio >= 3)
    #expect(increasedRatio >= standardRatio)
  }
}

@Test func maintenanceActionsHaveDeterministicKindScopedAccessibilityIDs() {
  let runner = ControlCenterAccessibility.runner("/tmp/actions-runner")
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

@Test @MainActor func borderedProminentOverridesOnlyAnOutsideForeground() throws {
  let outside = try sentinelPixelCount(
    in: ProminentForegroundRenderProbe(foregroundInsideLabel: false))
  let inside = try sentinelPixelCount(
    in: ProminentForegroundRenderProbe(foregroundInsideLabel: true))

  #expect(outside == 0)
  #expect(inside > 20)
}

@Test func prominentRunnerActionsPutTheMeasuredTokenInsideEachLabel() {
  let source = standfastSource("RunnerCardView.swift")
  let compact = source.filter { !$0.isWhitespace }
  let foregroundInsideLabel =
    "Label(action.label,systemImage:action.symbolName)"
    + ".foregroundStyle(foreground.color)"

  #expect(
    compact.contains(
      "serviceButtonLabel(action,foreground:palette.primaryButtonText)"))
  #expect(
    compact.contains(
      "navigationButton(action,foreground:palette.primaryButtonText)"))
  #expect(compact.components(separatedBy: "foreground:nil").count - 1 == 2)
  #expect(
    compact.components(separatedBy: foregroundInsideLabel).count - 1 == 2)
  #expect(
    !compact.contains(
      "ButtonLabel(action).foregroundStyle(palette.primaryButtonText.color)"))
}

// MARK: - Card projection

@Test func headerKeepsAggregateAttentionAndFreshnessAsSeparateFacts() {
  let snapshots = [
    controlCenterSnapshot(.resolved(.busy)),
    controlCenterSnapshot(.resolved(.disconnected)),
    controlCenterSnapshot(.resolved(.stopped)),
  ]
  let readAt = controlCenterNow.addingTimeInterval(-245)
  let overview = FleetOverviewPresentation.building(
    snapshots: snapshots, notice: nil)

  let subject = ControlCenterHeaderPresentation.building(
    overview: overview, readAt: readAt, now: controlCenterNow)

  #expect(subject.summary == L10n.stateBusy)
  #expect(subject.shortSummary == L10n.stateRunningShort)
  #expect(subject.symbolName == "gearshape.2.fill")
  #expect(subject.tone == .active)
  #expect(subject.attention == L10n.runnerAttention(1))
  #expect(subject.freshness == L10n.checkedAgo("4m"))
}

@Test func zeroAttentionDisappearsAndStoppedDoesNotCountAsAttention() {
  let snapshots = [
    controlCenterSnapshot(.resolved(.idle)),
    controlCenterSnapshot(.resolved(.stopped)),
  ]
  let subject = ControlCenterHeaderPresentation.building(
    overview: .building(
      snapshots: snapshots, notice: nil),
    readAt: controlCenterNow, now: controlCenterNow)

  #expect(subject.summary == L10n.stateIdle)
  #expect(subject.tone == .healthy)
  #expect(subject.attention == nil)
}

@Test func anUnreadInitialHeaderIsActivelyChecking() {
  let subject = ControlCenterHeaderPresentation.building(
    overview: .building(snapshots: [], notice: nil),
    readAt: nil, now: controlCenterNow)

  #expect(subject.summary == L10n.checkingRunners)
  #expect(subject.shortSummary == L10n.checkingRunners)
  #expect(subject.symbolName == "arrow.triangle.2.circlepath")
  #expect(subject.tone == .active)
  #expect(subject.attention == nil)
  #expect(subject.freshness == L10n.checkedNever)
}

@Test func aHealthyRunnerCardCarriesIdentityStateScopeAndItsRealCapabilities() throws {
  let subject = card(controlCenterSnapshot())
  let expectedWorkflowRunsURL = try #require(
    URL(string: "https://github.com/acme/widget/actions"))

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
  #expect(subject.githubDestination == .workflowRuns(expectedWorkflowRunsURL))
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

@Test func everyUnknownNamesItsLayerCompactlyAndItsRemedyInFull() {
  // Used to be `everyUnknownSharesCompactUnknown…`, which is the half of
  // UI-034 that stayed open: four different problems, four different
  // instructions, one badge reading `Unknown` over all of them.
  let cases: [(UnknownReason, compact: String, detail: String)] = [
    (.cliUnavailable, L10n.stateLayerGitHubSilent, L10n.stateUnknownNoCLI),
    (.notAuthenticated, L10n.stateLayerGitHubSilent, L10n.stateUnknownNotAuthenticated),
    (.noAnswer, L10n.stateLayerGitHubSilent, L10n.stateUnknownNoAnswer),
    (
      .serviceStateUnreadable, L10n.stateLayerLocalUnreadable,
      L10n.stateUnknownNoLocalAnswer
    ),
  ]
  let subjects = cases.map { reason, _, _ in
    card(controlCenterSnapshot(.resolved(.unknown(reason))))
  }

  // Two layers, so two badges — the same words the long sentence uses.
  #expect(subjects.map(\.compactState) == cases.map(\.compact))
  // And the remedy stays one per reason: the badge names where it went quiet,
  // never what to do about it.
  #expect(subjects.map(\.state) == cases.map(\.detail))
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

@Test func confirmationUnavailableIsTerminalActionableCardFeedback() {
  let operation = ServiceOperation(
    action: .stop, phase: .failed(.confirmationUnavailable),
    changedAt: controlCenterNow)

  let subject = card(controlCenterSnapshot(operation: operation))

  #expect(subject.operation == operation.presentation)
  #expect(
    subject.operation?.title
      == L10n.serviceOperationConfirmationUnavailableTitle(L10n.serviceStop))
  #expect(
    subject.operation?.detail
      == L10n.serviceOperationConfirmationUnavailableDetail(L10n.serviceStop))
  #expect(subject.operation?.symbolName == "exclamationmark.triangle")
  #expect(subject.operation?.isInFlight == false)
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

  #expect(subject.focus == .lastJob(JobRow.building(finished, now: controlCenterNow)))
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
      == .unavailable(lastKnownRows: [JobRow.building(finished, now: controlCenterNow)]))
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
      == .available(rows: JobRow.building(past, now: controlCenterNow), isTruncated: false))
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
        rows: JobRow.building(
          Array(past.prefix(RunnerRow.recentJobsShown)), now: controlCenterNow),
        isTruncated: true))
}

@Test func serviceActionsCarrySemanticEmphasisConfirmationAndAccessibility() {
  let stopped = card(controlCenterSnapshot(.resolved(.stopped)))
  #expect(
    stopped.action(.start)
      == RunnerCardAction(
        kind: .start, label: L10n.serviceStart,
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
    controlCenterSnapshot(version: .known(RunnerVersion(2, 335, 0))),
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
  let expectedRunnerSettingsURL = try #require(
    URL(string: "https://github.com/organizations/acme/settings/actions/runners"))

  #expect(
    subject.githubDestination
      == .runnerSettings(expectedRunnerSettingsURL))
  #expect(
    subject.actions.first { $0.kind == .openOnGitHub }?.label
      == L10n.viewSettings())
  #expect(
    subject.actions.first { $0.kind == .openOnGitHub }?.accessibilityLabel
      == L10n.openRunnerSettings)
}

// MARK: - Empty fleet

@Test func emptyControlCenterUsesInstallGuidanceOnlyForANoRunnerNotice() {
  let overview = FleetOverviewPresentation.building(
    snapshots: [], notice: .noRunnersInstalled)
  #expect(
    ControlCenterEmptyPresentation.building(overview: overview)
      == .noRunnersInstalled)
}

@Test func emptyControlCenterCarriesTheUnavailableLaunchAgentsDirectory() {
  let overview = FleetOverviewPresentation.building(
    snapshots: [],
    notice: .launchAgentsUnreadable(
      URL(fileURLWithPath: "/tmp/Library/LaunchAgents")))
  #expect(
    ControlCenterEmptyPresentation.building(overview: overview)
      == .launchAgentsUnavailable(directory: "/tmp/Library/LaunchAgents"))
}

@Test func emptyControlCenterCarriesEveryUnreadableRunnerPath() {
  let overview = FleetOverviewPresentation.building(
    snapshots: [],
    notice: .unreadable([
      URL(fileURLWithPath: "/tmp/actions.runner.a.plist"),
      URL(fileURLWithPath: "/tmp/actions.runner.b.plist"),
    ]))
  #expect(
    ControlCenterEmptyPresentation.building(overview: overview)
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

// MARK: - UI-038, UI-025, UI-026: what it counts, what it touches, where work comes from

@Test func restartDoesNotWearTheSymbolThatMeansReread() {
  let subject = card(controlCenterSnapshot())

  // `Actualizar ahora` re-reads the machine and touches nothing; `Reiniciar
  // servicio` stops and starts a LaunchAgent. They wore the same circular
  // arrow, which is the one control on this card that cannot afford to be
  // confused with the harmless one.
  #expect(subject.action(.restart)?.symbolName != "arrow.clockwise")
  #expect(
    standfastSource("ControlCenterView.swift")
      .contains("Label(L10n.refreshNow, systemImage: \"arrow.clockwise\")"))
}

@Test func theHistoryBadgeSaysWhatItCounts() {
  // `5+` says neither what is being counted nor why it stops at five. It sits
  // beside a disclosure labelled "Trabajos recientes", so the number reads as
  // a count of everything rather than as how many are listed.
  let source = standfastSource("RunnerCardView.swift")

  #expect(!source.contains("\\(rows.count)+"))
  #expect(source.contains("L10n.historyLatest"))
}

@Test func theMeasurementLineSaysWhatWasMeasured() {
  // `Medido hace 6m` — measured what? The line one row below already says
  // "Uso de disco aún sin medir" when there is no measurement, so the app
  // names the subject only while it has nothing to report about it.
  // Language-agnostic on purpose: what has to hold is that all three name the
  // same subject, whichever catalogue is loaded.
  let opening = [
    L10n.diskNotMeasured, L10n.diskMeasuredJustNow, L10n.diskMeasuredAgo("6m"),
  ]
  .map { $0.split(separator: " ").prefix(2).joined(separator: " ") }

  #expect(Set(opening).count == 1, "the three disk lines open differently: \(opening)")
}

@Test func theScopeLineExplainsWhatItIsToTheRunner() {
  // `acme/acme-widget` under a runner name can be read as a fixed assignment,
  // a filter, the last repository used, or the job in flight. It is where the
  // runner is registered, and that is the only reading the card never states.
  let source = standfastSource("RunnerCardView.swift")

  #expect(source.contains("L10n.scopeExplained(card.scope)"))
}

// MARK: - UI-031: the empty state does not answer with the header

@Test func theEmptyStateDoesNotRepeatTheHeaderAbove() {
  // The header already reads "No hay runners instalados en esta Mac". The body
  // said the same sentence again, 250 points below it and in a larger font, on
  // the first screen anybody who installs this app ever sees. The states that
  // do not share their sentence with the header keep their title.
  #expect(ControlCenterEmptyPresentation.noRunnersInstalled.title == nil)
  #expect(ControlCenterEmptyPresentation.checking.title != nil)
  #expect(
    ControlCenterEmptyPresentation.launchAgentsUnavailable(directory: "/x").title != nil)
  #expect(ControlCenterEmptyPresentation.unreadableRunners(paths: ["/x"]).title != nil)
}

@Test func aMacWhoseRunnerWasStartedByHandIsNotToldItHasNone() {
  // The empty state is exactly where somebody running `./run.sh` concludes the
  // app cannot see their machine and quits. It can — Settings takes the folder
  // — and this is the one screen with room to say so.
  #expect(
    ControlCenterEmptyPresentation.noRunnersInstalled.detailLines
      .contains(L10n.controlCenterNoRunnersManual))
}

// MARK: - UI-039: the empty state offers a way out

@Test func aMacWithNoRunnerIsToldWhereToFindOutHowToGetOne() {
  // The one screen where the user has nothing else to go on. It told them to
  // install a self-hosted runner and left them to find the instructions
  // themselves.
  #expect(
    ControlCenterEmptyPresentation.noRunnersInstalled.guide
      == ControlCenterEmptyPresentation.installGuide)
}

@Test func aDiscoveryFailureIsNotAnsweredWithInstallationInstructions() {
  // These states already name the exact paths to inspect. A link about
  // installing a runner over a directory that would not list is an answer to a
  // question nobody asked.
  #expect(ControlCenterEmptyPresentation.checking.guide == nil)
  #expect(
    ControlCenterEmptyPresentation.launchAgentsUnavailable(directory: "/x").guide == nil)
  #expect(ControlCenterEmptyPresentation.unreadableRunners(paths: ["/x"]).guide == nil)
}

@Test func theEmptyStateSymbolIsNotTheOneThatMeansReading() {
  // UI-039: `circle.dashed` reads as a spinner, the more so beside the symbol
  // this app actually uses while it reads the machine. A window whose empty
  // state looks like it is still loading never tells anybody it has finished.
  #expect(
    ControlCenterEmptyPresentation.noRunnersInstalled.symbolName
      != ControlCenterEmptyPresentation.checking.symbolName)
  #expect(!FleetSummary.noRunnersSymbolName.contains("circle.dashed"))
}

// MARK: - A failed order is not the same kind of news as a finished one

@Test func aFailedOperationCarriesAToneTheCardCanRaise() {
  // `F-accion-fallida`: a Stop that could not run, sitting under a green
  // `Listo` badge in the same weight as everything else. The card cannot lift
  // what the presentation never marked, so the outcome carries its own tone.
  let failed = ServiceOperation(
    action: .stop, phase: .failed(.scriptMissing), changedAt: controlCenterNow)
  let accepted = ServiceOperation(
    action: .stop, phase: .requestAccepted, changedAt: controlCenterNow)
  let uncertain = ServiceOperation(
    action: .stop, phase: .uncertain(.commandTimedOut), changedAt: controlCenterNow)

  #expect(failed.presentation.tone == .attention)
  #expect(accepted.presentation.tone == .healthy)
  // Not attention: an uncertain result is not a failure, and saying so in red
  // would be the app claiming to know something it just admitted it does not.
  #expect(uncertain.presentation.tone == .neutral)
}

@Test func theCardRaisesTheFailedReceiptWithItsOwnRule() {
  let source = standfastSource("RunnerCardView.swift")

  #expect(source.contains("attentionOnSurface"))
}
