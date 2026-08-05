import Foundation

/// What the menu bar shows, in the order the icon cares about.
public enum RunnerState: Equatable {
  /// Registered, connected, waiting for work.
  case idle
  /// Executing a job right now.
  case busy
  /// The service is running locally but GitHub does not see it, or vice
  /// versa. Worth its own state: "the process is up" and "GitHub will send
  /// it work" are different claims, and only the second one matters.
  case disconnected
  /// The LaunchAgent is not running.
  case stopped
  /// Could not determine — no token, no network, `svc.sh` missing.
  case unknown(String)
}

/// Reads and controls a self-hosted GitHub Actions runner installed as a
/// per-user LaunchAgent.
///
/// Two sources of truth, deliberately kept apart:
///
/// - `svc.sh status` says whether the local process is alive.
/// - The GitHub API says whether GitHub considers the runner online and
///   whether it is currently busy.
///
/// They disagree more often than you would expect — a runner whose token has
/// expired keeps its process happily running while GitHub has written it off.
/// Showing only the local view would report "fine" for a runner that will
/// never receive another job.
public struct RunnerService: Sendable {
  let runnerDirectory: URL
  let repository: String  // "owner/repo"

  public init(runnerDirectory: URL, repository: String) {
    self.runnerDirectory = runnerDirectory
    self.repository = repository
  }

  /// Runs a command and returns stdout, or nil if it could not be launched.
  private func shell(_ launchPath: String, _ args: [String], cwd: URL? = nil)
    -> String?
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = args
    if let cwd { process.currentDirectoryURL = cwd }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)
  }

  /// True when the LaunchAgent process is alive.
  func localServiceRunning() -> Bool {
    let script = runnerDirectory.appendingPathComponent("svc.sh").path
    guard FileManager.default.fileExists(atPath: script) else { return false }
    let out = shell("/bin/bash", [script, "status"], cwd: runnerDirectory) ?? ""
    // `svc.sh status` prints "Started:" followed by the pid when it is up, and
    // "Stopped" when it is not. Matching on "Started" rather than the exit
    // code, which is 0 either way.
    return out.contains("Started:")
  }

  /// What GitHub thinks, via `gh`. Nil when it cannot be asked.
  func remoteStatus() -> (online: Bool, busy: Bool)? {
    let out = shell(
      "/usr/bin/env",
      [
        "gh", "api", "repos/\(repository)/actions/runners",
        "--jq", ".runners[0] | \"\\(.status) \\(.busy)\"",
      ]
    )
    guard let line = out?.trimmingCharacters(in: .whitespacesAndNewlines),
      !line.isEmpty, !line.contains("null")
    else { return nil }
    let parts = line.split(separator: " ")
    guard parts.count == 2 else { return nil }
    return (online: parts[0] == "online", busy: parts[1] == "true")
  }

  public func currentState() -> RunnerState {
    let local = localServiceRunning()
    guard let remote = remoteStatus() else {
      // No answer from GitHub. Report what is actually known rather than
      // guessing: a stopped service is certain, everything else is not.
      return local ? .unknown("sin respuesta de GitHub") : .stopped
    }
    if !local { return .stopped }
    if !remote.online { return .disconnected }
    return remote.busy ? .busy : .idle
  }

  @discardableResult
  public func start() -> Bool { runSvc("start") }

  @discardableResult
  public func stop() -> Bool { runSvc("stop") }

  /// Stop then start. Sequential on purpose: `svc.sh` has no restart, and
  /// firing both at once leaves launchd racing itself.
  @discardableResult
  public func restart() -> Bool {
    guard runSvc("stop") else { return false }
    Thread.sleep(forTimeInterval: 1.5)
    return runSvc("start")
  }

  private func runSvc(_ command: String) -> Bool {
    let script = runnerDirectory.appendingPathComponent("svc.sh").path
    guard FileManager.default.fileExists(atPath: script) else { return false }
    // No sudo. On macOS the runner is a per-user LaunchAgent — sudo is the
    // Linux instruction and would only prompt for a password this app has no
    // way to answer.
    return shell("/bin/bash", [script, command], cwd: runnerDirectory) != nil
  }
}
