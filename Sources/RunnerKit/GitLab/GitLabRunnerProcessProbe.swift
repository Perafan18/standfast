import Foundation

/// Asks whether the gitlab-runner service is running on this machine.
///
/// Per machine, not per runner, because that is how gitlab-runner works: one
/// process serves every `[[runners]]` entry in `config.toml`. Which is also why
/// this app offers no Stop button for a GitLab runner — stopping the process
/// stops all of them, and that is a decision for a terminal, made on purpose.
public struct GitLabRunnerProcessProbe: Sendable {
  private let commandRunner: any CommandRunning
  private let userID: uid_t

  public init(
    commandRunner: any CommandRunning = ProcessCommandRunner(), userID: uid_t = getuid()
  ) {
    self.commandRunner = commandRunner
    self.userID = userID
  }

  /// Whether the service process is up, or nil when the process table could
  /// not be read — which says nothing about the runner and must not be drawn
  /// as "stopped". The same rule every local probe here follows.
  ///
  /// Blocks the calling thread inside `ps`; see `offCooperativePool`.
  public func blockingIsRunning() -> Bool? {
    guard
      // This user's processes only: the config this app reads is this user's,
      // and another account's service, or a system one under root, serves
      // some other file.
      let listing = try? commandRunner.run(
        "/bin/ps", ["-wwo", "command=", "-U", String(userID)]),
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
      guard Self.subcommand(of: parts) == "run" else { continue }
      let executable = String(parts[0])
      if executable == "gitlab-runner" || executable.hasSuffix("/gitlab-runner") {
        return true
      }
    }
    return false
  }

  /// Global options that take a value, so the word after one is that value
  /// and not the subcommand.
  private static let optionsWithValue: Set<Substring> = [
    "--log-level", "-l", "--log-format", "--cpuprofile",
  ]

  /// The first word after the executable that is not a global option or an
  /// option's value. GitLab documents `gitlab-runner --debug run` for
  /// debugging, and that process is the service too.
  private static func subcommand(of parts: [Substring]) -> Substring? {
    var index = 1
    while index < parts.count {
      guard parts[index].hasPrefix("-") else { return parts[index] }
      index += optionsWithValue.contains(parts[index]) ? 2 : 1
    }
    return nil
  }
}
