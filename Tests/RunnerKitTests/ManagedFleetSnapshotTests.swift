import Foundation
import Testing

@testable import RunnerKit

private struct ManagedFleetSandbox {
  let root: URL
  var snapshot: URL { root.appendingPathComponent("status-v1.json") }
  var launchAgents: URL { root.appendingPathComponent("LaunchAgents") }

  init() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("managed-fleet-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: launchAgents, withIntermediateDirectories: true)
  }

  func write(_ json: String) throws {
    try Data(json.utf8).write(to: snapshot)
  }

  func addLaunchAgentRunner() throws {
    let label = "actions.runner.acme-widget.local"
    let directory = root.appendingPathComponent(label)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    let runner: [String: Any] = [
      "agentId": 91,
      "agentName": label,
      "gitHubUrl": "https://github.com/acme/widget",
      "workFolder": "_work",
    ]
    try JSONSerialization.data(withJSONObject: runner)
      .write(to: directory.appendingPathComponent(".runner"))
    let plist: [String: Any] = [
      "Label": label,
      "WorkingDirectory": directory.path,
    ]
    let encoded = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    try encoded.write(
      to: launchAgents.appendingPathComponent("\(label).plist"))
  }

  func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

private let generated = "2026-09-03T21:00:00Z"
private let generatedDate = Date(timeIntervalSince1970: 1_788_469_200)

private let currentJobJSON = """
  {
    "id": 456, "run_id": 123, "run_attempt": 2,
    "runner_id": 282, "runner_name": "photo-mo-ci-a1b2c3",
    "repository": "acme/photo-mo", "hostname": "github.com",
    "workflow_name": "Quality Gate", "name": "Tests", "event": "pull_request",
    "pull_request_numbers": [702], "observed_at": "2026-09-03T21:00:00Z"
  }
  """

@Test private func managedFleetCurrentJobDecodesProducerContractAndDerivesLinks() throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.write(snapshotJSON(currentJob: currentJobJSON))
  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runner = snapshot.runners(snapshotFile: box.snapshot, now: generatedDate)[0]
  let job = try #require(runner.currentJob)
  #expect(job.repository == "acme/photo-mo")
  #expect(job.workflowName == "Quality Gate")
  #expect(job.name == "Tests")
  #expect(job.pullRequestNumbers == [702])
  #expect(
    job.jobURL?.absoluteString
      == "https://github.com/acme/photo-mo/actions/runs/123/job/456")
  #expect(
    job.runURL?.absoluteString
      == "https://github.com/acme/photo-mo/actions/runs/123/attempts/2")
  #expect(
    job.pullRequestURL(702)?.absoluteString == "https://github.com/acme/photo-mo/pull/702")
  #expect(job.pullRequestURL(999) == nil)
}

@Test private func managedFleetCurrentJobKeepsARepositoryNamedWithALeadingDot() throws {
  // `.github` is the organisation-wide repository GitHub itself defines, and its
  // workflows run on pools like any other. Dropping the job there leaves the
  // card saying "busy" with nothing to say what at.
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.write(
    snapshotJSON(currentJob: currentJobJSON)
      .replacingOccurrences(of: "acme/photo-mo", with: "acme/.github"))
  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runner = snapshot.runners(snapshotFile: box.snapshot, now: generatedDate)[0]
  let job = try #require(runner.currentJob)
  #expect(
    job.jobURL?.absoluteString
      == "https://github.com/acme/.github/actions/runs/123/job/456")
}

@Test(arguments: ["acme/.", "acme/..", ".acme/widget"])
private func managedFleetCurrentJobRefusesARepositoryThatIsAPathTrick(
  _ repository: String
) throws {
  // Through the snapshot, with the pool claiming the same repository, so the
  // only thing standing between `..` and a link one directory up is the
  // job's own check.
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.write(
    snapshotJSON(currentJob: currentJobJSON)
      .replacingOccurrences(of: "acme/photo-mo", with: repository))
  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runner = snapshot.runners(snapshotFile: box.snapshot, now: generatedDate)[0]
  #expect(runner.observedState == .busy)
  #expect(runner.currentJob == nil)
}

