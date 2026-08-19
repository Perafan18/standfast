import Foundation
import RunnerKit

/// A throwaway machine: a LaunchAgents directory, one runner directory with the
/// `.runner` and `svc.sh` a real installation leaves behind, and controllable
/// answers from `launchctl` and GitHub.
///
/// Discovery reads the real filesystem, so the files have to exist. Everything
/// past that is injected.
final class FleetSandbox: @unchecked Sendable {
  let root: URL
  private let lock = NSLock()
  private var running: Bool?
  private var remote: Result<RemoteStatus, GitHubError>
  private var scans = 0
  private var probes = 0
  private var nextProbeBarrier: BlockingProbe?
  private var nextDiscoveryBarrier: BlockingProbe?
  private var nextRemoteBarrier: BlockingProbe?
  private var nextReleaseBarrier: BlockingReleaseCheck?
  private var discoveryFailure: DiscoveryFailure?
  private var queues: [String] = []
  private var discoveryQueues: [String] = []
  /// Held for the duration of every GitHub call, so a test can make a scan
  /// slow enough to still be running when the next one is asked for.
  private var delay: TimeInterval = 0
  private var latest: Result<RunnerVersion, GitHubError> = .success(
    RunnerVersion(2, 336, 0))
  private var releaseChecks = 0
  private var releaseQueues: [String] = []
  private var versionQueues: [String] = []

