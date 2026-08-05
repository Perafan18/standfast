import Foundation
import Testing

@testable import RunnerKit

/// Builds a throwaway LaunchAgents directory plus runner directories.
private struct Sandbox {
  let root: URL
  var launchAgents: URL { root.appendingPathComponent("LaunchAgents") }

  init() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("discovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: launchAgents, withIntermediateDirectories: true)
  }

  @discardableResult
  func addRunner(
    label: String, agentId: Int, gitHubUrl: String,
    createRunnerFile: Bool = true
  ) throws -> URL {
    let dir = root.appendingPathComponent(label)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if createRunnerFile {
      let json = """
        {"agentId": \(agentId), "agentName": "\(label)", \
        "gitHubUrl": "\(gitHubUrl)", "workFolder": "_work"}
        """
      var data = Data([0xEF, 0xBB, 0xBF])  // same BOM the real agent writes
      data.append(Data(json.utf8))
      try data.write(to: dir.appendingPathComponent(".runner"))
    }
    let plist: [String: Any] = ["Label": label, "WorkingDirectory": dir.path]
    let encoded = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    try encoded.write(to: launchAgents.appendingPathComponent("\(label).plist"))
    return dir
  }

  func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Test func discoversASingleRunner() throws {
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.build-mac",
    agentId: 21, gitHubUrl: "https://github.com/acme/widget")

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.count == 1)
  #expect(found[0].agentId == 21)
  #expect(found[0].scope == .repository(owner: "acme", name: "widget"))
  #expect(found[0].label == "actions.runner.acme-widget.build-mac")
}

@Test func discoversSeveralRunnersOnOneMachine() throws {
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.mac-a",
    agentId: 1, gitHubUrl: "https://github.com/acme/widget")
  try box.addRunner(
    label: "actions.runner.acme.mac-b",
    agentId: 2, gitHubUrl: "https://github.com/acme")

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents)
    .discover().sorted { $0.agentId < $1.agentId }

  #expect(found.count == 2)
  #expect(found[1].scope == .organization("acme"))
}

@Test func skipsLaunchAgentsThatAreNotRunners() throws {
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.mac-a",
    agentId: 1, gitHubUrl: "https://github.com/acme/widget")
  try Data("<plist/>".utf8).write(
    to: box.launchAgents.appendingPathComponent("com.spotify.client.plist"))

  #expect(RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover().count == 1)
}

@Test func skipsHalfUninstalledRunners() throws {
  // A plist left behind after someone deleted the runner directory. Reporting
  // it would produce a permanently broken entry in the menu.
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.ghost",
    agentId: 9, gitHubUrl: "https://github.com/acme/widget",
    createRunnerFile: false)

  #expect(RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover().isEmpty)
}

@Test func returnsEmptyWhenThereIsNoLaunchAgentsDirectory() {
  let missing = URL(fileURLWithPath: "/nope/does/not/exist")
  #expect(RunnerDiscovery(launchAgentsDirectory: missing).discover().isEmpty)
}
