import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let selectionNow = Date(timeIntervalSince1970: 1_785_962_174)

private func selectable(_ name: String) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    RunnerSnapshot(
      runner: DiscoveredRunner(
        label: "actions.runner.acme-widget.\(name)",
        directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
        agentName: name, scope: .repository(owner: "acme", name: "widget")),
      display: .resolved(.idle), readAt: selectionNow),
    measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: selectionNow, fleetSize: 1)
}

private let buildMac = selectable("build-mac")
private let testMac = selectable("test-mac")

@Test func aStoredRunnerThatIsStillHereStaysSelected() {
  #expect(
    ControlCenterSelection.resolve(stored: testMac.id, cards: [buildMac, testMac])
      == .runner(testMac.id))
}

@Test func aStoredOverviewStaysTheOverviewEvenWithOneRunner() {
  // Somebody picked it. The one-runner shortcut is for a choice that was never
  // made or no longer names anything.
  #expect(
    ControlCenterSelection.resolve(stored: "overview", cards: [buildMac]) == .overview)
}

@Test func aRunnerThatWentAwayFallsBackToTheOverview() {
  #expect(
    ControlCenterSelection.resolve(
      stored: "actions.runner.acme-widget.uninstalled", cards: [buildMac, testMac])
      == .overview)
}

@Test func aRunnerThatWentAwayFallsBackToTheOnlyOneLeft() {
  // An Overview of one runner is that runner said twice.
  #expect(
    ControlCenterSelection.resolve(
      stored: "actions.runner.acme-widget.uninstalled", cards: [buildMac])
      == .runner(buildMac.id))
}

@Test func aFirstOpeningShowsTheOnlyRunnerOrTheOverview() {
  #expect(
    ControlCenterSelection.resolve(stored: "", cards: [buildMac]) == .runner(buildMac.id))
  #expect(
    ControlCenterSelection.resolve(stored: "", cards: [buildMac, testMac]) == .overview)
}

@Test func anEmptyFleetAlwaysResolvesToTheOverview() {
  for stored in ["", "overview", buildMac.id] {
    #expect(ControlCenterSelection.resolve(stored: stored, cards: []) == .overview)
  }
}

@Test func whatSceneStorageKeepsIsTheOverviewWordOrTheDurableLabel() {
  // Persisted across launches: a changed spelling would quietly reset
  // everybody's selection. The label, never the title, because a title
  // changes when another runner with the same name appears.
  #expect(ControlCenterSelection.overview.stored == "overview")
  #expect(
    ControlCenterSelection.runner(buildMac.id).stored
      == "actions.runner.acme-widget.build-mac")
  for selection in [ControlCenterSelection.overview, .runner(testMac.id)] {
    #expect(
      ControlCenterSelection.resolve(stored: selection.stored, cards: [buildMac, testMac])
        == selection)
  }
}