  init(
    serviceRunning: Bool = false,
    remote: RemoteStatus = .init(online: true, busy: false)
  ) throws {
    self.running = serviceRunning
    self.remote = .success(remote)
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fleet-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: launchAgents, withIntermediateDirectories: true)
  }

  /// Which dispatch queue the caller is on. The label is what tells the two
  /// pools apart: `Thread.isMainThread` cannot, because a nonisolated `async`
  /// function called from the main actor has already left the main thread — for
  /// the cooperative pool, which is the one place a blocking call must not go.
  static func queueLabel() -> String {
    String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
  }

  var launchAgents: URL { root.appendingPathComponent("LaunchAgents") }
  func cleanUp() { try? FileManager.default.removeItem(at: root) }

  /// How many times GitHub was asked. Zero for a stopped runner, which the
  /// resolver settles without asking.
  var scanCount: Int { withLock { scans } }
  /// How many times the machine was read at all, stopped runners included.
  var probeCount: Int { withLock { probes } }

  /// The dispatch queue each GitHub call arrived on.
  ///
  /// The label is what tells the two pools apart. `Thread.isMainThread` cannot:
  /// a nonisolated `async` function called from the main actor has already
  /// hopped off the main thread — onto the cooperative pool, which is the one
  /// place a blocking call must never land.
  var queuesUsed: [String] { withLock { queues } }

  /// How many times GitHub was asked what the newest runner is. The number this
  /// app has to keep small: it is a call against the same rate limit as the
  /// status one, about something that changes every few weeks.
  var releaseCheckCount: Int { withLock { releaseChecks } }

  /// The dispatch queue each release check arrived on, to the same standard as
  /// `queuesUsed`. It spawns `gh` and makes a network call, so it belongs off
  /// the cooperative pool for exactly the reasons the status call does.
  var releaseQueuesUsed: [String] { withLock { releaseQueues } }

  /// And where the runner's own version was read from — file I/O off a home
  /// directory that may be on a network volume.
  var versionQueuesUsed: [String] { withLock { versionQueues } }

  /// Never the real reader. This one answers what a test told it to and notes
  /// where it ran, which is the only way that second fact is observable.
  var versions: any RunnerVersionReading { Versions(sandbox: self) }

  private struct Versions: RunnerVersionReading {
    let sandbox: FleetSandbox

    func blockingVersion(inLog log: URL) -> InstalledRunnerVersion {
      sandbox.withLock { sandbox.versionQueues.append(FleetSandbox.queueLabel()) }
      return RunnerVersionReader().blockingVersion(inLog: log)
    }
  }

  func set(latest answer: Result<RunnerVersion, GitHubError>) {
    withLock { latest = answer }
  }

  /// Never the real client. `GHCommandLineClient` would spawn `gh` and make a
  /// network call, from every test that builds a model.
  var releases: any RunnerReleaseChecking { Releases(sandbox: self) }

  private struct Releases: RunnerReleaseChecking {
    let sandbox: FleetSandbox

    func blockingLatestRunnerRelease() throws -> RunnerVersion {
      typealias Answer = (Result<RunnerVersion, GitHubError>, BlockingReleaseCheck?)
      let answer = sandbox.withLock { () -> Answer in
        sandbox.releaseChecks += 1
        sandbox.releaseQueues.append(FleetSandbox.queueLabel())
        defer { sandbox.nextReleaseBarrier = nil }
        return (sandbox.latest, sandbox.nextReleaseBarrier)
      }
      answer.1?.block()
      return try answer.0.get()
    }
  }

  /// What GitHub has queued, for the tests that care. Nothing by default, so a
  /// sandbox that never mentions a queue behaves as it always did.
  private var queuedAnswer: Result<QueuedWork, GitHubError> = .failure(.noToken)

  func set(queued answer: Result<QueuedWork, GitHubError>) {
    withLock { queuedAnswer = answer }
  }

  /// Not `queues`: that name already means the dispatch queues this sandbox
  /// records, and the two would read as the same thing.
  var queuedWork: any QueuedWorkReading { Queues(sandbox: self) }

  private struct Queues: QueuedWorkReading {
    let sandbox: FleetSandbox

    func blockingQueuedWork(in scope: RunnerScope) throws -> QueuedWork {
      try sandbox.withLock { sandbox.queuedAnswer }.get()
    }
  }

  func set(serviceRunning: Bool?) { withLock { running = serviceRunning } }
  func set(remote answer: Result<RemoteStatus, GitHubError>) {
    withLock { remote = answer }
  }
  func set(delay seconds: TimeInterval) { withLock { delay = seconds } }
  func set(discoveryFailure failure: DiscoveryFailure?) {
    withLock { discoveryFailure = failure }
  }

  /// Pauses the next local service probe before it reads `running`.
  func blockNextProbe() -> BlockingProbe {
    let barrier = BlockingProbe()
    withLock { nextProbeBarrier = barrier }
    return barrier
  }

  /// Pauses the next discovery only after it has read the filesystem result.
  func blockNextDiscoveryAfterReading() -> BlockingProbe {
    let barrier = BlockingProbe()
    withLock { nextDiscoveryBarrier = barrier }
    return barrier
  }

  /// Pauses the next GitHub answer after launchd has already been read.
  func blockNextRemoteAnswer() -> BlockingProbe {
    let barrier = BlockingProbe()
    withLock { nextRemoteBarrier = barrier }
    return barrier
  }

  /// Pauses the next latest-release answer until a test releases it.
  func blockNextReleaseCheck() -> BlockingReleaseCheck {
    let barrier = BlockingReleaseCheck()
    withLock { nextReleaseBarrier = barrier }
    return barrier
  }

  /// A command runner that moves the sandbox's service the way `svc.sh` moves
  /// a real one, so a refresh landing mid-restart sees the service genuinely
  /// down rather than a fixed answer.
  var svcDrivingCommandRunner: RecordingCommandRunner {
    RecordingCommandRunner { [self] verb in set(serviceRunning: verb == "start") }
  }

  /// - Parameters:
  ///   - name: what the runner calls itself, which is what the menu shows.
  ///   - scope: the repository slug it is registered against. Separate from the
  ///     name because they are separate on a real machine: `config.sh` proposes
  ///     the hostname, so one Mac in two repositories is two runners with one
  ///     name — the case the rows have to survive.
  @discardableResult
  func addRunner(
    name: String = "build-mac", scope: String = "acme-widget", agentId: Int = 7,
    withScript: Bool = true
  ) throws -> URL {
    let label = "actions.runner.\(scope).\(name)"
    let directory = root.appendingPathComponent("\(scope).\(name)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    let fields: [String: Any] = [
      "agentId": agentId, "agentName": name, "workFolder": "_work",
      "gitHubUrl": "https://github.com/acme/\(scope)",
    ]
    try JSONSerialization.data(withJSONObject: fields)
      .write(to: directory.appendingPathComponent(".runner"))
    // The controller refuses a directory with no `svc.sh` before it runs
    // anything, so a sandbox without one is how a failing action is staged.
    if withScript {
      try Data("#!/bin/bash\n".utf8).write(to: directory.appendingPathComponent("svc.sh"))
    }
    let plist: [String: Any] = ["Label": label, "WorkingDirectory": directory.path]
    try PropertyListSerialization
      .data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: launchAgents.appendingPathComponent("\(label).plist"))
    return directory
  }

  /// Writes the `_diag` a runner leaves beside itself, with one job in it.
  ///
  /// Verbatim from a real listener log, double timestamp and all. The reader
  /// under this is only ever pointed at fixtures — CI has no runner — so a
  /// fixture that drifts from the real format is the one failure the suite
  /// cannot see.
  ///
  /// - Parameters:
  ///   - finished: nil for a job still running.
  ///   - version: the header a real listener writes before anything else, and
  ///     the only place on disk that says which runner is installed.
  func writeListenerLog(
    in directory: URL, job name: String, startedAt: String, finished: String?,
    result: String = "Succeeded", version: String? = nil
  ) throws {
    let diagnostics = directory.appendingPathComponent("_diag")
    try FileManager.default.createDirectory(
      at: diagnostics, withIntermediateDirectories: true)
    var lines: [String] = []
    if let version { lines.append("[\(startedAt) INFO Listener] Version: \(version)") }
    lines.append(
      "[\(startedAt) INFO Terminal] WRITE LINE: \(startedAt): Running job: \(name)")
    if let finished {
      lines.append(
        "[\(finished) INFO Terminal] WRITE LINE: \(finished): "
          + "Job \(name) completed with result: \(result)")
    }
    try Data((lines.map { $0 + "\n" }.joined()).utf8)
      .write(to: diagnostics.appendingPathComponent("Runner_20260805-000000-utc.log"))
  }

  /// Adds one more job to the log the listener is already writing to, the way a
  /// real one does — appended, so the reader's cached offset still means
  /// something and the delta is the only thing read.
  func appendJob(
    in directory: URL, job name: String, startedAt: String, finished: String?,
    result: String = "Succeeded"
  ) throws {
    let log = directory.appendingPathComponent(
      "_diag/Runner_20260805-000000-utc.log")
    var lines = [
      "[\(startedAt) INFO Terminal] WRITE LINE: \(startedAt): Running job: \(name)"
    ]
    if let finished {
      lines.append(
        "[\(finished) INFO Terminal] WRITE LINE: \(finished): "
          + "Job \(name) completed with result: \(result)")
    }
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((lines.map { $0 + "\n" }.joined()).utf8))
  }

  /// A log holding several successful runs of one job and one still going, all
  /// placed against the real clock.
  ///
  /// Relative to now on purpose: elapsed time is measured from when the machine
  /// was read, and the model under test reads the real clock. A fixed timestamp
  /// would make "twenty minutes in" mean something different every day.
  ///
  /// - Parameters:
  ///   - each: how long every finished run took, which is what the estimate is
  ///     built from.
  ///   - runningFor: how long the unfinished one has been going.
  func writeSlowRun(
    in directory: URL, job name: String, finishedRuns: Int, each duration: TimeInterval,
    runningFor: TimeInterval
  ) throws {
    let diagnostics = directory.appendingPathComponent("_diag")
    try FileManager.default.createDirectory(
      at: diagnostics, withIntermediateDirectories: true)
    let now = Date()
    var lines: [String] = []
    for run in 0..<finishedRuns {
      // Oldest first, an hour apart, all of them well before the running one.
      let started = now.addingTimeInterval(
        -runningFor - Double(finishedRuns - run) * 3600)
      let finished = started.addingTimeInterval(duration)
      lines.append(
        "[\(Self.stamp(started)) INFO Terminal] WRITE LINE: "
          + "\(Self.stamp(started)): Running job: \(name)")
      lines.append(
        "[\(Self.stamp(finished)) INFO Terminal] WRITE LINE: \(Self.stamp(finished)): "
          + "Job \(name) completed with result: Succeeded")
    }
    let started = now.addingTimeInterval(-runningFor)
    lines.append(
      "[\(Self.stamp(started)) INFO Terminal] WRITE LINE: "
        + "\(Self.stamp(started)): Running job: \(name)")
    try Data((lines.map { $0 + "\n" }.joined()).utf8)
      .write(to: diagnostics.appendingPathComponent("Runner_20260805-000000-utc.log"))
  }

  /// `2026-08-05 20:36:14Z`, which is what the runner writes and what the parser
  /// reads. Built by hand rather than with a `DateFormatter`, so the host's
  /// locale and calendar stay out of it.
  private static func stamp(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d-%02d-%02d %02d:%02d:%02dZ", parts.year ?? 0, parts.month ?? 0,
      parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
  }

  /// Replaces the listener log's contents with noise of exactly the same
  /// length.
  ///
  /// How a test asks whether the log was read again. A reader carried forward
  /// between scans has consumed these bytes already and must not look at them;
  /// one that was thrown away and rebuilt reads the file from scratch and finds
  /// nothing in it.
  func garbleListenerLog(in directory: URL) throws {
    let log = directory.appendingPathComponent("_diag/Runner_20260805-000000-utc.log")
    let size = try FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int
    let noise = String(repeating: "x", count: (size ?? 1) - 1) + "\n"
    try Data(noise.utf8).write(to: log)
  }

  /// Discovery, plus a note of where it was called from. Reading the whole
  /// LaunchAgents directory and a file per runner is filesystem work, and on a
  /// networked home directory it is not the microsecond it is here.
  /// Takes a runner off the machine the way an uninstall does: launchd stops
  /// advertising it, and the directory it pointed at may well stay behind.
  func removeRunner(name: String = "build-mac", scope: String = "acme-widget") throws {
    let label = "actions.runner.\(scope).\(name)"
    try FileManager.default.removeItem(
      at: launchAgents.appendingPathComponent("\(label).plist"))
  }

  var discover: @Sendable () -> DiscoveryResult {
    { [self] in
      let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
      let (failure, barrier) = withLock {
        discoveryQueues.append(queue)
        defer { nextDiscoveryBarrier = nil }
        return (discoveryFailure, nextDiscoveryBarrier)
      }
      let found =
        if let failure {
          DiscoveryResult(runners: [], failure: failure)
        } else {
          RunnerDiscovery(launchAgentsDirectory: launchAgents).discover()
        }
      barrier?.block()
      return found
    }
  }

  var discoveryQueuesUsed: [String] { withLock { discoveryQueues } }

  var resolver: RunnerStateResolver {
    RunnerStateResolver(
      isServiceRunning: { [self] _ in
        let barrier = withLock {
          probes += 1
          defer { nextProbeBarrier = nil }
          return nextProbeBarrier
        }
        barrier?.block()
        return withLock { running }
      },
      github: Client(sandbox: self))
  }

  /// Answers whatever the sandbox is currently set to, and counts the asking.
  private struct Client: GitHubClient {
    let sandbox: FleetSandbox

    func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
      let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
      let (answer, pause, barrier) = sandbox.withLock {
        sandbox.scans += 1
        sandbox.queues.append(queue)
        defer { sandbox.nextRemoteBarrier = nil }
        return (sandbox.remote, sandbox.delay, sandbox.nextRemoteBarrier)
      }
      if pause > 0 { Thread.sleep(forTimeInterval: pause) }
      barrier?.block()
      return try answer.get()
    }
  }

  fileprivate func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

