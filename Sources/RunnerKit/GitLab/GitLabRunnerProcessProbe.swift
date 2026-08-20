import Foundation

/// Asks whether the gitlab-runner service is running on this machine.
///
/// Per machine, not per runner, because that is how gitlab-runner works: one
/// process serves every `[[runners]]` entry in `config.toml`. Which is also why
/// this app offers no Stop button for a GitLab runner — stopping the process
/// stops all of them, and that is a decision for a terminal, made on purpose.
public struct GitLabRunnerProcessProbe: Sendable {
  private let commandRunner: any CommandRunning

  public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
    self.commandRunner = commandRunner
  }

  /// Whether the service process is up, or nil when the process table could
  /// not be read — which says nothing about the runner and must not be drawn
  /// as "stopped". The same rule every local probe here follows.
  ///
  /// Blocks the calling thread inside `ps`; see `offCooperativePool`.
  public func blockingIsRunning() -> Bool? {
    guard
      let listing = try? commandRunner.run("/bin/ps", ["-Awwo", "command="]),
      listing.exitCode == 0
    else { return nil }

    for line in listing.standardOutput.split(separator: "\n") {
      let command = line.trimmingCharacters(in: .whitespaces)
      let parts = command.split(separator: " ", omittingEmptySubsequences: true)
      // The executable itself, then the `run` subcommand. `register`, `verify`
      // and friends are real invocations somebody may have open right now, and
      // none of them is the long-lived process that takes jobs. The name is
      // matched as a whole path component so a wrapper that merely contains
      // the words is not mistaken for the service.
      guard parts.count >= 2, parts[1] == "run" else { continue }
      let executable = String(parts[0])
      if executable == "gitlab-runner" || executable.hasSuffix("/gitlab-runner") {
        return true
      }
    }
    return false
  }
}
