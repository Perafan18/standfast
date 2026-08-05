import Foundation
import Testing

@testable import RunnerKit

private let runnerDirectory = URL(fileURLWithPath: "/Users/ci/actions-runner")

private func svc(_ verb: String) -> FakeCommandRunner.Invocation {
  // `svc.sh` reads the runner directory it sits in, so the working directory
  // is as much a part of the call as the verb.
  .init(
    executable: "/bin/bash",
    arguments: ["/Users/ci/actions-runner/svc.sh", verb],
    workingDirectory: runnerDirectory)
}

@Test func startRunsSvcStartInTheRunnerDirectory() throws {
  let fake = FakeCommandRunner()
  try ServiceController(commandRunner: fake).start(in: runnerDirectory)
  #expect(fake.invocations == [svc("start")])
}

@Test func stopRunsSvcStopInTheRunnerDirectory() throws {
  let fake = FakeCommandRunner()
  try ServiceController(commandRunner: fake).stop(in: runnerDirectory)
  #expect(fake.invocations == [svc("stop")])
}

@Test func restartStopsThenStarts() throws {
  // svc.sh has no restart verb, and firing both at once leaves launchd
  // racing itself, so the order is load-bearing.
  let fake = FakeCommandRunner()
  try ServiceController(commandRunner: fake, settleDelay: 0).restart(in: runnerDirectory)
  #expect(fake.invocations == [svc("stop"), svc("start")])
}

@Test func restartDoesNotStartWhenStopFailed() {
  let fake = FakeCommandRunner()
  fake.failingExecutables = ["/bin/bash"]
  #expect(throws: CommandError.couldNotLaunch("/bin/bash")) {
    try ServiceController(commandRunner: fake, settleDelay: 0).restart(in: runnerDirectory)
  }
  #expect(fake.invocations == [svc("stop")])
}

@Test func eachRunnerIsControlledInItsOwnDirectory() {
  // One controller serves the whole machine; the directory is an argument,
  // not state, so two runners cannot end up sharing one svc.sh.
  let fake = FakeCommandRunner()
  let controller = ServiceController(commandRunner: fake)
  let other = URL(fileURLWithPath: "/Users/ci/second-runner")

  try? controller.start(in: runnerDirectory)
  try? controller.start(in: other)

  #expect(fake.invocations.last
          == .init(executable: "/bin/bash",
                   arguments: ["/Users/ci/second-runner/svc.sh", "start"],
                   workingDirectory: other))
}

@Test func waitsBetweenStoppingAndStartingSoLaunchdSettles() throws {
  // Restarting with no gap hands launchd a load while it is still unloading.
  let fake = FakeCommandRunner()
  let started = Date()
  try ServiceController(commandRunner: fake, settleDelay: 0.2).restart(in: runnerDirectory)
  #expect(Date().timeIntervalSince(started) >= 0.2)
}