/// A `svc.sh` the command runner gave up on, having first let it do its work.
///
/// What a real 30-second timeout looks like from here: the process was killed
/// at the deadline, and by then it had usually already loaded the agent — a
/// `launchctl load` and a little shell do not take half a minute unless the
/// machine is struggling, which is also when a runner takes longest to
/// register and so needs the settling window most.
final class TimingOutCommandRunner: CommandRunning, @unchecked Sendable {
  private let onVerb: @Sendable (String) -> Void

  init(onVerb: @escaping @Sendable (String) -> Void = { _ in }) { self.onVerb = onVerb }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    if let verb = arguments.last { onVerb(verb) }
    throw CommandError.timedOut(executable: executable)
  }
}

/// A `svc.sh` that definitely did not complete, for distinguishing a known
/// failure from a timeout whose effects cannot be known.
final class FailingCommandRunner: CommandRunning, @unchecked Sendable {
  private let onVerb: @Sendable (String) -> Void

  init(onVerb: @escaping @Sendable (String) -> Void = { _ in }) { self.onVerb = onVerb }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    if let verb = arguments.last { onVerb(verb) }
    throw DeliberateCommandFailure.failed
  }

  private enum DeliberateCommandFailure: Error { case failed }
}

/// Succeeds until one selected svc verb, for locating which half of Restart
/// failed without replacing the controller's real stop-then-start sequence.
final class FailingVerbCommandRunner: CommandRunning, @unchecked Sendable {
  private let failingVerb: String
  private let onVerb: @Sendable (String) -> Void
  private let lock = NSLock()
  private var seen: [String] = []

