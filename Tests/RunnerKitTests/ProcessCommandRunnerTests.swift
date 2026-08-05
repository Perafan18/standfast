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
private final class Box: @unchecked Sendable { var count: Int? }

@Test func readsOutputBiggerThanThePipeBuffer() throws {
  // A pipe holds ~64 KB. Waiting for the child before draining it deadlocks
  // both processes, and only chatty commands ever reach that size.
  let file = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("chatty-\(UUID().uuidString).txt")
  try Data(String(repeating: "a", count: 200_000).utf8).write(to: file)
  defer { try? FileManager.default.removeItem(at: file) }

  // Run off this thread against a deadline. Swift Testing's time limits only
  // bite at suspension points, so a deadlocked `run()` would otherwise hang
  // the whole suite instead of failing this one test.
  let box = Box()
  let finished = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    box.count = try? runner.run("/bin/cat", [file.path]).count
    finished.signal()
  }

  guard finished.wait(timeout: .now() + 30) == .success else {
    Issue.record("run() never came back: the child filled the pipe and both sides are waiting")
    return
  }
  #expect(box.count == 200_000)
}
