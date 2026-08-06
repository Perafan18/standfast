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

  let name: String

  init(name: String = "build-mac") throws {
    self.name = name
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
      label: "actions.runner.acme-widget.\(name)", directory: root, agentId: 7,
      agentName: name, scope: .repository(owner: "acme", name: "widget"))
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
  commands: any CommandRunning = ProcessCommandRunner(),
  clock: @escaping @Sendable () -> Date = Date.init
) -> HousekeepingModel {
  HousekeepingModel(
    usage: DiskUsage(commandRunner: commands), confirmation: confirmation,
    probe: sandbox.probe, retention: retention, clock: clock)
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
@Test func theMeasureButtonGoesThroughTheOneEntryPointLikeEveryOtherOne() async throws {
  // Every button in the submenu is wired to `perform(_:on:)` and nothing else,
  // and this is the only one whose route through it no test walked — so the
  // case could be deleted outright and the suite stayed green. A dead Measure
  // turns the whole feature off silently: with no measurement, the section
  // offers no delete buttons at all.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let clock = TestClock()
  let subject = model(sandbox, confirmation: FakeConfirmation(), clock: clock.read)

  subject.perform(.measure, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  let measurement = try #require(subject.measurement(for: sandbox.runner))
  #expect(measurement.report?.bytes(of: .toolCache) ?? 0 >= 4096)
  // And the moment it was taken is the injected one, not `Date()`. That line —
  // "Measured 4m ago" — is what makes reading on demand honest rather than
  // lazy, and it is the only thing in this menu nothing refreshes.
  #expect(measurement.readAt == clock.start)
}

@MainActor
@Test func everyButtonInTheSubmenuIsSomethingThisModelActsOn() async throws {
  // The companion to the test above, and the one that survives a fifth button
  // being added. `MaintenanceOffer.Kind` is what `App.swift` hands to
  // `perform`, and `App.swift` is the file no test can read.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  try sandbox.writeLog("Worker_20260101-000000-utc.log", bytes: 8192, ageInDays: 30)
  // Every offer has to have something to act on, or its guard returns before
  // the model does anything and the loop below proves nothing about it.
  try Data(repeating: 0, count: 4096)
    .write(to: sandbox.root.appendingPathComponent("_work/_actions/payload"))
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()

  for kind in MaintenanceOffer.Kind.allCases {
    let before = sandbox.probeCount
    subject.perform(kind, on: snapshot(display: .resolved(.idle), of: sandbox))
    await subject.quiesce()
    // Measuring is a read and costs no probe; everything else deletes, and
    // deleting is gated on one. Either way the call reached something.
    #expect(kind == .measure ? sandbox.probeCount == before : sandbox.probeCount > before)
  }
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
  #expect(subject.notice(for: sandbox.runner) == nil)
  // The numbers on screen described a directory that is no longer there.
  #expect(subject.measurement(for: sandbox.runner)?.report?.bytes(of: .toolCache) == 0)
}

@MainActor
@Test func theGateInFrontOfADeletionIsTheOneThatAsksGitHub() async throws {
  // The wiring, not the resolver — that half has its own tests. This model has
  // a choice of two verdicts and only one of them is safe to delete on, and the
  // difference shows up exactly here: `launchctl` cannot see a runner started
  // by hand with `./run.sh`, so the verdict the *menu* uses says `.stopped`,
  // which this app deletes four gigabytes in. The runner is building.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = HousekeepingModel(
    confirmation: FakeConfirmation(),
    resolver: RunnerStateResolver(
      isServiceRunning: { _ in false },
      github: AlwaysBusyGitHub()))
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(sandbox.names(in: "_work").contains("_tool"))
  #expect(subject.notice(for: sandbox.runner) == L10n.cleanupRefused("build-mac"))
}

/// A GitHub that reports a runner online and working, which is the truth
/// `launchctl` cannot see for a runner nobody started through launchd.
private struct AlwaysBusyGitHub: GitHubClient {
  func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    RemoteStatus(online: true, busy: true)
  }
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
  // Said out loud rather than swallowed: the user asked for something, agreed
  // to it, and did not get it.
  #expect(subject.notice(for: sandbox.runner) == L10n.cleanupRefused("build-mac"))
}