  init(
    failingVerb: String, onVerb: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.failingVerb = failingVerb
    self.onVerb = onVerb
  }

  var invocations: [String] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    let verb = arguments.last ?? ""
    lock.lock()
    seen.append(verb)
    lock.unlock()
    onVerb(verb)
    if verb == failingVerb { throw DeliberateCommandFailure.failed }
    return CommandResult(standardOutput: "", exitCode: 0)
  }

  private enum DeliberateCommandFailure: Error { case failed }
}

/// Succeeds until one selected svc verb times out, so Restart tests can tell a
/// timeout in Stop from a timeout after Stop completed and Start was attempted.
final class TimingOutVerbCommandRunner: CommandRunning, @unchecked Sendable {
  private let timingOutVerb: String
  private let onVerb: @Sendable (String) -> Void

  init(
    timingOutVerb: String, onVerb: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.timingOutVerb = timingOutVerb
    self.onVerb = onVerb
  }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    let verb = arguments.last ?? ""
    onVerb(verb)
    if verb == timingOutVerb { throw CommandError.timedOut(executable: executable) }
    return CommandResult(standardOutput: "", exitCode: 0)
  }
}

enum SecondCommandOutcome {
  case definiteFailure
  case timeout
}

/// Lets one Stop complete, then fails the next service command so a test can
/// start a second lifecycle only after the first action released ownership.
final class SecondCommandOutcomeRunner: CommandRunning, @unchecked Sendable {
  private let outcome: SecondCommandOutcome
  private let lock = NSLock()
  private var seen: [String] = []

