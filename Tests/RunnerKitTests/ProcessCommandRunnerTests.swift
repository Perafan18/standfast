import Foundation
import Testing

@testable import RunnerKit

/// Exercised against binaries every macOS ships, so the one implementation
/// that actually spawns processes is covered on a CI machine with no runner
/// installed.
private let runner = ProcessCommandRunner()

@Test func returnsWhatTheProcessWroteToStdout() throws {
  #expect(try runner.run("/bin/echo", ["hello", "world"]) == "hello world\n")
}

@Test func runsTheProcessInTheGivenWorkingDirectory() throws {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("cwd-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  // -P prints the physical path, and both sides get resolved afterwards:
  // macOS reaches the temporary directory through the /var and /private
  // symlinks, so the two spellings are the same directory.
  let printed = try runner.run("/bin/pwd", ["-P"], workingDirectory: directory)
  let reported = URL(fileURLWithPath: printed.trimmingCharacters(in: .newlines))

  #expect(reported.resolvingSymlinksInPath().path
          == directory.resolvingSymlinksInPath().path)
}

@Test func throwsWhenTheExecutableIsNotThere() {
  #expect(throws: CommandError.couldNotLaunch("/nope/not-an-executable")) {
    try runner.run("/nope/not-an-executable", [])
  }
}

@Test func aNonZeroExitIsNotAnError() throws {
  // Declared contract: only a failure to launch throws. `svc.sh` and `gh`
  // both exit non-zero in situations their caller wants to read, not catch.
  #expect(try runner.run("/usr/bin/false", []) == "")
}

@Test func stderrDoesNotContaminateStdout() throws {
  let output = try runner.run("/bin/sh", ["-c", "echo out; echo err >&2"])
  #expect(output == "out\n")
}

/// Carries a result off the thread the command was run on.
private final class Box: @unchecked Sendable { var output: String? }

/// Runs the command on another thread and gives up after 30 seconds.
///
/// Swift Testing's time limits only bite at suspension points, so a `run()`
/// deadlocked against a full pipe would hang the entire suite rather than fail
/// the one test that provoked it. Returns nil when the deadline passes.
private func runAgainstADeadline(_ executable: String, _ arguments: [String]) -> String? {
  let box = Box()
  let finished = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    box.output = try? runner.run(executable, arguments)
    finished.signal()
  }
  guard finished.wait(timeout: .now() + 30) == .success else {
    Issue.record("\(executable) never came back: it is blocked writing into a pipe nobody drains")
    return nil
  }
  return box.output
}

/// Big enough that printing it overflows the ~64 KB a pipe holds.
private func makeChatterFile() throws -> URL {
  let file = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("chatty-\(UUID().uuidString).txt")
  try Data(String(repeating: "a", count: 200_000).utf8).write(to: file)
  return file
}

@Test func readsOutputBiggerThanThePipeBuffer() throws {
  // Waiting for the child before draining stdout deadlocks both processes,
  // and only chatty commands ever reach that size.
  let file = try makeChatterFile()
  defer { try? FileManager.default.removeItem(at: file) }

  #expect(runAgainstADeadline("/bin/cat", [file.path])?.count == 200_000)
}

@Test func survivesAProcessThatIsChattyOnStderr() throws {
  // Why stderr goes to the null device instead of a pipe: nothing ever reads
  // that pipe, so the child stops the moment it fills — and `gh` reports its
  // failures at length.
  let file = try makeChatterFile()
  defer { try? FileManager.default.removeItem(at: file) }

  #expect(runAgainstADeadline("/bin/sh", ["-c", "cat \(file.path) >&2; echo done"])
          == "done\n")
}
