import Foundation

@testable import RunnerKit

/// Replays canned stdout and records every invocation, working directory
/// included — `svc.sh` reads its own directory, so a fake that forgot it would
/// let that regression through unnoticed.
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
  struct Invocation: Equatable {
    let executable: String
    let arguments: [String]
    let workingDirectory: URL?
  }

  /// Stands in for whatever Foundation reports when a launch fails.
  struct LaunchFailure: Error {}

  private var responses: [[String]: String]
  private(set) var invocations: [Invocation] = []
  var failingExecutables: Set<String> = []
  /// Executables that run and never finish. Distinct from `failingExecutables`
  /// because the two mean opposite things to a caller looking for `gh`: one
  /// says "nothing is installed here", the other says "it is installed and it
  /// did not answer".
  var timingOutExecutables: Set<String> = []
  /// Exit codes for commands that ran and failed, keyed like `responses`.
  /// Absent means 0. Needed because the interesting `gh` failures are all
  /// exit-code-only: 127 when it is not on PATH, 4 when it is not
  /// authenticated, both with an empty stdout.
  var exitCodes: [[String]: Int32] = [:]
  /// Runs inside `run`, on whatever thread called it. The only way to observe
  /// where a synchronous command was executed from.
  var onRun: (@Sendable () -> Void)?

  /// Keyed by the argument list rather than by a joined string: `["gh", "a b"]`
  /// and `["gh", "a", "b"]` are different commands, and a `gh --jq` filter is
  /// one argument with spaces in it.
  init(_ responses: [[String]: String] = [:]) { self.responses = responses }

  /// For the tests whose fakes are built before their answers are decided.
  /// Keyed exactly like the initialiser, executable included.
  func respond(to command: [String], with output: String) {
    responses[command] = output
  }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    onRun?()
    invocations.append(
      Invocation(
        executable: executable, arguments: arguments,
        workingDirectory: workingDirectory))
    if failingExecutables.contains(executable) {
      throw CommandError.couldNotLaunch(
        executable: executable, underlying: LaunchFailure())
    }
    if timingOutExecutables.contains(executable) {
      throw CommandError.timedOut(executable: executable)
    }
    let command = [executable] + arguments
    return CommandResult(
      standardOutput: responses[command] ?? "", exitCode: exitCodes[command] ?? 0)
  }
}
