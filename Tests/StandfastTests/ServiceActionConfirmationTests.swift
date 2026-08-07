import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let promptMoment = Date(timeIntervalSince1970: 1_785_962_174)

private func promptSnapshot(
  display: DisplayState = .resolved(.busy),
  runner: DiscoveredRunner? = nil,
  runningJob: JobRecord? = JobRecord(name: "testflight", startedAt: promptMoment),
  readAt: Date = promptMoment,
  stateReadAt: Date? = nil,
  version: RunnerVersion? = nil,
  operation: ServiceOperation? = nil
) -> RunnerSnapshot {
  let runner =
    runner
    ?? DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac",
      directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "widget"))
  let jobs = runningJob.map { JobHistory(records: [$0], running: $0) } ?? .empty
  return RunnerSnapshot(
    runner: runner, display: display, jobs: jobs, readAt: readAt,
    stateReadAt: stateReadAt, version: version, operation: operation)
}

@Test func busyStopConfirmationNamesTheRunnerScopeAndCurrentJob() throws {
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))

  #expect(prompt.action == .stop)
  #expect(prompt.runnerID == "actions.runner.acme-widget.build-mac")
  #expect(prompt.display == .resolved(.busy))
  #expect(prompt.runningJob?.name == "testflight")
  #expect(prompt.runningJob?.startedAt == promptMoment)
  #expect(prompt.title == "Stop build-mac?")
  #expect(
    prompt.message
      == "build-mac in acme/widget is running “testflight”. "
      + "Stopping it interrupts this job.")
  #expect(prompt.confirm == "Stop")
  #expect(prompt.cancel == "Cancel")
}

@Test func busyRestartConfirmationNamesBothConsequences() throws {
  let prompt = try #require(
    ServiceActionPrompt(action: .restart, snapshot: promptSnapshot(), bundles: []))

  #expect(prompt.title == "Restart build-mac?")
  #expect(
    prompt.message
      == "build-mac in acme/widget is running “testflight”. "
      + "Restarting interrupts this job. If Start fails after Stop, the runner can "
      + "remain stopped.")
  #expect(prompt.confirm == "Restart")
  #expect(prompt.cancel == "Cancel")
}

@Test func everyUncertainDisplayWarnsAboutPossibleWorkWithoutInventingAJob()
  throws
{
  let displays: [DisplayState] = [
    .resolved(.disconnected),
    .resolved(.unknown(.cliUnavailable)),
    .resolved(.unknown(.notAuthenticated)),
    .resolved(.unknown(.noAnswer)),
    .resolved(.unknown(.serviceStateUnreadable)),
    .starting,
  ]
  for display in displays {
    let snapshot = promptSnapshot(display: display)
    let stop = try #require(
      ServiceActionPrompt(action: .stop, snapshot: snapshot, bundles: []))
    let restart = try #require(
      ServiceActionPrompt(action: .restart, snapshot: snapshot, bundles: []))

    #expect(
      stop.message
        == "build-mac in acme/widget may have work in progress. "
        + "Stopping it can interrupt that work.")
    #expect(
      restart.message
        == "build-mac in acme/widget may have work in progress. "
        + "Restarting can interrupt that work. If Start fails after Stop, the runner "
        + "can remain stopped.")
    #expect(!stop.message.contains("testflight"))
    #expect(!restart.message.contains("testflight"))
  }
}

@Test func safeServiceActionsDoNotProduceAConfirmationPrompt() {
  let idle = promptSnapshot(display: .resolved(.idle), runningJob: nil)
  let stopped = promptSnapshot(display: .resolved(.stopped), runningJob: nil)

  #expect(ServiceActionPrompt(action: .stop, snapshot: idle, bundles: []) == nil)
  #expect(ServiceActionPrompt(action: .restart, snapshot: idle, bundles: []) == nil)
  #expect(ServiceActionPrompt(action: .start, snapshot: stopped, bundles: []) == nil)
}

@Test func promptFingerprintAllowsUnrelatedSnapshotRefreshMetadata() throws {
  let original = promptSnapshot()
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: original, bundles: []))
  let refreshed = promptSnapshot(
    readAt: promptMoment.addingTimeInterval(30),
    stateReadAt: promptMoment.addingTimeInterval(31),
    version: RunnerVersion(9, 9, 9),
    operation: ServiceOperation(
      action: .restart, phase: .requestAccepted,
      changedAt: promptMoment.addingTimeInterval(32)))

  #expect(prompt.stillMatches(refreshed))
}

@Test func promptFingerprintRejectsRunnerDisplayScopeAndJobIdentityChanges() throws {
  let original = promptSnapshot()
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: original, bundles: []))
  let renamed = DiscoveredRunner(
    label: original.runner.label, directory: original.runner.directory,
    agentId: original.runner.agentId, agentName: "release-mac",
    scope: original.runner.scope)
  let movedScope = DiscoveredRunner(
    label: original.runner.label, directory: original.runner.directory,
    agentId: original.runner.agentId, agentName: original.runner.agentName,
    scope: .enterprise("acme"))

  #expect(!prompt.stillMatches(promptSnapshot(display: .resolved(.idle))))
  #expect(!prompt.stillMatches(promptSnapshot(runner: renamed)))
  #expect(!prompt.stillMatches(promptSnapshot(runner: movedScope)))
  #expect(
    !prompt.stillMatches(
      promptSnapshot(
        runningJob: JobRecord(name: "deploy", startedAt: promptMoment))))
  #expect(
    !prompt.stillMatches(
      promptSnapshot(
        runningJob: JobRecord(
          name: "testflight", startedAt: promptMoment.addingTimeInterval(1)))))
  #expect(!prompt.stillMatches(promptSnapshot(runningJob: nil)))
}

@Test func serviceAlertKeysMakeEscapeCancelAndReturnConfirmNothing() {
  #expect(ServiceConfirmationKeys.cancel == "\u{1B}")
  #expect(ServiceConfirmationKeys.confirm == "")
}
