import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let barNow = Date(timeIntervalSince1970: 1_785_962_174)

/// A job `elapsed` seconds in, after three successful runs of `usual` seconds
/// each: the least history an estimate is made from.
private func runningJob(
  _ name: String = "testflight", elapsed: TimeInterval, usual: TimeInterval?
) -> JobHistory {
  let live = JobRecord(name: name, startedAt: barNow.addingTimeInterval(-elapsed))
  let past = (1...3).map { hour -> JobRecord in
    let startedAt = barNow.addingTimeInterval(-3600 * Double(hour))
    return JobRecord(
      name: name, startedAt: startedAt,
      finishedAt: startedAt.addingTimeInterval(usual ?? 0), result: .succeeded)
  }
  return JobHistory(records: [live] + (usual == nil ? [] : past), running: live)
}

private func barCard(
  _ display: DisplayState = .resolved(.busy), jobs: JobHistory = .empty
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    RunnerSnapshot(
      runner: DiscoveredRunner(
        label: "actions.runner.acme-widget.build-mac",
        directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
        agentName: "build-mac", scope: .repository(owner: "acme", name: "widget")),
      display: display, jobs: jobs, readAt: barNow),
    measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: barNow, fleetSize: 1)
}

// MARK: - When there is a bar at all

@Test func aBarIsDrawnOnlyAgainstAUsualTimeTheJobHasNotPassed() {
  #expect(JobProgress(name: "testflight", elapsed: 80, typical: 170).showsBar)
  #expect(JobProgress(name: "testflight", elapsed: 170, typical: 170).showsBar)
  // Past it a full bar would read as done.
  #expect(!JobProgress(name: "testflight", elapsed: 171, typical: 170).showsBar)
  #expect(!JobProgress(name: "testflight", elapsed: 80, typical: nil).showsBar)
  #expect(!JobProgress(name: "testflight", elapsed: 0, typical: 0).showsBar)
}

@Test func theCardCarriesTheJobItsRowDescribes() throws {
  let card = barCard(jobs: runningJob(elapsed: 80, usual: 170))

  let progress = try #require(card.jobProgress)
  #expect(progress.name == "testflight")
  #expect(progress.elapsed == 80)
  #expect(progress.typical == 170)
  #expect(progress.showsBar)
  #expect(card.progress == progress.line)
}

@Test func aRunnerGitHubDoesNotCallBusyHasNoJobToDraw() {
  // A listener killed mid-job leaves a start line no completion follows.
  for display in [DisplayState.resolved(.idle), .resolved(.stopped), .starting] {
    #expect(barCard(display, jobs: runningJob(elapsed: 80, usual: 170)).jobProgress == nil)
  }
}

// MARK: - The heat over one runner's detail

@Test func theHeatIsExplainedOverTheRunnerWhoseJobItIsSlowing() throws {
  let card = barCard(jobs: runningJob(elapsed: 400, usual: 170))
  let lines = ThermalNotice.lines(pressure: .serious, overrunning: true)

  let banner = try #require(card.overrunThermalLine(thermalLines: lines))

  #expect(
    banner.split(separator: "\n").map(String.init)
      == [L10n.thermalSerious, L10n.thermalSlowingJobs])
}

@Test func aJobOnTimeIsNotWhatTheHeatExplains() {
  let lines = ThermalNotice.lines(pressure: .critical, overrunning: true)
  let onTime = barCard(jobs: runningJob(elapsed: 80, usual: 170))
  let unestimated = barCard(jobs: runningJob(elapsed: 4000, usual: nil))

  #expect(onTime.overrunThermalLine(thermalLines: lines) == nil)
  #expect(unestimated.overrunThermalLine(thermalLines: lines) == nil)
  #expect(barCard(.resolved(.idle)).overrunThermalLine(thermalLines: lines) == nil)
}

@Test func anOverrunOnACoolMacHasNoHeatToBlame() {
  let card = barCard(jobs: runningJob(elapsed: 400, usual: 170))
  let cool = ThermalNotice.lines(pressure: .none, overrunning: true)

  #expect(card.overrunThermalLine(thermalLines: []) == nil)
  #expect(card.overrunThermalLine(thermalLines: cool) == nil)
}