@MainActor
@Test func whatWentWrongIsSaidUnderTheRunnerItWentWrongOn() async throws {
  // The submenu is drawn once per runner, and the model has one report for the
  // whole fleet because only one action runs at a time. Handing that report to
  // every submenu puts "nothing was deleted: build-mac picked up work" under
  // the other runner's Maintenance menu — a sentence about the wrong machine,
  // on exactly the two-runner Mac this app is built for.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = model(sandbox, confirmation: FakeConfirmation())
  subject.measure(sandbox.runner)
  await subject.quiesce()
  sandbox.set(.busy)

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(subject.notice(for: sandbox.runner) != nil)
  #expect(subject.notice(for: otherRunner) == nil)
}

/// A second runner on the same Mac, which is what this app is for. It owns no
/// directory: nothing here reads one, and giving it a real one would be a
/// second tree for a test about a string.
private let otherRunner = DiscoveredRunner(
  label: "actions.runner.acme-widget.build-intel", directory: URL(fileURLWithPath: "/"),
  agentId: 8, agentName: "build-intel",
  scope: .repository(owner: "acme", name: "widget"))

@MainActor
@Test func oneRunnersRefusalIsNotLostToAnotherRunnersSuccess() async throws {
  // Two runners can be acting at once — `working` is indexed by runner, and
  // clearing four gigabytes takes long enough to go and clear the other one's
  // while it runs. With one report for the whole model, whichever finished last
  // wrote over the other, and what it wrote over could be the one outcome that
  // has to be said out loud: the user asked for something, agreed to it, and
  // did not get it.
  let quick = try HousekeepingSandbox()
  let slow = try HousekeepingSandbox(name: "build-intel")
  defer {
    quick.cleanUp()
    slow.cleanUp()
  }
  let probes = SlowerForTheSecondRunner(refusing: quick.runner.label)
  let subject = HousekeepingModel(
    confirmation: FakeConfirmation(), probe: probes.probe)
  subject.measure(quick.runner)
  subject.measure(slow.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: quick))
  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: slow))
  await subject.quiesce()

  #expect(quick.names(in: "_work").contains("_tool"))
  #expect(subject.notice(for: quick.runner) == L10n.cleanupRefused("build-mac"))
  // And the one that worked still says nothing, which is what a success says.
  #expect(subject.notice(for: slow.runner) == nil)
}

/// Refuses one runner immediately and lets the other through after a pause, so
/// the second action is the one that finishes last.
private struct SlowerForTheSecondRunner: Sendable {
  let refusing: String

  var probe: @Sendable (DiscoveredRunner) -> RunnerState {
    { [refusing] runner in
      guard runner.label != refusing else { return .busy }
      Thread.sleep(forTimeInterval: 0.3)
      return .idle
    }
  }
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

@MainActor
@Test func anEmptyCacheOpensNoDialogueAboutFreeingNothing() async throws {
  // The menu already declines to draw the button; this is the gate behind it.
  // `_work/_actions` exists here and is empty, which is what a runner that has
  // only ever run a workflow of `run:` steps looks like — so the size in the
  // confirmation would be zero, and agreeing to it would free zero.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let confirmation = FakeConfirmation()
  let subject = model(sandbox, confirmation: confirmation)
  subject.measure(sandbox.runner)
  await subject.quiesce()
  #expect(subject.measurement(for: sandbox.runner)?.report?.bytes(of: .actionCache) == 0)

  subject.perform(.cleanActionCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(confirmation.prompts.isEmpty)
  #expect(sandbox.probeCount == 0)
}

@MainActor
@Test func aSecondMeasurementIsNotStartedOnTopOfTheFirst() async throws {
  // Both would walk the same couple of hundred thousand files, and whichever
  // finished last would be the one on screen — so a slow first press could
  // overwrite the answer a later one had already produced.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let queues = QueueLog()
  let subject = model(
    sandbox, confirmation: FakeConfirmation(),
    commands: QueueNotingCommands(log: queues))

  subject.measure(sandbox.runner)
  #expect(subject.isWorking(on: sandbox.runner))
  subject.measure(sandbox.runner)
  await subject.quiesce()

  // One `du`, not two. Counted through the command seam rather than off the
  // report, which looks identical either way.
  #expect(queues.seen.count == 1)
}

@MainActor
@Test func aDirectoryThatCouldNotBeDeletedIsNamedInTheComplaint() async throws {
  // By the time anything can fail, what failed is the filesystem saying no —
  // and the fix is a permission on one directory. Naming the runner's root
  // instead would point the user at the wrong one of the several inside it.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = HousekeepingModel(
    usage: DiskUsage(), housekeeper: Housekeeper(files: RefusingFileOperations()),
    confirmation: FakeConfirmation(), probe: sandbox.probe)
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  // `_work`, because with nothing writable at all the first thing to fail is
  // making the folder the cache is moved into.
  #expect(
    subject.notice(for: sandbox.runner)
      == L10n.cleanupFailed(
        PathText.abbreviated(sandbox.root.appendingPathComponent("_work"))))
}

