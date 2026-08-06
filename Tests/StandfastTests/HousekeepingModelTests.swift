import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// Answers whatever it was told to, and remembers what it was shown.
@MainActor
private final class FakeConfirmation: CleanupConfirming {
  private(set) var prompts: [CleanupPrompt] = []
  var answer = true

  func confirm(_ prompt: CleanupPrompt) -> Bool {
    prompts.append(prompt)
    return answer
  }
}

/// A runner directory with a `_work` and a `_diag` in it, and a state a test
/// can change halfway through an operation.
private final class HousekeepingSandbox: @unchecked Sendable {
  let root: URL
  private let lock = NSLock()
  private var state: RunnerState = .idle
  private var probes = 0

  init() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("model-\(UUID().uuidString)")
    for folder in ["_work/_tool", "_work/_actions", "_work/nest-rules-app", "_diag"] {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    try Data(repeating: 0, count: 4096)
      .write(to: root.appendingPathComponent("_work/_tool/payload"))
  }

  func cleanUp() { try? FileManager.default.removeItem(at: root) }

  var runner: DiscoveredRunner {
    DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac", directory: root, agentId: 7,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "widget"))
  }

  /// What the probe will answer from now on. `onProbe` is how a test makes the
  /// runner pick up work *during* an operation, which is the race the whole
  /// design is about.
  var onProbe: (@Sendable () -> Void)?

  func set(_ next: RunnerState) {
    lock.lock()
    state = next
    lock.unlock()
  }

  var probeCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return probes
  }

  var probe: @Sendable (DiscoveredRunner) -> RunnerState {
    { [self] _ in
      onProbe?()
      lock.lock()
      defer { lock.unlock() }
      probes += 1
      return state
    }
  }

  func names(in folder: String) -> Set<String> {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        atPath: root.appendingPathComponent(folder).path)) ?? []
    return Set(entries)
  }

  @discardableResult
  func writeLog(_ name: String, bytes: Int, ageInDays: Double) throws -> URL {
    let url = root.appendingPathComponent("_diag/\(name)")
    try Data(repeating: UInt8(ascii: "x"), count: bytes).write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-ageInDays * 24 * 3600)],
      ofItemAtPath: url.path)
    return url
  }
}

@MainActor
private func model(
  _ sandbox: HousekeepingSandbox, confirmation: FakeConfirmation,
  retention: DiagnosticsRetention = .standard,
  commands: any CommandRunning = ProcessCommandRunner()
) -> HousekeepingModel {
  HousekeepingModel(
    usage: DiskUsage(commandRunner: commands), confirmation: confirmation,
    probe: sandbox.probe, retention: retention)
}

/// Runs the real command and notes which dispatch queue it was run from.
///
/// `du` walks every file the runner owns, so where it is launched from is as
/// much a part of the contract as what it measures.
private struct QueueNotingCommands: CommandRunning {
  let log: QueueLog

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    log.note()
    return try ProcessCommandRunner().run(
      executable, arguments, workingDirectory: workingDirectory)
  }
}

// MARK: - Measuring

@MainActor
@Test func measuringReadsTheRealDirectoryAndKeepsWhenItDidIt() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = model(sandbox, confirmation: FakeConfirmation())

  subject.measure(sandbox.runner)
  await subject.quiesce()

  let measurement = try #require(subject.measurement(for: sandbox.runner))
  let report = try #require(measurement.report)
  #expect(report.bytes(of: .toolCache) >= 4096)
  #expect(report.bytes(of: .checkout) >= 0)
  #expect(!subject.isWorking(on: sandbox.runner))
  // Measuring is a read. It must not cost a `launchctl` and a call to GitHub.
  #expect(sandbox.probeCount == 0)
}

@MainActor
@Test func aRunnerThatLeavesTheMachineTakesItsMeasurementWithIt() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.keepOnly(["actions.runner.somewhere.else"])
  #expect(subject.measurement(for: sandbox.runner) == nil)
}

// MARK: - Deleting

@MainActor
@Test func nothingIsDeletedWithoutSomebodySayingYes() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let confirmation = FakeConfirmation()
  confirmation.answer = false
  let subject = model(sandbox, confirmation: confirmation)
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(confirmation.prompts.count == 1)
  #expect(sandbox.names(in: "_work").contains("_tool"))
  // And the check that would have preceded the deletion was never spent.
  #expect(sandbox.probeCount == 0)
}

@MainActor
@Test func sayingYesTakesTheCacheAndLeavesTheCheckout() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(sandbox.names(in: "_work") == ["_actions", "nest-rules-app"])
  #expect(subject.notice == nil)
  // The numbers on screen described a directory that is no longer there.
  #expect(subject.measurement(for: sandbox.runner)?.report?.bytes(of: .toolCache) == 0)
}

@MainActor
@Test func aRunnerThatPicksUpAJobAfterTheClickKeepsItsCache() async throws {
  // The race the whole unit is about. The menu was drawn over an idle runner,
  // the user agreed, and by the time the deletion runs GitHub has handed it a
  // build. Nothing may go.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()
  sandbox.set(.busy)

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(sandbox.names(in: "_work").contains("_tool"))
  #expect(subject.notice == L10n.cleanupRefused("build-mac"))
  // Said out loud rather than swallowed: the user asked for something, agreed
  // to it, and did not get it.
  #expect(subject.notice != nil)
}