@Test(arguments: [
  "idle", "offline", "unavailable", "stopped", "stale", "oldJob", "futureJob",
  "wrongID", "wrongName", "wrongRepo", "badHost", "badPath", "malformed",
])
private func managedFleetCurrentJobRejectsUnreliableEvidence(_ scenario: String) throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  var job = currentJobJSON
  switch scenario {
  case "oldJob": job = job.replacingOccurrences(of: "21:00:00Z", with: "20:57:00Z")
  case "futureJob": job = job.replacingOccurrences(of: "21:00:00Z", with: "21:03:00Z")
  case "wrongID": job = job.replacingOccurrences(of: "282", with: "283")
  case "wrongName": job = job.replacingOccurrences(of: "photo-mo-ci-a1b2c3", with: "other")
  case "wrongRepo":
    job = job.replacingOccurrences(of: "acme/photo-mo", with: "other/private")
  case "badHost":
    job = job.replacingOccurrences(of: "github.com", with: "github.com@evil.test")
  case "badPath": job = job.replacingOccurrences(of: "acme/photo-mo", with: "acme/../evil")
  case "malformed": job = #"{"id":"bad"}"#
  default: break
  }
  try box.write(
    snapshotJSON(
      supervisorState: scenario == "stopped" ? "stopped" : "running",
      remoteObservation: scenario == "unavailable" ? "unavailable" : "available",
      remoteStatus: scenario == "offline" ? "offline" : "online",
      remoteBusy: scenario != "idle", currentJob: job))
  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runner = snapshot.runners(
    snapshotFile: box.snapshot,
    now: scenario == "stale" ? generatedDate.addingTimeInterval(121) : generatedDate)[0]
  #expect(runner.currentJob == nil)
  if [
    "wrongID", "wrongName", "wrongRepo", "badHost", "badPath", "malformed", "oldJob",
    "futureJob",
  ].contains(scenario) {
    #expect(runner.observedState == .busy)
  }
}

private func snapshotJSON(
  schema: String = ManagedFleetSnapshot.currentSchema,
  executor: String = "native",
  serviceControl: Bool = false,
  includeRemote: Bool = true,
  supervisorState: String = "running",
  remoteObservation: String = "available",
  remoteStatus: String = "online",
  remoteBusy: Bool = true,
  currentJob: String? = nil
) -> String {
  let remoteMember =
    includeRemote
    ? """
    ,
            "remote": {
              "id": 282, "name": "photo-mo-ci-a1b2c3",
              "status": "\(remoteStatus)", "busy": \(remoteBusy)
            }
    """
    : ""

  return """
    {
      "schema": "\(schema)",
      "generated_at": "\(generated)",
      "supervisor_state": "\(supervisorState)",
      "pools": [{
        "id": "photo-mo", "label": "Photo MO", "scope": "repository",
        "target": "acme/photo-mo", "executor": "\(executor)", "capacity": 2,
        "remote_observation": "\(remoteObservation)",
        "slots": [{
          "id": "photo-mo:0", "index": 0, "phase": "active",
          "capabilities": {
            "service_control": \(serviceControl), "maintenance": false,
            "job_history": false
          },
          "runner_name": "photo-mo-ci-a1b2c3",
          "workspace": "/private/tmp/slot 0"\(remoteMember)\(currentJob.map { ",\"current_job\":\($0)" } ?? "")
        }, {
          "id": "photo-mo:1", "index": 1, "phase": "waiting",
          "capabilities": {
            "service_control": false, "maintenance": false,
            "job_history": false
          }
        }]
      }]
    }
    """
}

private enum ManagedFleetStateScenario: CaseIterable, Sendable {
  case busy, idle, offline, waiting, rotating, notObserved, unavailableWithRemote, stale,
    stopped
}

@Test(arguments: ManagedFleetStateScenario.allCases)
private func everyManagedFleetStateBranchIsPinned(
  _ scenario: ManagedFleetStateScenario
) throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }

  var includeRemote = true
  var supervisorState = "running"
  var remoteObservation = "available"
  var remoteStatus = "online"
  var remoteBusy = true
  var slotIndex = 0
  var now = generatedDate
  let expected: RunnerState

  switch scenario {
  case .busy:
    expected = .busy
  case .idle:
    remoteBusy = false
    expected = .idle
  case .offline:
    remoteStatus = "offline"
    expected = .disconnected
  case .waiting:
    slotIndex = 1
    expected = .unknown(.managedFleetWaiting)
  case .rotating:
    includeRemote = false
    expected = .unknown(.managedFleetWaiting)
  case .notObserved:
    includeRemote = false
    remoteObservation = "not_observed"
    expected = .unknown(.managedFleetStatusUnavailable)
  case .unavailableWithRemote:
    remoteObservation = "unavailable"
    expected = .unknown(.managedFleetStatusUnavailable)
  case .stale:
    now = generatedDate.addingTimeInterval(121)
    expected = .unknown(.managedFleetStatusUnavailable)
  case .stopped:
    supervisorState = "stopped"
    expected = .stopped
  }

  try box.write(
    snapshotJSON(
      includeRemote: includeRemote,
      supervisorState: supervisorState,
      remoteObservation: remoteObservation,
      remoteStatus: remoteStatus,
      remoteBusy: remoteBusy))

  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runners = snapshot.runners(snapshotFile: box.snapshot, now: now)

  #expect(runners[slotIndex].observedState == expected)
}

