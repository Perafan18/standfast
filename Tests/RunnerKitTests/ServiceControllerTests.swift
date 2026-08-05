import Foundation
import Testing

@testable import RunnerKit

/// A runner directory on disk: the controller refuses to hand bash a `svc.sh`
/// that is not there, so these tests need real files.
private struct RunnerSandbox {
  let directory: URL

  init(withScript: Bool = true) throws {
    directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if withScript {
      try Data("#!/bin/bash\n".utf8).write(to: script)
    }
  }

  var script: URL { directory.appendingPathComponent("svc.sh") }
  func cleanUp() { try? FileManager.default.removeItem(at: directory) }

  /// svc.sh reads the runner directory it sits in, so the working directory is
  /// as much a part of the call as the verb.
  func invocation(_ verb: String) -> FakeCommandRunner.Invocation {
    .init(
      executable: "/bin/bash", arguments: [script.path, verb],
      workingDirectory: directory)
  }
}

@Test func startRunsSvcStartInTheRunnerDirectory() throws {
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  try ServiceController(commandRunner: fake).start(in: box.directory)

  #expect(fake.invocations == [box.invocation("start")])
}

@Test func stopRunsSvcStopInTheRunnerDirectory() throws {
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  try ServiceController(commandRunner: fake).stop(in: box.directory)

  #expect(fake.invocations == [box.invocation("stop")])
}

@Test func restartStopsThenStarts() async throws {
  // svc.sh has no restart verb, and firing both at once leaves launchd
  // racing itself, so the order is load-bearing.
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  try await ServiceController(commandRunner: fake, settleDelay: 0)
    .restart(in: box.directory)

  #expect(fake.invocations == [box.invocation("stop"), box.invocation("start")])
}

@Test func restartDoesNotStartWhenStopFailed() async throws {
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()
  fake.failingExecutables = ["/bin/bash"]

  await #expect(throws: CommandError.self) {
    try await ServiceController(commandRunner: fake, settleDelay: 0)
      .restart(in: box.directory)
  }
  #expect(fake.invocations == [box.invocation("stop")])
}

@Test func waitsBetweenStoppingAndStartingSoLaunchdSettles() async throws {
  // Restarting with no gap hands launchd a load while it is still unloading.
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let started = Date()

  try await ServiceController(commandRunner: FakeCommandRunner(), settleDelay: 0.2)
    .restart(in: box.directory)

  #expect(Date().timeIntervalSince(started) >= 0.2)
}

@Test func eachRunnerIsControlledInItsOwnDirectory() throws {
  // One controller serves the whole machine; the directory is an argument,
  // not state, so two runners cannot end up sharing one svc.sh.
  let first = try RunnerSandbox()
  let second = try RunnerSandbox()
  defer {
    first.cleanUp()
    second.cleanUp()
  }
  let fake = FakeCommandRunner()
  let controller = ServiceController(commandRunner: fake)

  try controller.start(in: first.directory)
  try controller.start(in: second.directory)

  #expect(fake.invocations == [first.invocation("start"), second.invocation("start")])
}

@Test func refusesADirectoryWithNoSvcScript() throws {
  // A half-uninstalled runner, which discovery already models. Firing bash at
  // a script that is not there exits 127 and looks, from here, like success.
  let box = try RunnerSandbox(withScript: false)
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  #expect(throws: ServiceControlError.scriptMissing(box.script)) {
    try ServiceController(commandRunner: fake).start(in: box.directory)
  }
  #expect(fake.invocations.isEmpty)
}
