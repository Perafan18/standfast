import Foundation
import RunnerKit

/// A throwaway machine: a LaunchAgents directory, one runner directory with the
/// `.runner` and `svc.sh` a real installation leaves behind, and controllable
/// answers from `launchctl` and GitHub.
///
/// Discovery reads the real filesystem, so the files have to exist. Everything
/// past that is injected.
final class FleetSandbox: @unchecked Sendable {
  let root: URL
  private let lock = NSLock()
  private var running: Bool
  private var remote: Result<RemoteStatus, GitHubError>
  private var scans = 0
  private var probes = 0
  private var queues: [String] = []
  private var discoveryQueues: [String] = []
  /// Held for the duration of every GitHub call, so a test can make a scan
  /// slow enough to still be running when the next one is asked for.
  private var delay: TimeInterval = 0

  init(
    serviceRunning: Bool = false,
    remote: RemoteStatus = .init(online: true, busy: false)
  ) throws {
    self.running = serviceRunning
    self.remote = .success(remote)
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fleet-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: launchAgents, withIntermediateDirectories: true)
  }

  var launchAgents: URL { root.appendingPathComponent("LaunchAgents") }
  func cleanUp() { try? FileManager.default.removeItem(at: root) }

  /// How many times GitHub was asked. Zero for a stopped runner, which the
  /// resolver settles without asking.
  var scanCount: Int { withLock { scans } }
  /// How many times the machine was read at all, stopped runners included.
  var probeCount: Int { withLock { probes } }

  /// The dispatch queue each GitHub call arrived on.
  ///
  /// The label is what tells the two pools apart. `Thread.isMainThread` cannot:
  /// a nonisolated `async` function called from the main actor has already
  /// hopped off the main thread — onto the cooperative pool, which is the one
  /// place a blocking call must never land.
  var queuesUsed: [String] { withLock { queues } }

  func set(serviceRunning: Bool) { withLock { running = serviceRunning } }
  func set(remote answer: Result<RemoteStatus, GitHubError>) {
    withLock { remote = answer }
  }
  func set(delay seconds: TimeInterval) { withLock { delay = seconds } }

  /// A command runner that moves the sandbox's service the way `svc.sh` moves
  /// a real one, so a refresh landing mid-restart sees the service genuinely
  /// down rather than a fixed answer.
  var svcDrivingCommandRunner: RecordingCommandRunner {
    RecordingCommandRunner { [self] verb in set(serviceRunning: verb == "start") }
  }

  @discardableResult
  func addRunner(
    name: String = "build-mac", agentId: Int = 7, withScript: Bool = true
  ) throws -> URL {
    let label = "actions.runner.acme-widget.\(name)"
    let directory = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    let fields: [String: Any] = [
      "agentId": agentId, "agentName": name, "workFolder": "_work",
      "gitHubUrl": "https://github.com/acme/widget",
    ]
    try JSONSerialization.data(withJSONObject: fields)
      .write(to: directory.appendingPathComponent(".runner"))
    // The controller refuses a directory with no `svc.sh` before it runs
    // anything, so a sandbox without one is how a failing action is staged.
    if withScript {
      try Data("#!/bin/bash\n".utf8).write(to: directory.appendingPathComponent("svc.sh"))
    }
    let plist: [String: Any] = ["Label": label, "WorkingDirectory": directory.path]
    try PropertyListSerialization
      .data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: launchAgents.appendingPathComponent("\(label).plist"))
    return directory
  }

  /// Discovery, plus a note of where it was called from. Reading the whole
  /// LaunchAgents directory and a file per runner is filesystem work, and on a
  /// networked home directory it is not the microsecond it is here.
  var discover: @Sendable () -> DiscoveryResult {
    { [self] in
      let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
      withLock { discoveryQueues.append(queue) }
      return RunnerDiscovery(launchAgentsDirectory: launchAgents).discover()
    }
  }

  var discoveryQueuesUsed: [String] { withLock { discoveryQueues } }

  var resolver: RunnerStateResolver {
    RunnerStateResolver(
      isServiceRunning: { [self] _ in
        withLock {
          probes += 1
          return running
        }
      },
      github: Client(sandbox: self))
  }

  /// Answers whatever the sandbox is currently set to, and counts the asking.
  private struct Client: GitHubClient {
    let sandbox: FleetSandbox

    func runnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
      let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
      let (answer, pause) = sandbox.withLock {
        sandbox.scans += 1
        sandbox.queues.append(queue)
        return (sandbox.remote, sandbox.delay)
      }
      if pause > 0 { Thread.sleep(forTimeInterval: pause) }
      return try answer.get()
    }
  }

  fileprivate func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

/// Records what `svc.sh` was asked to do and always succeeds, which is what
/// the real one does even when it failed.
final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var seen: [[String]] = []
  private var queues: [String] = []
  private let onVerb: @Sendable (String) -> Void

  init(onVerb: @escaping @Sendable (String) -> Void = { _ in }) { self.onVerb = onVerb }

  var invocations: [[String]] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  /// The dispatch queue each `svc.sh` call arrived on. `svc.sh` blocks for as
  /// long as the command timeout allows, so where it runs is as much a part of
  /// the contract as what it runs.
  var queuesUsed: [String] {
    lock.lock()
    defer { lock.unlock() }
    return queues
  }

  func run(_ executable: String, _ arguments: [String], workingDirectory: URL?) throws
    -> CommandResult
  {
    let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
    lock.lock()
    seen.append([executable] + arguments)
    queues.append(queue)
    lock.unlock()
    if let verb = arguments.last { onVerb(verb) }
    return CommandResult(standardOutput: "", exitCode: 0)
  }
}
