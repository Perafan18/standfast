import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let overviewNow = Date(timeIntervalSince1970: 1_785_962_174)

private func overviewSnapshot(
  _ name: String, _ display: DisplayState
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.test.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: .repository(owner: "acme", name: "widget")),
    display: display, readAt: overviewNow)
}

private struct FleetSurfaceProjection {
  let overview: FleetOverviewPresentation
  let quickMenu: QuickMenuPresentation
  let header: ControlCenterHeaderPresentation
  let empty: ControlCenterEmptyPresentation?
  let notice: ControlCenterNoticePresentation?

  init(
    snapshots: [RunnerSnapshot], notice: FleetNotice?, readAt: Date?
  ) {
    overview = .building(
      snapshots: snapshots, notice: notice, readAt: readAt)
    quickMenu = .building(
      snapshots: snapshots, overview: overview, thermalLines: [],
      readAt: readAt, now: overviewNow)
    header = .building(
      overview: overview, readAt: readAt, now: overviewNow)
    empty = .building(overview: overview)
    self.notice = .building(overview: overview)
  }
}

private func discoveryLines(
  in presentation: QuickMenuPresentation
) -> [String] {
  presentation.items.compactMap {
    guard case .discovery(let line) = $0 else { return nil }
    return line
  }
}

@Test func initialFleetIsCheckingOnEverySurface() throws {
  let subject = FleetSurfaceProjection(
    snapshots: [], notice: nil, readAt: nil)
  let empty = try #require(subject.empty)

  #expect(subject.overview.state == .checking)
  #expect(subject.overview.summary == L10n.checkingRunners)
  #expect(subject.overview.shortSummary == L10n.checkingRunners)
  #expect(subject.overview.symbolName == "arrow.triangle.2.circlepath")
  #expect(subject.overview.tone == .active)
  #expect(discoveryLines(in: subject.quickMenu) == [L10n.checkingRunners])
  #expect(subject.header.summary == L10n.checkingRunners)
  #expect(subject.header.symbolName == "arrow.triangle.2.circlepath")
  #expect(subject.header.tone == .active)
  #expect(empty.title == L10n.checkingRunners)
  #expect(empty.detailLines.isEmpty)
  #expect(empty.symbolName == "arrow.triangle.2.circlepath")
  #expect(subject.notice == nil)
  #expect(subject.overview.summary != L10n.noRunnersFound)
}

@Test func conclusiveEmptyFleetSaysNoRunnersOnEverySurface() throws {
  let subject = FleetSurfaceProjection(
    snapshots: [], notice: .noRunnersInstalled, readAt: overviewNow)
  let empty = try #require(subject.empty)

  #expect(subject.overview.state == .noRunnersInstalled)
  #expect(subject.overview.summary == L10n.noRunnersFound)
  #expect(subject.overview.symbolName == FleetSummary.noRunnersSymbolName)
  #expect(subject.overview.tone == .neutral)
  #expect(discoveryLines(in: subject.quickMenu) == [L10n.noRunnersFound])
  #expect(subject.header.summary == L10n.noRunnersFound)
  #expect(subject.header.symbolName == FleetSummary.noRunnersSymbolName)
  #expect(empty.title == L10n.noRunnersFound)
  #expect(empty.detailLines == [L10n.controlCenterNoRunnersDescription])
  #expect(subject.notice == nil)
}

@Test func unreadableLaunchAgentsStayUnavailableOnEverySurface() throws {
  let directory = URL(fileURLWithPath: "/tmp/Library/LaunchAgents")
  let subject = FleetSurfaceProjection(
    snapshots: [], notice: .launchAgentsUnreadable(directory),
    readAt: overviewNow)
  let empty = try #require(subject.empty)

  #expect(subject.overview.state == .unavailable)
  #expect(subject.overview.summary == L10n.launchAgentsUnreadable)
  #expect(subject.overview.symbolName == "exclamationmark.triangle")
  #expect(subject.overview.tone == .attention)
  #expect(
    subject.overview.recovery
      == .launchAgentsUnavailable(directory: "/tmp/Library/LaunchAgents"))
  #expect(
    discoveryLines(in: subject.quickMenu)
      == [L10n.launchAgentsUnreadable + " /tmp/Library/LaunchAgents"])
  #expect(subject.header.summary == L10n.launchAgentsUnreadable)
  #expect(subject.header.symbolName == "exclamationmark.triangle")
  #expect(subject.header.tone == .attention)
  #expect(empty.title == L10n.launchAgentsUnreadable)
  #expect(empty.detailLines == ["/tmp/Library/LaunchAgents"])
  #expect(empty.symbolName == "exclamationmark.triangle")
  #expect(subject.notice == nil)
  #expect(subject.overview.summary != L10n.noRunnersFound)
}