@MainActor
@Test func theComplaintNamesWhereTheBytesActuallyAreAfterAHalfDoneDelete() async throws {
  // The rename worked and the delete behind it did not, so `_work/_tool` — the
  // directory the user agreed to and the one this used to name — no longer
  // exists. Sending them to fix a permission on a path that is not there is
  // worse than saying nothing; where the gigabytes are is the grave.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let subject = HousekeepingModel(
    usage: DiskUsage(),
    housekeeper: Housekeeper(files: MovingButNotDeletingOperations()),
    confirmation: FakeConfirmation(), probe: sandbox.probe)
  subject.measure(sandbox.runner)
  await subject.quiesce()

  subject.perform(.cleanToolCache, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  let grave = sandbox.root.appendingPathComponent("_work/\(Housekeeper.trashFolder)")
  #expect(
    subject.notice(for: sandbox.runner)
      == L10n.cleanupFailed(PathText.abbreviated(grave)))
  #expect(!sandbox.names(in: "_work").contains("_tool"))
}

/// A filesystem that says no to everything, which is what a directory this app
/// cannot write to looks like from here.
private struct RefusingFileOperations: DestructiveFileOperations {
  struct Refusal: Error {}
  func createDirectory(at url: URL) throws { throw Refusal() }
  func move(_ url: URL, to destination: URL) throws { throw Refusal() }
  func remove(_ url: URL) throws { throw Refusal() }
}