@Test func managedFleetSnapshotKeepsStableSlotsAcrossEphemeralWorkers() throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.write(snapshotJSON())

  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runners = snapshot.runners(
    snapshotFile: box.snapshot, now: generatedDate.addingTimeInterval(30))

  #expect(
    runners.map(\.label) == ["standfast.fleet:photo-mo:0", "standfast.fleet:photo-mo:1"])
  #expect(runners.map(\.agentName) == ["Photo MO #1", "Photo MO #2"])
  #expect(runners[0].agentId == 282)
  #expect(runners[0].scope == .repository(owner: "acme", name: "photo-mo"))
  #expect(runners[0].installation == .managedFleet)
  #expect(runners[0].observedState == .busy)
  #expect(runners[1].observedState == .unknown(.managedFleetWaiting))
}

@Test func managedFleetSnapshotIgnoresAuthorityStandfastDoesNotImplement() throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.write(snapshotJSON(executor: "future", serviceControl: true))

  let snapshot = try ManagedFleetSnapshot(contentsOf: box.snapshot)
  let runner = try #require(
    snapshot.runners(snapshotFile: box.snapshot, now: generatedDate).first)

  #expect(runner.observedState == .busy)
}

@Test func discoveryReportsAnInvalidManagedFleetContractAsUnreadable() throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.write(snapshotJSON(schema: "actions-runner-fleet/status-v2"))

  let result = RunnerDiscovery(
    launchAgentsDirectory: box.launchAgents,
    gitLabConfigFile: box.root.appendingPathComponent("no-gitlab.toml"),
    managedFleetSnapshotFile: box.snapshot
  ).discover()

  #expect(result.runners.isEmpty)
  #expect(result.unreadable == [box.snapshot])
}

@Test func discoveryKeepsLaunchAgentAlongsideManagedFleetSlots() throws {
  let box = try ManagedFleetSandbox()
  defer { box.cleanUp() }
  try box.addLaunchAgentRunner()
  try box.write(snapshotJSON())

  let result = RunnerDiscovery(
    launchAgentsDirectory: box.launchAgents,
    gitLabConfigFile: box.root.appendingPathComponent("no-gitlab.toml"),
    managedFleetSnapshotFile: box.snapshot
  ).discover()

  #expect(
    Set(result.runners.map(\.label)) == [
      "actions.runner.acme-widget.local",
      "standfast.fleet:photo-mo:0",
      "standfast.fleet:photo-mo:1",
    ])
  #expect(result.unreadable.isEmpty)
  #expect(result.possiblyInstalledLabels == [])
}

@Test func managedFleetStateNeverFallsBackToLocalOrGitHubProbes() {
  let calls = ManagedFleetProbeCalls()
  let observedAt = Date(timeIntervalSince1970: 1_788_469_200)
  let runner = DiscoveredRunner(
    label: "standfast.fleet:photo-mo:0",
    directory: URL(fileURLWithPath: "/private/tmp/ephemeral-slot"),
    agentId: 282, agentName: "Photo MO",
    scope: .repository(owner: "acme", name: "photo-mo"),
    installation: .managedFleet, observedState: .busy, observedAt: observedAt)
  let resolver = RunnerStateResolver(
    isServiceRunning: { _ in
      calls.recordLocalProbe()
      return true
    },
    github: ManagedFleetGitHubProbe(calls: calls))

  let reading = resolver.blockingReading(for: runner, clock: Date.init)
  let confirmed = resolver.blockingConfirmedState(for: runner)

  #expect(reading.state == .busy)
  #expect(reading.readAt == observedAt)
  #expect(confirmed == .busy)
  #expect(calls.local == 0)
  #expect(calls.remote == 0)
}

private final class ManagedFleetProbeCalls: @unchecked Sendable {
  private let lock = NSLock()
  private var counts = (local: 0, remote: 0)

  var local: Int { lock.withLock { counts.local } }
  var remote: Int { lock.withLock { counts.remote } }

  func recordLocalProbe() { lock.withLock { counts.local += 1 } }
  func recordRemoteProbe() { lock.withLock { counts.remote += 1 } }
}

private struct ManagedFleetGitHubProbe: GitHubClient {
  let calls: ManagedFleetProbeCalls

  func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    calls.recordRemoteProbe()
    return RemoteStatus(online: true, busy: false)
  }
}
