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

  /// Starts the runner's service without tying up a thread the runtime needs.
  ///
  /// This is the entry point to use, and the reason it exists is the same one
  /// `RunnerStateResolver.state(for:)` exists for: the blocking call underneath
  /// parks a whole thread inside `waitUntilExit()`. See `offCooperativePool`.
  public func start(in directory: URL) async throws {
    try await offCooperativePool { try blockingStart(in: directory) }
  }

  /// Stops the runner's service without tying up a thread the runtime needs.
  /// See `start(in:)`.
  public func stop(in directory: URL) async throws {
    try await offCooperativePool { try blockingStop(in: directory) }
  }

  /// Blocks the calling thread inside `svc.sh` for up to the command runner's
  /// timeout — thirty seconds by default. Safe to call directly only from a
  /// thread that is yours to block, which rules out the main actor and the
  /// cooperative pool behind every `Task`. Prefer the `async` overload above,
  /// which makes the hop for you.
  public func blockingStart(in directory: URL) throws { try svc("start", in: directory) }

  /// Blocks the calling thread, exactly as `blockingStart(in:)` does. Prefer
  /// `stop(in:)`.
  public func blockingStop(in directory: URL) throws { try svc("stop", in: directory) }

  /// Sequential, with a pause in between: `svc.sh` has no restart verb, and
  /// handing launchd a load while it is still unloading leaves the service
  /// down.
  ///
  /// There is no blocking counterpart to this one, and that is deliberate: the
  /// pause is `Task.sleep`, so a synchronous version would have to be a real
  /// sleep, and a button wired straight to it would freeze the menu for the
  /// whole gap. Composing the two async halves also keeps launchd's
  /// unload-before-load requirement where it belongs, in the only type that
  /// knows about it.
  public func restart(in directory: URL) async throws {
    try await stop(in: directory)
    if settleDelay > 0 { try await Task.sleep(for: .seconds(settleDelay)) }
    try await start(in: directory)
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