@MainActor
@Test func aRunnerTheMenuAlreadyKnowsIsBusyIsNotEvenAskedAbout() async throws {
  // Two gates, and this is the outer one. A dialogue about deleting the cache
  // of a runner that is mid-build is a dialogue that should never open.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let confirmation = FakeConfirmation()
  let subject = model(sandbox, confirmation: confirmation)
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.busy), of: sandbox))
  await subject.quiesce()

  #expect(confirmation.prompts.isEmpty)
  #expect(sandbox.names(in: "_work").contains("_tool"))
}

@MainActor
@Test func theConfirmationTheUserSeesIsTheOneAboutThisRunnersDirectory() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let confirmation = FakeConfirmation()
  let subject = model(sandbox, confirmation: confirmation)
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  let prompt = try #require(confirmation.prompts.first)
  #expect(prompt.title.contains(sandbox.root.appendingPathComponent("_work/_tool").path))
  #expect(prompt.message.contains("build-mac"))
}

@MainActor
@Test func nothingIsOfferedForDeletionUntilItHasBeenMeasured() async throws {
  // The size in the dialogue comes from the measurement, so acting without one
  // would mean a confirmation that could not say what it frees.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let confirmation = FakeConfirmation()
  let subject = model(sandbox, confirmation: confirmation)

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(confirmation.prompts.isEmpty)
  #expect(sandbox.names(in: "_work").contains("_tool"))
}

// MARK: - Sweeping the logs

@MainActor
@Test func sweepingTakesTheOldLogsAndNeverTheActiveOne() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.writeLog(
    "Worker_20260101-000000-utc.log", bytes: 8192, ageInDays: 30)
  let active = try sandbox.writeLog(
    "Runner_20260805-000000-utc.log", bytes: 64, ageInDays: 0)
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.trimLogs, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(!FileManager.default.fileExists(atPath: old.path))
  #expect(FileManager.default.fileExists(atPath: active.path))
}

@MainActor
@Test func sweepingIsRefusedForARunnerThatPickedUpWorkToo() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.writeLog(
    "Worker_20260101-000000-utc.log", bytes: 8192, ageInDays: 30)
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()
  sandbox.set(.busy)

  subject.perform(.trimLogs, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(FileManager.default.fileExists(atPath: old.path))
  #expect(subject.notice == L10n.cleanupRefused("build-mac"))
}

@MainActor
@Test func aBusyRunnerIsNotEvenAskedAboutItsLogsEither() async throws {
  // The sweep goes through the same gate as the deletions. It is the gentler of
  // the two — the runner only ever appends to the log it has open, and that one
  // is never in a plan — but a rule with an exception in it is a rule somebody
  // has to remember, and this app deletes nothing while a runner has work.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.writeLog(
    "Worker_20260101-000000-utc.log", bytes: 8192, ageInDays: 30)
  let confirmation = FakeConfirmation()
  let subject = model(sandbox, confirmation: confirmation)
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.trimLogs, on: snapshot(display: .resolved(.busy), of: sandbox))
  await subject.quiesce()

  #expect(confirmation.prompts.isEmpty)
  #expect(FileManager.default.fileExists(atPath: old.path))
}

// MARK: - Where the blocking happens

@MainActor
@Test func neitherMeasuringNorDeletingBlocksAPoolThatMattersEither() async throws {
  // `du` walks every file the runner owns and the check is `launchctl` plus a
  // call to GitHub. Both park a thread, and the cooperative pool behind every
  // `Task` has one per core and runs the main actor's work too — so "off the
  // main thread" is not the condition. The queue's label is what tells the two
  // pools apart.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let queues = QueueLog()
  sandbox.onProbe = { queues.note() }
  let subject = model(
    sandbox, confirmation: FakeConfirmation(),
    commands: QueueNotingCommands(log: queues))
  subject.measure(sandbox.runner)
  await subject.quiesce()
  // The measurement's own `du`, before anything has been deleted: it is the
  // half that walks a couple of hundred thousand files.
  #expect(!queues.seen.isEmpty)

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(queues.seen.count >= 2)
  for queue in queues.seen {
    #expect(!queue.contains("main"))
    #expect(queue.contains("com.apple.root"))
  }
}

/// Which dispatch queue something ran on, recorded from whatever thread it was.
private final class QueueLog: @unchecked Sendable {
  private let lock = NSLock()
  private var queues: [String] = []

  var seen: [String] {
    lock.lock()
    defer { lock.unlock() }
    return queues
  }

  func note() {
    let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
    lock.lock()
    queues.append(queue)
    lock.unlock()
  }
}

/// The snapshot the menu would have been drawn from for this sandbox's runner.
private func snapshot(
  display: DisplayState, of sandbox: HousekeepingSandbox
) -> RunnerSnapshot {
  RunnerSnapshot(runner: sandbox.runner, display: display)
}