/// Renames for real and refuses to delete: a directory holding one file this
/// app cannot unlink, which is what a step running `sudo` leaves behind.
private struct MovingButNotDeletingOperations: DestructiveFileOperations {
  struct Refusal: Error {}
  func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  func move(_ url: URL, to destination: URL) throws {
    try FileManager.default.moveItem(at: url, to: destination)
  }
  func remove(_ url: URL) throws { throw Refusal() }
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
@Test func theRetentionThisModelWasGivenIsTheOneBothHalvesUse() async throws {
  // Both halves: the measurement that draws the plan the dialogue names, and
  // the sweep that decides what actually leaves. A log two days old is kept by
  // `.standard`, which holds a week — so either half quietly falling back to it
  // leaves this file exactly where it was.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  try sandbox.writeLog("Runner_20260805-000000-utc.log", bytes: 64, ageInDays: 0)
  let old = try sandbox.writeLog(
    "Worker_20260803-000000-utc.log", bytes: 8192, ageInDays: 2)
  let subject = model(
    sandbox, confirmation: FakeConfirmation(),
    retention: DiagnosticsRetention(keepFor: 24 * 3600, listenerLogsKept: 1))
  subject.measure(sandbox.runner)
  await subject.quiesce()
  #expect(subject.measurement(for: sandbox.runner)?.report?.rotation.count == 1)

  subject.perform(.trimLogs, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(!FileManager.default.fileExists(atPath: old.path))
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
  #expect(subject.notice(for: sandbox.runner) == L10n.cleanupRefused("build-mac"))
}

@MainActor
@Test func aPartiallyFailedSweepRemeasuresAndDoesNotClaimNothingWasDeleted() async throws {
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let first = try sandbox.writeLog(
    "Worker_20260101-000000-utc.log", bytes: 8192, ageInDays: 40)
  let second = try sandbox.writeLog(
    "Worker_20260201-000000-utc.log", bytes: 8192, ageInDays: 30)
  let clock = TestClock()
  let subject = HousekeepingModel(
    usage: DiskUsage(),
    housekeeper: Housekeeper(files: RemovingOneThenRefusingOperations()),
    confirmation: FakeConfirmation(), probe: sandbox.probe, clock: clock.read)
  subject.measure(sandbox.runner)
  await subject.quiesce()
  let before = try #require(subject.measurement(for: sandbox.runner))
  #expect(before.report?.rotation.count == 2)

  clock.advance(60)
  subject.perform(.trimLogs, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(!FileManager.default.fileExists(atPath: first.path))
  #expect(FileManager.default.fileExists(atPath: second.path))
  let after = try #require(subject.measurement(for: sandbox.runner))
  #expect(after.readAt > before.readAt)
  #expect(after.report?.rotation.count == 1)
  let path = PathText.abbreviated(sandbox.root.appendingPathComponent("_diag"))
  let notice = try #require(subject.notice(for: sandbox.runner))
  #expect(notice != L10n.cleanupFailed(path))
  #expect(notice.contains(path))
}

private final class RemovingOneThenRefusingOperations:
  DestructiveFileOperations, @unchecked Sendable
{
  private struct Refusal: Error {}
  private let lock = NSLock()
  private var removalCount = 0

  func createDirectory(at url: URL) throws {}
  func move(_ url: URL, to destination: URL) throws {}

  func remove(_ url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    guard removalCount == 0 else { throw Refusal() }
    removalCount += 1
    try FileManager.default.removeItem(at: url)
  }
}

@MainActor
@Test func aSweepTakesNoMoreThanTheNumberInTheDialogue() async throws {
  // Nothing expires a measurement — `du` is far too expensive to run on a
  // timer, which is why the menu says how old the number is instead — so the
  // plan behind the confirmation can be any age at all, while the sweep decides
  // what leaves against the clock at the moment of the click. On a runner that
  // makes ten worker logs a day, a fortnight between the two is a hundred and
  // forty files the user never agreed to.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  try sandbox.writeLog("Runner_20260805-000000-utc.log", bytes: 64, ageInDays: 0)
  for day in 1...30 {
    try sandbox.writeLog(
      "Worker_2026\(String(format: "%04d", day))-000000-utc.log", bytes: 1024,
      ageInDays: Double(day))
  }
  let clock = TestClock()
  let subject = model(sandbox, confirmation: FakeConfirmation(), clock: clock.read)
  subject.measure(sandbox.runner)
  await subject.quiesce()
  let agreed = try #require(subject.measurement(for: sandbox.runner)?.report?.rotation)
  let survivors = sandbox.names(in: "_diag").subtracting(
    agreed.doomed.map(\.lastPathComponent))

  clock.advance(14 * 24 * 3600)
  subject.perform(.trimLogs, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  // Exactly the set that was agreed to, and every other file still there —
  // including the ones a fortnight of drift has since aged past the week.
  #expect(sandbox.names(in: "_diag") == survivors)
}

@MainActor
@Test func aSweepStillRefusesAFileThatHasBecomeTheActiveLog() async throws {
  // The other direction, and why the re-plan cannot simply be dropped in favour
  // of the agreed one. What the user said yes to is a ceiling and never a
  // floor: a listener that rotated between the measurement and the click leaves
  // the old plan naming a file the runner now has open.
  let sandbox = try HousekeepingSandbox()
  defer { sandbox.cleanUp() }
  let willBecomeActive = try sandbox.writeLog(
    "Runner_20260101-000000-utc.log", bytes: 64, ageInDays: 30)
  let newer = try sandbox.writeLog(
    "Runner_20260805-000000-utc.log", bytes: 64, ageInDays: 30)
  // One listener log kept rather than the standard twenty-five, so that two
  // files are enough to have one of them doomed.
  let subject = model(
    sandbox, confirmation: FakeConfirmation(),
    retention: DiagnosticsRetention(keepFor: 7 * 24 * 3600, listenerLogsKept: 1))
  subject.measure(sandbox.runner)
  await subject.quiesce()
  let agreed = try #require(subject.measurement(for: sandbox.runner)?.report?.rotation)
  #expect(agreed.doomed.map(\.lastPathComponent).contains("Runner_20260101-000000-utc.log"))

  // The newest log goes: a `_diag` cleared by hand, or a listener log the user
  // deleted. The oldest is now the one being appended to.
  try FileManager.default.removeItem(at: newer)
  subject.perform(.trimLogs, on: snapshot(display: .resolved(.idle), of: sandbox))
  await subject.quiesce()

  #expect(FileManager.default.fileExists(atPath: willBecomeActive.path))
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
    // The suffix and not `contains("com.apple.root")`, which is the predicate
    // this used to carry and which cannot fail: the cooperative pool is called
    // `com.apple.root.default-qos.cooperative`, so it satisfied the assertion
    // as happily as the global queue did. Every hop this file is about could be
    // moved onto the pool it exists to stay off, and nothing would have said so.
    #expect(!queue.hasSuffix(".cooperative"))
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
