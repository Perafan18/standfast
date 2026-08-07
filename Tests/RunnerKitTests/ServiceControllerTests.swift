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
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
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

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = false

  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func set() {
    lock.lock()
    storage = true
    lock.unlock()
  }
}

private func waitUntil(
  timeout: Duration = .seconds(1), _ condition: () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !condition() {
    guard clock.now < deadline else { throw TestWaitFailure.timedOut }
    try await Task.sleep(for: .milliseconds(1))
  }
}

private enum TestWaitFailure: Error { case timedOut }

@Test func startRunsSvcStartInTheRunnerDirectory() async throws {
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  try await ServiceController(commandRunner: fake).start(in: box.directory)

  #expect(fake.invocations == [box.invocation("start")])
}

@Test func stopRunsSvcStopInTheRunnerDirectory() async throws {
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  try await ServiceController(commandRunner: fake).stop(in: box.directory)

  #expect(fake.invocations == [box.invocation("stop")])
}

@Test func theBlockingCallsRunTheSameCommandsAsTheirFacades() throws {
  // The facade must not quietly become a different command from the one a
  // library consumer gets when it takes the thread on itself.
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()
  let controller = ServiceController(commandRunner: fake)

  try controller.blockingStart(in: box.directory)
  try controller.blockingStop(in: box.directory)

  #expect(fake.invocations == [box.invocation("start"), box.invocation("stop")])
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

@Test func cancellationDuringRestartPauseIsAPostStopFailure() async throws {
  // Stop has returned before the pause begins. Cancellation there must retain
  // that phase instead of looking like a failure that happened before Stop.
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()
  let stopped = LockedFlag()
  fake.onRun = { stopped.set() }
  let controller = ServiceController(commandRunner: fake, settleDelay: 60)
  let restart = Task { try await controller.restart(in: box.directory) }

  try await waitUntil { stopped.value }
  restart.cancel()

  do {
    try await restart.value
    Issue.record("Restart unexpectedly succeeded after cancellation")
  } catch let failure as RestartStartFailure {
    #expect(failure.underlying is CancellationError)
  } catch {
    Issue.record("Expected RestartStartFailure, got \(error)")
  }
  #expect(fake.invocations == [box.invocation("stop")])
}

@Test @MainActor func everyAsyncEntryPointKeepsItsBlockingOffBothPools() async throws {
  // `svc.sh` parks a thread inside waitUntilExit for up to the command
  // timeout. The cooperative pool has one thread per core and runs every
  // `Task {}`, so an app driving a runner from a button would stall it — and
  // these entry points are `async`, which means callers have no thread of
  // their own to hand them. The hop has to happen in here, for all three.
  final class Queues: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func record(_ label: String) {
      lock.lock()
      defer { lock.unlock() }
      seen.append(label)
    }
    var all: [String] {
      lock.lock()
      defer { lock.unlock() }
      return seen
    }
  }
  let box = try RunnerSandbox()
  defer { box.cleanUp() }
  let queues = Queues()
  let fake = FakeCommandRunner()
  fake.onRun = {
    queues.record(String(validatingCString: __dispatch_queue_get_label(nil)) ?? "")
  }
  let controller = ServiceController(commandRunner: fake, settleDelay: 0)

  try await controller.start(in: box.directory)
  try await controller.stop(in: box.directory)
  try await controller.restart(in: box.directory)

  #expect(queues.all.count == 4)
  #expect(!queues.all.contains { $0.hasSuffix(".cooperative") })
  #expect(!queues.all.contains { $0 == "com.apple.main-thread" })
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

  try controller.blockingStart(in: first.directory)
  try controller.blockingStart(in: second.directory)

  #expect(fake.invocations == [first.invocation("start"), second.invocation("start")])
}

@Test func refusesADirectoryWithNoSvcScript() throws {
  // A half-uninstalled runner, which discovery already models. Firing bash at
  // a script that is not there exits 127 and looks, from here, like success.
  let box = try RunnerSandbox(withScript: false)
  defer { box.cleanUp() }
  let fake = FakeCommandRunner()

  #expect(throws: ServiceControlError.scriptMissing(box.script)) {
    try ServiceController(commandRunner: fake).blockingStart(in: box.directory)
  }
  #expect(fake.invocations.isEmpty)
}