@Test func unreadableRunnerFilesKeepEveryRecoveryPathOffTheEmptyClaim() throws {
  let paths = [
    URL(fileURLWithPath: "/tmp/actions.runner.a.plist"),
    URL(fileURLWithPath: "/tmp/actions.runner.b.plist"),
  ]
  let subject = FleetSurfaceProjection(
    snapshots: [], notice: .unreadable(paths), readAt: overviewNow)
  let empty = try #require(subject.empty)

  #expect(subject.overview.state == .unavailable)
  #expect(subject.overview.summary == L10n.someRunnersUnreadable)
  #expect(subject.overview.symbolName == "exclamationmark.triangle")
  #expect(subject.overview.tone == .attention)
  #expect(
    subject.overview.recovery
      == .unreadableRunners(paths: [
        "/tmp/actions.runner.a.plist", "/tmp/actions.runner.b.plist",
      ]))
  #expect(
    discoveryLines(in: subject.quickMenu)
      == [
        L10n.someRunnersUnreadable + " /tmp/actions.runner.a.plist "
          + L10n.moreUnreadable
      ])
  #expect(subject.header.summary == L10n.someRunnersUnreadable)
  #expect(empty.title == L10n.someRunnersUnreadable)
  #expect(
    empty.detailLines
      == ["/tmp/actions.runner.a.plist", "/tmp/actions.runner.b.plist"])
  #expect(subject.notice == nil)
  #expect(subject.overview.summary != L10n.noRunnersFound)
}

@Test func populatedFleetKeepsAggregatePrimaryAndUnreadableRecoverySecondary() {
  let snapshots = [
    overviewSnapshot("ready", .resolved(.idle)),
    overviewSnapshot("running", .resolved(.busy)),
  ]
  let unreadable = URL(fileURLWithPath: "/tmp/actions.runner.broken.plist")
  let subject = FleetSurfaceProjection(
    snapshots: snapshots, notice: .unreadable([unreadable]),
    readAt: overviewNow)

  #expect(subject.overview.state == .fleet(.resolved(.busy)))
  #expect(subject.overview.summary == L10n.stateBusy)
  #expect(subject.overview.shortSummary == L10n.stateRunningShort)
  #expect(subject.overview.symbolName == "gearshape.2.fill")
  #expect(subject.overview.tone == .active)
  #expect(
    subject.overview.recovery
      == .unreadableRunners(paths: ["/tmp/actions.runner.broken.plist"]))
  #expect(
    discoveryLines(in: subject.quickMenu)
      == [L10n.someRunnersUnreadable + " /tmp/actions.runner.broken.plist"])
  #expect(subject.header.summary == L10n.stateBusy)
  #expect(subject.header.shortSummary == L10n.stateRunningShort)
  #expect(subject.header.symbolName == "gearshape.2.fill")
  #expect(subject.header.tone == .active)
  #expect(subject.empty == nil)
  #expect(
    subject.notice
      == .unreadableRunners(paths: ["/tmp/actions.runner.broken.plist"]))
}

@Test func statusItemSourceConsumesTheModelsOverview() {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let app = repository.appendingPathComponent("Sources/Standfast/App.swift")
  let source = (try? String(contentsOf: app, encoding: .utf8)) ?? ""

  #expect(source.contains("let overview = fleet.overview"))
  #expect(source.contains("Image(systemName: overview.symbolName)"))
  #expect(source.contains(".accessibilityValue(overview.summary)"))
  #expect(!source.contains("FleetSummary"))
  #expect(!source.contains("fleet.snapshots"))
}
