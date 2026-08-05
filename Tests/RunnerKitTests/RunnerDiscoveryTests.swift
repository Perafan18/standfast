import Foundation
import Testing

@testable import RunnerKit

/// Builds a throwaway LaunchAgents directory plus runner directories.
private struct Sandbox {
  /// What to leave in the runner's own directory.
  enum RunnerFile {
    case complete
    /// A file from a release that stopped writing the cosmetic fields.
    case withoutAgentName
    /// Nothing at all — what a half-finished uninstall leaves behind.
    case missing
  }

  let root: URL
  var launchAgents: URL { root.appendingPathComponent("LaunchAgents") }

  init() throws {
    // The space is deliberate. Runners get installed under "Mobile Documents"
    // and worse, and a path joined as a string instead of a URL survives every
    // test until it meets one.
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("runner discovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: launchAgents, withIntermediateDirectories: true)
  }

  @discardableResult
  func addRunner(
    label: String, agentId: Int, gitHubUrl: String,
    runnerFile: RunnerFile = .complete, fileName: String? = nil
  ) throws -> URL {
    let dir = root.appendingPathComponent(label)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if runnerFile != .missing {
      var fields: [String: Any] = [
        "agentId": agentId, "gitHubUrl": gitHubUrl, "workFolder": "_work",
      ]
      if runnerFile == .complete { fields["agentName"] = label }
      var data = Data([0xEF, 0xBB, 0xBF])  // same BOM the real agent writes
      data.append(try JSONSerialization.data(withJSONObject: fields))
      try data.write(to: dir.appendingPathComponent(".runner"))
    }
    try addLaunchAgentFile(
      named: fileName ?? "\(label).plist", label: label, workingDirectory: dir)
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

  #expect(found.runners.count == 1)
  #expect(found.runners[0].agentId == 21)
  #expect(found.runners[0].scope == .repository(owner: "acme", name: "widget"))
  #expect(found.runners[0].label == "actions.runner.acme-widget.build-mac")
  #expect(found.unreadable.isEmpty)
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
    .discover().runners.sorted { $0.agentId < $1.agentId }

  #expect(found.count == 2)
  #expect(found[1].scope == .organization("acme"))
}

@Test func returnsRunnersSortedByLabel() throws {
  // The file names are ordered against the labels on purpose: sorting the
  // directory listing would pass this by accident, and the menu orders by
  // what it displays, which is the label.
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.zulu", agentId: 1,
    gitHubUrl: "https://github.com/acme/widget",
    fileName: "actions.runner.acme-widget.alpha.plist")
  try box.addRunner(
    label: "actions.runner.acme-widget.alpha", agentId: 2,
    gitHubUrl: "https://github.com/acme/widget",
    fileName: "actions.runner.acme-widget.zulu.plist")

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(
    found.runners.map(\.label) == [
      "actions.runner.acme-widget.alpha", "actions.runner.acme-widget.zulu",
    ])
}

@Test func reportsEachRunnerOnceEvenIfItsPlistWasDuplicated() throws {
  // "name copy.plist" is what Finder produces, and it keeps both the prefix
  // and the extension while describing the same runner. Identifiable exists
  // for the menu's ForEach, where a repeated id is undefined behaviour that
  // nothing traces back to here.
  let box = try Sandbox()
  defer { box.cleanUp() }
  let dir = try box.addRunner(
    label: "actions.runner.acme-widget.mac-a", agentId: 1,
    gitHubUrl: "https://github.com/acme/widget")
  try box.addLaunchAgentFile(
    named: "actions.runner.acme-widget.mac-a copy.plist",
    label: "actions.runner.acme-widget.mac-a", workingDirectory: dir)

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.runners.count == 1)
  #expect(Set(found.runners.map(\.id)).count == found.runners.count)
}

@Test func reportsAMissingNameAsMissingAndStillHasSomethingToShow() throws {
  // agentName stays truthful so the menu can render a nameless runner
  // differently; displayName is what it falls back to when it just needs a
  // string.
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.mac-a", agentId: 1,
    gitHubUrl: "https://github.com/acme/widget", runnerFile: .withoutAgentName)

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.runners.count == 1)
  #expect(found.runners[0].agentName == "")
  #expect(found.runners[0].displayName == "acme-widget.mac-a")
}

@Test func prefersTheRunnersOwnNameForDisplay() throws {
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.mac-a", agentId: 1,
    gitHubUrl: "https://github.com/acme/widget")

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.runners[0].displayName == found.runners[0].agentName)
}

@Test func showsTheWholeLabelWhenItIsNotShapedLikeARunners() {
  // The prefix is stripped as noise, not parsed. A Label that does not carry
  // it is shown whole rather than mangled.
  let odd = DiscoveredRunner(
    label: "com.example.oddly-labelled", directory: URL(fileURLWithPath: "/tmp"),
    agentId: 1, agentName: "", scope: .organization("acme"))

  #expect(odd.displayName == "com.example.oddly-labelled")
}

@Test func skipsLaunchAgentsThatAreNotRunners() throws {
  let box = try Sandbox()
  defer { box.cleanUp() }
  try box.addRunner(
    label: "actions.runner.acme-widget.mac-a",
    agentId: 1, gitHubUrl: "https://github.com/acme/widget")
  try Data("<plist/>".utf8).write(
    to: box.launchAgents.appendingPathComponent("com.spotify.client.plist"))

  let found = RunnerDiscovery(launchAgentsDirectory: box.launchAgents).discover()

  #expect(found.runners.count == 1)
  // Somebody else's broken agent is not this app's problem to report.
  #expect(found.unreadable.isEmpty)
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

  #expect(found.runners.count == 1)
  #expect(found.runners[0].label == "actions.runner.acme-widget.mac-a")
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

  #expect(found.runners.count == 1)
  #expect(found.runners[0].label == "actions.runner.acme-widget.mac-a")
}

@Test func separatesAnEmptyMachineFromOneWhereNothingCouldBeRead() throws {
  // The half-uninstalled runner below — a plist whose directory someone
  // deleted — must not reach the menu as a permanently broken row.
  //
  // Both machines end up with no runners, and the difference decides what the
  // menu is allowed to say. Telling someone to install a runner when one is
  // installed and unreadable is the one answer guaranteed to be wrong.
  let bare = try Sandbox()
  defer { bare.cleanUp() }

  let broken = try Sandbox()
  defer { broken.cleanUp() }
  try broken.addRunner(
    label: "actions.runner.acme-widget.ghost", agentId: 9,
    gitHubUrl: "https://github.com/acme/widget", runnerFile: .missing)

  let nothingInstalled = RunnerDiscovery(launchAgentsDirectory: bare.launchAgents).discover()
  let nothingReadable = RunnerDiscovery(launchAgentsDirectory: broken.launchAgents).discover()

  #expect(nothingInstalled.runners.isEmpty)
  #expect(nothingInstalled.unreadable.isEmpty)

  #expect(nothingReadable.runners.isEmpty)
  #expect(
    nothingReadable.unreadable.map(\.lastPathComponent)
      == ["actions.runner.acme-widget.ghost.plist"])
}

@Test func returnsEmptyWhenThereIsNoLaunchAgentsDirectory() {
  let missing = URL(fileURLWithPath: "/nope/does/not/exist")
  let found = RunnerDiscovery(launchAgentsDirectory: missing).discover()

  #expect(found.runners.isEmpty)
  #expect(found.unreadable.isEmpty)
}
