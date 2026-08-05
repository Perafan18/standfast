import Foundation

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

  /// Sequential, and blocking for `settleDelay` in between: `svc.sh` has no
  /// restart verb, and handing launchd a load while it is still unloading
  /// leaves the service down. Call it off the main actor.
  public func restart(in directory: URL) throws {
    try stop(in: directory)
    if settleDelay > 0 { Thread.sleep(forTimeInterval: settleDelay) }
    try start(in: directory)
  }

  private func svc(_ verb: String, in directory: URL) throws {
    let script = directory.appendingPathComponent("svc.sh").path
    // `svc.sh` resolves its own paths from the current directory, not from
    // where the script itself lives.
    _ = try commandRunner.run("/bin/bash", [script, verb], workingDirectory: directory)
  }
}
