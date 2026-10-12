import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let echoNow = Date(timeIntervalSince1970: 1_785_962_174)

private func echoSnapshot(_ name: String, _ display: DisplayState) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: .repository(owner: "acme", name: "widget")),
    display: display, readAt: echoNow)
}

private func echoes(_ snapshots: [RunnerSnapshot]) -> [QuickMenuPresentation.RunnerEcho] {
  let menu = QuickMenuPresentation.building(
    snapshots: snapshots,
    overview: .building(snapshots: snapshots, notice: nil),
    thermalLines: [], readAt: nil, now: echoNow)
  return menu.items.compactMap {
    guard case .runner(let echo) = $0 else { return nil }
    return echo
  }
}

@Test func eachMenuRunnerCarriesItsOwnStateSymbol() {
  // Literals rather than `display.symbolName`, so a change to either side is a
  // decision somebody makes here and not a drift.
  let symbols: [(DisplayState, String)] = [
    (.resolved(.idle), "checkmark.circle"),
    (.resolved(.busy), "gearshape.2.fill"),
    (.resolved(.disconnected), "exclamationmark.triangle"),
    (.resolved(.stopped), "moon.zzz"),
    (.resolved(.unknown(.noAnswer)), "questionmark.circle"),
    (.resolved(.unknown(.managedFleetWaiting)), "arrow.triangle.2.circlepath"),
    (.starting, "arrow.triangle.2.circlepath"),
  ]
  for (display, symbol) in symbols {
    #expect(echoes([echoSnapshot("build-mac", display)]).map(\.symbolName) == [symbol])
  }
}

@Test func theMenuSymbolIsTheRunnersNotTheFleets() {
  // With one runner idle and another stopped the fleet's icon is idle, and the
  // stopped runner must still show its moon.
  let snapshots = [
    echoSnapshot("build-mac", .resolved(.idle)),
    echoSnapshot("gl-docs", .resolved(.stopped)),
    echoSnapshot("deploy-mac", .resolved(.disconnected)),
  ]

  #expect(
    echoes(snapshots).map(\.symbolName)
      == ["checkmark.circle", "moon.zzz", "exclamationmark.triangle"])
  #expect(echoes(snapshots).map(\.symbolName) == snapshots.map(\.display.symbolName))
}
