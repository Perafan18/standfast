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

  private let responses: [[String]: String]
  private(set) var invocations: [Invocation] = []
  var failingExecutables: Set<String> = []

  /// Keyed by the argument list rather than by a joined string: `["gh", "a b"]`
  /// and `["gh", "a", "b"]` are different commands, and a `gh --jq` filter is
  /// one argument with spaces in it.
  init(_ responses: [[String]: String] = [:]) { self.responses = responses }

  func run(_ executable: String, _ arguments: [String], workingDirectory: URL?) throws
    -> CommandResult
  {
    invocations.append(
      Invocation(
        executable: executable, arguments: arguments,
        workingDirectory: workingDirectory))
    if failingExecutables.contains(executable) {
      throw CommandError.couldNotLaunch(
        executable: executable, underlying: LaunchFailure())
    }
    return CommandResult(
      standardOutput: responses[[executable] + arguments] ?? "", exitCode: 0)
  }
}
