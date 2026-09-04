import Foundation
import RunnerKit
import Testing

@testable import Standfast

private func managedFleetSnapshot(
  _ display: DisplayState = .resolved(.busy)
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "standfast.fleet:photo-mo:0",
      directory: URL(fileURLWithPath: "/private/tmp/ephemeral-slot"),
      agentId: 282, agentName: "Photo MO",
      scope: .repository(owner: "acme", name: "photo-mo"),
      installation: .managedFleet, observedState: display.resolvedState,
      observedAt: Date(timeIntervalSince1970: 1_788_469_200)),
    display: display)
}

@Test func managedFleetCardIsExplicitlyReadOnly() {
  let snapshot = managedFleetSnapshot()
  let card = RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 1_788_469_230), fleetSize: 1)

  #expect(card.serviceNote == L10n.runnerManagedFleet)
  #expect(card.action(.start)?.isEnabled == false)
  #expect(card.action(.stop)?.isEnabled == false)
  #expect(card.action(.restart)?.isEnabled == false)
  #expect(card.action(.openOnGitHub)?.isEnabled == true)
}

@Test func managedFleetCardOffersNoFilesystemMaintenance() {
  let section = MaintenanceSection.building(
    managedFleetSnapshot(), measurement: nil, latest: nil,
    isWorking: false, notice: nil,
    now: Date(timeIntervalSince1970: 1_788_469_230))

  #expect(section.offers.isEmpty)
  #expect(section.measured == L10n.diskManagedFleet)
}

@Test func aRotatingManagedFleetSlotIsActiveWithoutClaimingItCanReceiveWork() {
  let display = DisplayState.resolved(.unknown(.managedFleetWaiting))

  #expect(display.tone == .active)
  #expect(display.needsAttention == false)
  #expect(display.canReceiveWork == false)
  #expect(display.symbolName == "arrow.triangle.2.circlepath")
}
