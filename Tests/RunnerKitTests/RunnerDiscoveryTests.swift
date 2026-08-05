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
    try addLaunchAgentFile(
      named: "\(label).plist", label: label, workingDirectory: dir)
    return dir
  }

  /// Writes a well-formed LaunchAgent under an arbitrary file name, so a test
  /// can vary the name independently of the contents.
  func addLaunchAgentFile(
    named name: String, label: String, workingDirectory: URL
  ) throws {
    let plist: [String: Any] = [
      "Label": label, "WorkingDirectory": workingDirectory.path,
    ]
    let encoded = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    try encoded.write(to: launchAgents.appendingPathComponent(name))
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

@Test func skipsForeignLaunchAgentsEvenWhenEverythingElseFits() throws {
  // Nothing stops an unrelated agent from being well-formed and from running
  // out of a directory that happens to hold a .runner — a second LaunchAgent
  // parked in the runner's own directory is enough. Past that point the label
  // prefix is the only thing telling the two apart.
  let box = try Sandbox()
  defer { box.cleanUp() }
  let dir = try box.addRunner(
    label: "actions.runner.acme-widget.mac-a",
    agentId: 1, gitHubUrl: "https://github.com/acme/widget")
  try box.addLaunchAgentFile(
    named: "com.spotify.client.plist", label: "com.spotify.client",
    workingDirectory: dir)

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.count == 1)
  #expect(found[0].label == "actions.runner.acme-widget.mac-a")
}

@Test func skipsRunnerFilesThatLaunchdWouldNotLoad() throws {
  // A backup or editor leftover beside the real plist: right prefix, valid
  // contents, wrong extension. launchd loads only `.plist`, so anything else
  // describes a runner that is not actually installed.
  let box = try Sandbox()
  defer { box.cleanUp() }
  let dir = try box.addRunner(
    label: "actions.runner.acme-widget.mac-a",
    agentId: 1, gitHubUrl: "https://github.com/acme/widget")
  try box.addLaunchAgentFile(
    named: "actions.runner.acme-widget.mac-b.txt",
    label: "actions.runner.acme-widget.mac-b", workingDirectory: dir)

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.count == 1)
  #expect(found[0].label == "actions.runner.acme-widget.mac-a")
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