  init(_ outcome: SecondCommandOutcome) { self.outcome = outcome }

  var invocations: [String] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    let verb = arguments.last ?? ""
    let invocation = lock.withLock {
      seen.append(verb)
      return seen.count
    }
    guard invocation == 2 else {
      return CommandResult(standardOutput: "", exitCode: 0)
    }
    switch outcome {
    case .definiteFailure: throw SecondCommandFailure.failed
    case .timeout: throw CommandError.timedOut(executable: executable)
    }
  }

  private enum SecondCommandFailure: Error { case failed }
}

/// Holds every command at a gate after recording it, so tests can act while a
/// service mutation is definitely still in flight without racing a sleep.
final class BlockingCommandRunner: CommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private let gate = DispatchSemaphore(value: 0)
  private let failureAfterRelease: Bool
  private let onReleaseVerb: @Sendable (String) -> Void
  private var seen: [[String]] = []
  private var completed = 0

  init(
    failureAfterRelease: Bool = false,
    onReleaseVerb: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.failureAfterRelease = failureAfterRelease
    self.onReleaseVerb = onReleaseVerb
  }

  var invocations: [[String]] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func waitForInvocationCount(
    _ count: Int, timeout: Duration = .seconds(1)
  ) async throws {
    try await wait(timeout: timeout) { self.invocations.count >= count }
  }

  func waitForCompletionCount(
    _ count: Int, timeout: Duration = .seconds(1)
  ) async throws {
    try await wait(timeout: timeout) { self.completionCount >= count }
  }

  /// Signals may be issued before a command reaches the gate; the semaphore
  /// keeps them, which lets a test release both the expected and buggy paths.
  func release(_ count: Int = 1) {
    for _ in 0..<count { gate.signal() }
  }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    lock.lock()
    seen.append([executable] + arguments)
    lock.unlock()

    gate.wait()
    if let verb = arguments.last { onReleaseVerb(verb) }
    lock.lock()
    completed += 1
    lock.unlock()
    if failureAfterRelease { throw DeliberateCommandFailure.failed }
    return CommandResult(standardOutput: "", exitCode: 0)
  }

  private var completionCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return completed
  }

  private func wait(
    timeout: Duration, until condition: () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      guard clock.now < deadline else { throw WaitFailure.timedOut }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  private enum WaitFailure: Error { case timedOut }
  private enum DeliberateCommandFailure: Error { case failed }
}

