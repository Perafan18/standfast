import Foundation

public enum ServiceControlError: Error, Equatable {
  /// The runner directory has no `svc.sh`: an uninstall that stopped halfway,
  /// or a directory that was never a runner.
  case scriptMissing(URL)
}

/// Starts and stops a runner's LaunchAgent through the `svc.sh` the runner
/// ships. No sudo: on macOS the runner is a per-user LaunchAgent, and sudo is
/// the Linux instruction — it would only prompt for a password this app has no
/// way to answer.
///
/// The directory is a parameter rather than stored state, so one controller
/// serves every runner on the machine.
public struct ServiceController: Sendable {
  private let commandRunner: any CommandRunning
  private let settleDelay: TimeInterval

  public init(
    commandRunner: any CommandRunning = ProcessCommandRunner(),
    settleDelay: TimeInterval = 1.5
  ) {
    self.commandRunner = commandRunner
    self.settleDelay = settleDelay
  }

  public func start(in directory: URL) throws { try svc("start", in: directory) }
  public func stop(in directory: URL) throws { try svc("stop", in: directory) }

  /// Sequential, with a pause in between: `svc.sh` has no restart verb, and
  /// handing launchd a load while it is still unloading leaves the service
  /// down.
  ///
  /// Async so the pause cannot be taken on the main actor by accident — a
  /// button wired straight to a sleeping function freezes the menu.
  public func restart(in directory: URL) async throws {
    try stop(in: directory)
    if settleDelay > 0 { try await Task.sleep(for: .seconds(settleDelay)) }
    try start(in: directory)
  }

  private func svc(_ verb: String, in directory: URL) throws {
    let script = directory.appendingPathComponent("svc.sh")
    // Checked rather than left to bash: a missing script comes back as exit
    // 127 with an empty stdout, and svc.sh's own exit codes are too unreliable
    // to read a cause out of — `svc.sh start` exits 0 even when the launchctl
    // underneath it printed a failure.
    guard FileManager.default.fileExists(atPath: script.path) else {
      throw ServiceControlError.scriptMissing(script)
    }
    // Handed to bash rather than executed directly: a runner directory that
    // was copied or restored from a backup often arrives without the execute
    // bit, and svc.sh is a bash script either way.
    //
    // The working directory matters as much as the verb — svc.sh resolves its
    // template and its plist path from `pwd`, not from where it lives.
    _ = try commandRunner.run("/bin/bash", [script.path, verb], workingDirectory: directory)
  }
}
