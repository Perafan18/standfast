import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let jobNow = Date(timeIntervalSince1970: 1_788_469_200)

private func jobSnapshot(
  pulls: String = "[702]", event: String = "pull_request",
  display: DisplayState = .resolved(.busy)
) throws -> RunnerSnapshot {
  let json = """
    {
      "id": 456, "run_id": 123, "run_attempt": 2,
      "runner_id": 282, "runner_name": "widget-ci-host",
      "repository": "acme/widget", "hostname": "github.com",
      "workflow_name": "Quality Gate", "name": "Tests", "event": "\(event)",
      "pull_request_numbers": \(pulls), "observed_at": "2026-09-03T21:00:00Z"
    }
    """
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let job = try decoder.decode(ManagedFleetJob.self, from: Data(json.utf8))
  return RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "standfast.fleet:widget:0", directory: URL(fileURLWithPath: "/unused"),
      agentId: 282, agentName: "widget-ci", scope: .organization("acme"),
      installation: .managedFleet, observedState: .busy, currentJob: job),
    display: display, isJobHistoryAvailable: false)
}

@Test private func managedFleetJobAppearsInQuickMenuAndControlCenterWithoutControls() throws
{
  let snapshot = try jobSnapshot()
  let job = try #require(ManagedFleetJobPresentation.building(snapshot, now: jobNow))
  #expect(job.context == "acme/widget #702")
  #expect(job.detail == "Quality Gate · Tests")
  #expect(
    job.links.map(\.url.absoluteString) == [
      "https://github.com/acme/widget/actions/runs/123/job/456",
      "https://github.com/acme/widget/actions/runs/123/attempts/2",
      "https://github.com/acme/widget/pull/702",
    ])
  let overview = FleetOverviewPresentation.building(snapshots: [snapshot], notice: nil)
  let menu = QuickMenuPresentation.building(
    snapshots: [snapshot], overview: overview, thermalLines: [], readAt: nil, now: jobNow)
  guard case .runner(let echo) = menu.items.first else {
    Issue.record("Expected runner menu")
    return
  }
  #expect(echo.title.contains("acme/widget #702"))
  // The AX gate parses the localized state after the last middle dot.
  #expect(echo.title.hasSuffix(" · \(snapshot.display.shortSummary)"))
  #expect(echo.currentJob == job)
  #expect(!echo.canStart)
  let card = RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: jobNow, fleetSize: 11)
  #expect(card.focus == .managedJob(job))
  #expect(card.action(.stop)?.isEnabled == false)
}

@Test(arguments: ["push", "workflow_dispatch"])
private func managedFleetJobWithoutPRReportsAbsenceWithoutInventingAssociation(
  _ event: String
) throws {
  let snapshot = try jobSnapshot(pulls: "[]", event: event)
  let job = try #require(ManagedFleetJobPresentation.building(snapshot, now: jobNow))
  #expect(job.context == "acme/widget")
  #expect(job.association == L10n.managedJobNoPR(event))
  #expect(job.links.count == 2)
}

@Test private func managedFleetJobKeepsMultiplePRsAndHidesDetailsWhenNotBusy() throws {
  let snapshot = try jobSnapshot(pulls: "[702, 703]")
  let job = try #require(ManagedFleetJobPresentation.building(snapshot, now: jobNow))
  #expect(job.context == "acme/widget #702, #703")
  #expect(job.links.count == 4)
  #expect(
    ManagedFleetJobPresentation.building(
      try jobSnapshot(display: .resolved(.idle)), now: jobNow) == nil)
  #expect(
    ManagedFleetJobPresentation.building(snapshot, now: jobNow.addingTimeInterval(121))
      == nil)
}
