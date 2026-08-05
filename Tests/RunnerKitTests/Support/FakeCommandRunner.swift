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

  private let responses: [String: String]
  private(set) var invocations: [Invocation] = []
  var failingExecutables: Set<String> = []

  /// Invocations as `"executable arg arg"`, for assertions about what ran
  /// rather than where.
  var commands: [String] {
    invocations.map { ([$0.executable] + $0.arguments).joined(separator: " ") }
  }

  /// Keyed by `"executable arg arg"`: the working directory changes what a
  /// command does to the machine, never what it prints back here.
  init(_ responses: [String: String] = [:]) { self.responses = responses }

  func run(_ executable: String, _ arguments: [String], workingDirectory: URL?) throws
    -> String
  {
    invocations.append(
      Invocation(
        executable: executable, arguments: arguments,
        workingDirectory: workingDirectory))
    if failingExecutables.contains(executable) {
      throw CommandError.couldNotLaunch(executable)
    }
    return responses[([executable] + arguments).joined(separator: " ")] ?? ""
  }
}
