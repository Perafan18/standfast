import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let logFolderNow = Date(timeIntervalSince1970: 1_785_962_174)

private let gitLabScope = RunnerScope.gitLab(
  instance: GitLabInstance(url: "https://gitlab.example.com")!)

private func logFolderCard(
  _ installation: RunnerInstallation, scope: RunnerScope = .organization("acme"),
  contained: URL?
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    RunnerSnapshot(
      runner: DiscoveredRunner(
        label: "actions.runner.acme.build-mac",
        directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
        agentName: "build-mac", scope: scope, installation: installation),
      display: .resolved(.idle), containedDiagnosticsDirectory: contained,
      readAt: logFolderNow),
    measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: logFolderNow, fleetSize: 1)
}

private let diag = URL(fileURLWithPath: "/tmp/build-mac/_diag")

@Test func aRunnerOfItsOwnRevealsTheLogFolderTheScanProved() {
  #expect(logFolderCard(.launchAgent, contained: diag).diagnosticsDirectory == diag)
  #expect(logFolderCard(.manual, contained: diag).diagnosticsDirectory == diag)
}

@Test func aLogFolderThatEscapesTheRunnerIsNeverRevealed() {
  // Nil from the scan is a `_diag` symlinked elsewhere or unresolvable, and
  // the card must not fall back to the configured path.
  #expect(logFolderCard(.launchAgent, contained: nil).diagnosticsDirectory == nil)
  #expect(logFolderCard(.manual, contained: nil).diagnosticsDirectory == nil)
}

@Test func runnersWhoseLogsAreSomebodyElsesOfferNoFolder() {
  // gitlab-runner writes no `_diag`, and a fleet slot's logs are its
  // supervisor's: a path here would open a folder that is not this runner's.
  #expect(
    logFolderCard(.gitLabService, scope: gitLabScope, contained: diag).diagnosticsDirectory
      == nil)
  #expect(logFolderCard(.managedFleet, contained: diag).diagnosticsDirectory == nil)
}

@Test func theCardNeverResolvesTheLogFolderItself() {
  // Resolving it is a `realpath` that may wait on a network volume, and the
  // card is built every two seconds on the main actor. Only the scan asks.
  let names = standfastSourceNames()
  #expect(names.contains("ControlCenterPresentation.swift"))
  for name in names where name != "RunnerFleetModel.swift" {
    #expect(
      !standfastSource(name).contains("runner.containedDiagnosticsDirectory"), "\(name)")
  }
}
