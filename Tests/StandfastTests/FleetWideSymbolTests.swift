import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// UI-002: the three fleet-wide answers must not share one icon.
///
/// "Still looking", "nothing installed" and "the directory could not be read"
/// once all reached the menu bar as `circle.dashed`, so the icon that exists to
/// answer at a glance said the same thing about a Mac that is fine, a Mac that
/// has nothing, and a Mac whose runners this app cannot see at all. The three
/// have completely different answers and now carry completely different marks;
/// this pins that, because it is exactly the kind of thing a redesign merges
/// back together without anyone noticing.

private let atStartup = FleetOverviewPresentation.building(
  snapshots: [], notice: nil)
private let nothingInstalled = FleetOverviewPresentation.building(
  snapshots: [], notice: .noRunnersInstalled)
private let unreadable = FleetOverviewPresentation.building(
  snapshots: [],
  notice: .launchAgentsUnreadable(URL(fileURLWithPath: "/tmp/LaunchAgents")))

@Test func theThreeFleetWideAnswersDoNotShareOneSymbol() {
  let symbols = [
    atStartup.symbolName, nothingInstalled.symbolName, unreadable.symbolName,
  ]

  #expect(Set(symbols).count == 3, "\(symbols)")
}

@Test func aFleetThatCouldNotBeReadIsNotDrawnAsAFleetWithNothingInIt() {
  // The dashed circle means "nothing here". A directory that could not be
  // listed is not evidence of an empty Mac, and drawing it that way tells the
  // operator to install a runner they may already have.
  #expect(nothingInstalled.symbolName == FleetSummary.noRunnersSymbolName)
  #expect(unreadable.symbolName != FleetSummary.noRunnersSymbolName)
  #expect(atStartup.symbolName != FleetSummary.noRunnersSymbolName)
}

@Test func onlyTheUnreadableFleetAsksForSomebodysAttention() {
  #expect(unreadable.tone == .attention)
  #expect(nothingInstalled.tone == .neutral)
  #expect(atStartup.tone == .active)
}