/// A one-shot gate placed immediately before the sandbox reads launchd state.
final class BlockingProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let gate = DispatchSemaphore(value: 0)
  private var hasEntered = false

  func waitUntilEntered(timeout: Duration = .seconds(1)) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !entered {
      guard clock.now < deadline else { throw WaitFailure.timedOut }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  func release() { gate.signal() }

  fileprivate func block() {
    lock.lock()
    hasEntered = true
    lock.unlock()
    gate.wait()
  }

  private var entered: Bool {
    lock.lock()
    defer { lock.unlock() }
    return hasEntered
  }

  private enum WaitFailure: Error { case timedOut }
}

/// A release-check gate whose entry is an event, not a scheduler deadline.
/// The test using it has a generous test-level limit for broken implementations.
final class BlockingReleaseCheck: @unchecked Sendable {
  private let gate = DispatchSemaphore(value: 0)
  private let entry: AsyncStream<Void>
  private let entryContinuation: AsyncStream<Void>.Continuation

  init() {
    let signal = AsyncStream<Void>.makeStream()
    entry = signal.stream
    entryContinuation = signal.continuation
  }

  func waitUntilEntered() async {
    for await _ in entry {
      return
    }
  }

  func release() { gate.signal() }

  fileprivate func block() {
    entryContinuation.yield()
    entryContinuation.finish()
    gate.wait()
  }
}

/// A clock a test moves by hand, for the parts of this model that measure how
/// stale their own answer is.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var now: Date
  private let step: TimeInterval
  /// Where it started, which a test needs to name the instant it expects.
  let start: Date

  /// - Parameter step: how far time moves on each reading. Zero for a clock
  ///   that stands still, which is what most of these tests want; anything else
  ///   makes time pass *during* a scan, which is the only way to tell a stamp
  ///   taken when the machine was read from one taken when the answer landed.
  init(
    _ start: Date = Date(timeIntervalSince1970: 1_785_962_174), step: TimeInterval = 0
  ) {
    self.start = start
    now = start
    self.step = step
  }

  var read: @Sendable () -> Date {
    { [self] in
      lock.lock()
      defer { lock.unlock() }
      let reading = now
      now = now.addingTimeInterval(step)
      return reading
    }
  }

  func advance(_ seconds: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    now = now.addingTimeInterval(seconds)
  }
}

/// Records what `svc.sh` was asked to do and always succeeds, which is what
/// the real one does even when it failed.
final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var seen: [[String]] = []
  private var queues: [String] = []
  private let onVerb: @Sendable (String) -> Void

  init(onVerb: @escaping @Sendable (String) -> Void = { _ in }) { self.onVerb = onVerb }

  var invocations: [[String]] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  /// The dispatch queue each `svc.sh` call arrived on. `svc.sh` blocks for as
  /// long as the command timeout allows, so where it runs is as much a part of
  /// the contract as what it runs.
  var queuesUsed: [String] {
    lock.lock()
    defer { lock.unlock() }
    return queues
  }

  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    let queue = String(validatingCString: __dispatch_queue_get_label(nil)) ?? ""
    lock.lock()
    seen.append([executable] + arguments)
    queues.append(queue)
    lock.unlock()
    if let verb = arguments.last { onVerb(verb) }
    return CommandResult(standardOutput: "", exitCode: 0)
  }
}
