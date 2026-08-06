import Foundation
import Testing

@testable import RunnerKit

/// Exercised against binaries every macOS ships, so the one implementation
/// that actually spawns processes is covered on a CI machine with no runner
/// installed.
private let runner = ProcessCommandRunner()

@Test func returnsWhatTheProcessWroteToStdout() throws {
  #expect(try runner.run("/bin/echo", ["hello", "world"]).standardOutput == "hello world\n")
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
  let reported = URL(
    fileURLWithPath: printed.standardOutput.trimmingCharacters(in: .newlines))

  #expect(reported.resolvingSymlinksInPath().path
          == directory.resolvingSymlinksInPath().path)
}

@Test func throwsWhenTheExecutableIsNotThere() {
  #expect {
    try runner.run("/nope/not-an-executable", [])
  } throws: { error in
    guard case .couldNotLaunch(let executable, _) = error as? CommandError
    else { return false }
    return executable == "/nope/not-an-executable"
  }
}

@Test func carriesTheFailureFoundationReported() {
  // Kept whole rather than flattened to a string, for whoever ends up having
  // to explain the failure to a user.
  #expect {
    try runner.run("/nope/not-an-executable", [])
  } throws: { error in
    guard case .couldNotLaunch(_, let underlying) = error as? CommandError
    else { return false }
    let reported = underlying as NSError
    return reported.domain == NSCocoaErrorDomain && reported.code == NSFileNoSuchFileError
  }
}

@Test func aNonZeroExitIsNotAnError() throws {
  // Declared contract: only a failure to launch or a missed deadline throws.
  // `svc.sh` and `gh` both exit non-zero in situations their caller wants to
  // read, not catch.
  let result = try runner.run("/usr/bin/false", [])
  #expect(result.exitCode == 1)
  #expect(result.standardOutput == "")
}

@Test func reportsZeroForACommandThatWorked() throws {
  #expect(try runner.run("/bin/echo", ["hi"]).exitCode == 0)
}

@Test func reportsTheExitCodeThatMeansCommandNotFound() throws {
  // The case this exists for: an app launched from Finder gets a PATH without
  // Homebrew, so `gh` is missing and env exits 127 with nothing on stdout.
  // Without the code, that is indistinguishable from gh answering nothing.
  let result = try runner.run("/usr/bin/env", ["definitely-not-installed-xyz"])
  #expect(result.exitCode == 127)
  #expect(result.standardOutput == "")
}

@Test func stderrDoesNotContaminateStdout() throws {
  #expect(try runner.run("/bin/sh", ["-c", "echo out; echo err >&2"]).standardOutput
          == "out\n")
}

@Test func returnsOutputThatIsNotValidUTF8AsBestItCan() throws {
  // One stray byte must not blank the whole answer: a `launchctl list` turned
  // into "" would report every runner on the machine as stopped.
  let result = try runner.run("/bin/sh", ["-c", #"printf 'a\377b'"#])
  #expect(result.standardOutput.hasPrefix("a"))
  #expect(result.standardOutput.hasSuffix("b"))
}

/// Carries a result off the thread the command was run on.
private final class Box: @unchecked Sendable {
  var result: CommandResult?
  var error: (any Error)?
}

/// Runs the command on another thread and gives up after 30 seconds.
///
/// Swift Testing's time limits only bite at suspension points, so a `run()`
/// deadlocked against a full pipe would hang the entire suite rather than fail
/// the one test that provoked it. Returns nil when the deadline passes.
private func runAgainstADeadline(
  _ runner: ProcessCommandRunner, _ executable: String, _ arguments: [String]
) -> Box? {
  let box = Box()
  let finished = DispatchSemaphore(value: 0)
  DispatchQueue.global().async {
    do { box.result = try runner.run(executable, arguments) } catch { box.error = error }
    finished.signal()
  }
  guard finished.wait(timeout: .now() + 30) == .success else {
    Issue.record(
      "\(executable) never came back: it is blocked writing into a pipe nobody drains")
    return nil
  }
  return box
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

  #expect(runAgainstADeadline(runner, "/bin/cat", [file.path])?.result?.standardOutput.count
          == 200_000)
}

@Test func survivesAProcessThatIsChattyOnStderr() throws {
  // Why stderr goes to the null device instead of a pipe: nothing ever reads
  // that pipe, so the child stops the moment it fills — and `gh` reports its
  // failures at length.
  let file = try makeChatterFile()
  defer { try? FileManager.default.removeItem(at: file) }

  #expect(runAgainstADeadline(runner, "/bin/sh", ["-c", "cat \(file.path) >&2; echo done"])?
          .result?.standardOutput == "done\n")
}

@Test func givesUpOnAProcessThatNeverFinishes() throws {
  // `gh` does network I/O, and a stalled TLS handshake would otherwise block
  // this thread forever.
  let impatient = ProcessCommandRunner(timeout: 0.3, terminationGrace: 0.3)
  let box = runAgainstADeadline(impatient, "/bin/sleep", ["30"])

  guard case .timedOut(let executable)? = box?.error as? CommandError else {
    Issue.record(
      "expected a timeout, got \(String(describing: box?.error ?? box?.result as Any))")
    return
  }
  #expect(executable == "/bin/sleep")
}

@Test func killsAProcessThatIgnoresThePoliteSignal() throws {
  // SIGTERM is a request. `exec` keeps the ignored disposition, so this is a
  // single process that only SIGKILL can stop.
  let impatient = ProcessCommandRunner(timeout: 0.3, terminationGrace: 0.3)
  let box = runAgainstADeadline(
    impatient, "/bin/sh", ["-c", "trap '' TERM; exec sleep 30"])

  #expect(box?.error is CommandError)
}
