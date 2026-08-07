import Foundation
import RunnerKit
import Testing

@testable import Standfast

@MainActor
private func model(
  _ sandbox: FleetSandbox, commands: any CommandRunning = RecordingCommandRunner(),
  settling: SettlingWindow = SettlingWindow(), settleDelay: TimeInterval = 0,
  probeDelay: TimeInterval = 0, clock: @escaping @Sendable () -> Date = Date.init,
  // Never the real ones. `UNUserNotificationCenter` needs an application bundle
  // and a permission CI cannot grant, and a power assertion would be taken out
  // on whatever machine runs the suite.
  notifications: NotificationSettings? = nil, sleep: SleepGuard? = nil,
  // Nor this one. The real opener hands the URL to the user's browser, so a
  // suite that reaches it buries whoever ran it in tabs pointed at a fixture.
  opener: FakeURLOpener = FakeURLOpener(),
  // No ticker by default: these tests drive every refresh themselves. A test
  // that wants the freshness rule passes an interval long enough that the real
  // ticker cannot fire inside it, and calls `tick()` by hand.
  refreshInterval: TimeInterval? = nil,
  releaseInterval: TimeInterval = 24 * 60 * 60
) -> RunnerFleetModel {
  RunnerFleetModel(
    discover: sandbox.discover, resolver: sandbox.resolver,
    controller: ServiceController(commandRunner: commands, settleDelay: settleDelay),
    settling: settling,
    notifications: notifications
      ?? NotificationSettings(
        delivery: FakeNotificationDelivery(), defaults: scratchDefaults()),
    sleep: sleep
      ?? SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults()),
    // Nor this one. Left at its default it is a real `NSAlert` — a modal window
    // on whatever machine runs the suite — a real `Housekeeper`, which is the
    // only thing in this app that deletes anything, and a real probe spawning
    // `launchctl` and `gh`. Only the read path is reached from here today, and
    // "today" is not a guarantee worth resting a delete on.
    housekeeping: unattendedHousekeeping(),
    // Never the real one, which would spawn `gh` and make a network call from
    // every test in this file.
    versions: sandbox.versions,
    releases: sandbox.releases,
    opener: opener,
    clock: clock, probeDelay: probeDelay, refreshInterval: refreshInterval,
    releaseInterval: releaseInterval)
}

/// A housekeeping model that can neither open a window nor delete a file.
@MainActor
private func unattendedHousekeeping() -> HousekeepingModel {
  HousekeepingModel(
    housekeeper: Housekeeper(files: UntouchableFileOperations()),
    confirmation: RefusingConfirmation(),
    // And a probe that answers without asking the machine, so nothing here can
    // reach `launchctl` or the network by accident.
    probe: { _ in .busy })
}

/// Says no to everything. Nothing in this file is about the delete path, and a
/// dialogue nobody is there to dismiss is a suite that hangs.
@MainActor
private struct RefusingConfirmation: CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> Bool { false }
}

/// A filesystem that does nothing at all, so nothing in this file can remove a
/// directory even if every guard above it were wrong at once.
private struct UntouchableFileOperations: DestructiveFileOperations {
  func createDirectory(at url: URL) throws {}
  func move(_ url: URL, to destination: URL) throws {}
  func remove(_ url: URL) throws {}
}

/// A model whose notifications are all switched on, with the delivery it posts
/// to. Every switch is off on a real install; a test that wants to see anything
/// arrive has to turn them on, which is the behaviour under test everywhere
/// else.
@MainActor
private func listening(
  _ sandbox: FleetSandbox, commands: any CommandRunning = RecordingCommandRunner(),
  settleDelay: TimeInterval = 0, probeDelay: TimeInterval = 0,
  clock: @escaping @Sendable () -> Date = Date.init
) async -> (RunnerFleetModel, FakeNotificationDelivery) {
  let delivery = FakeNotificationDelivery()
  let notifications = NotificationSettings(
    delivery: delivery, defaults: scratchDefaults())
  for kind in NotificationKind.allCases { notifications.setEnabled(kind, true) }
  await notifications.quiesce()
  return (
    model(
      sandbox, commands: commands, settleDelay: settleDelay, probeDelay: probeDelay,
      clock: clock, notifications: notifications),
    delivery
  )
}

@MainActor
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

private struct CouldNotLaunchCommandRunner: CommandRunning {
  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    throw CommandError.couldNotLaunch(
      executable: executable, underlying: NSError(domain: "test", code: 1))
  }
}

// MARK: - Reading the machine

@Test @MainActor func listsWhatIsInstalledWithTheStateOfEachRunner() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "build-mac")
  let fleet = model(box)

  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.runner.displayName) == ["build-mac"])
  #expect(fleet.snapshots.map(\.display) == [.resolved(.idle)])
  #expect(fleet.notice == nil)
}

@Test @MainActor func aMacWithNoRunnersSaysSoRatherThanLookingBroken() async throws {
  let box = try FleetSandbox()
  defer { box.cleanUp() }
  let fleet = model(box)

  await fleet.quiesce()

  #expect(fleet.snapshots.isEmpty)
  #expect(fleet.notice == .noRunnersInstalled)
  #expect(FleetSummary.symbolName(for: []) == FleetSummary.noRunnersSymbolName)
}

@Test @MainActor func refreshesDoNotPileUpOnTopOfASlowScan() async throws {
  // A `gh` call has a 30s ceiling and the ticker comes round every 15s, so an
  // unguarded refresh would start a second scan on top of the first. The
  // requests are coalesced rather than dropped: the one most likely to land
  // during a slow scan is the re-probe after an action.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()
  #expect(box.scanCount == 1)

  box.set(delay: 0.2)
  fleet.refresh()
  fleet.refresh()
  fleet.refresh()
  await fleet.quiesce()

  // One running, one remembered, the third folded into the second.
  #expect(box.scanCount == 3)
}

// MARK: - The ticker, and the loop it used to become

@Test @MainActor func aTickArrivingDuringAScanIsDroppedRatherThanRemembered()
  async throws
{
  // The measured failure: with `gh` slower than the interval, every tick that
  // landed mid-scan left a request pending, so the scan restarted the instant
  // it finished — and again, and again, for as long as the network stayed bad.
  // No pause, an API call per pass, and the radio never asleep, all of it
  // spent exactly when the machine can least afford it.
  //
  // Dropping loses nothing: a tick asks for a fresh reading, and the scan
  // already running is one.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()
  #expect(box.scanCount == 1)

  box.set(delay: 0.2)
  fleet.refresh()
  fleet.tick()
  fleet.tick()
  fleet.tick()
  await fleet.quiesce()

  #expect(box.scanCount == 2)
}

@Test @MainActor func anExplicitRefreshDuringAScanIsStillRemembered() async throws {
  // The other half of the same decision, and why ticks are the only thing
  // dropped. The request most likely to land during a slow scan is the
  // re-probe after an action — the single answer the user is waiting for — and
  // the scan already running read the machine before the action touched it.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()

  box.set(delay: 0.2)
  fleet.refresh()
  fleet.refresh()
  await fleet.quiesce()

  #expect(box.scanCount == 3)
}

@Test @MainActor func aTickIsDroppedWhileTheAnswerOnScreenIsStillFresh() async throws {
  // `readAt` is when the machine was read, not when the answer landed. A scan
  // that overran the interval leaves the very next tick due on arrival, which
  // is the same loop by a slower route.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let fleet = model(box, clock: clock.read, refreshInterval: 15)
  await fleet.quiesce()
  #expect(box.scanCount == 1)

  clock.advance(14)
  fleet.tick()
  await fleet.quiesce()
  #expect(box.scanCount == 1)

  clock.advance(2)
  fleet.tick()
  await fleet.quiesce()
  #expect(box.scanCount == 2)
}

// MARK: - When the machine was last read

@Test @MainActor func theMarkSaysWhenTheScanStartedAndNotWhenItLanded() async throws {
  // The whole reason this line is worth having. A `gh` that hangs for thirty
  // seconds leaves the menu describing a machine from half a minute ago, and a
  // mark taken when the answer arrived would call that fresh — which is exactly
  // the lie the line exists to catch.
  //
  // Time moves on every reading here, so a stamp taken at either end of the
  // scan is a different number.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock(step: 30)
  let fleet = model(box, clock: clock.read)

  await fleet.quiesce()

  #expect(fleet.lastReadAt == clock.start)
  #expect(fleet.lastReadAt != clock.read())
}

@Test @MainActor func theMenuKnowsWhenItLastReadTheMachine() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let fleet = model(box, clock: clock.read)
  #expect(fleet.lastReadAt == nil)

  await fleet.quiesce()
  let first = fleet.lastReadAt
  #expect(first == clock.read())

  clock.advance(60)
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.lastReadAt == clock.read())
  #expect(fleet.lastReadAt != first)
}

// MARK: - What the runner has been building

@Test @MainActor func theJobARunnerIsBuildingReachesTheMenu() async throws {
  // End to end, through the one path that matters: the log on disk, the
  // reader, the snapshot and the row. Nothing here is stubbed but GitHub.
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z", finished: nil)
  let fleet = model(box)

  await fleet.quiesce()

  #expect(fleet.snapshots[0].jobs.running?.name == "testflight")
  #expect(fleet.snapshots[0].row.progress?.contains("testflight") == true)
}

@Test @MainActor func aFinishedJobBecomesHistoryRatherThanProgress() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z")
  let fleet = model(box)

  await fleet.quiesce()

  let row = fleet.snapshots[0].row
  #expect(row.progress == nil)
  #expect(row.recentJobs.map(\.text) == ["testflight — \(L10n.jobSucceeded) (2m 45s)"])
}

@Test @MainActor func theElapsedTimeIsMeasuredFromWhenTheMachineWasRead() async throws {
  // Every number in one row has to describe one moment. Measuring elapsed time
  // against the clock while the state beside it is as it was read half a minute
  // ago leaves the row quietly describing two different machines — and on a
  // slow `gh` the gap is the whole thirty seconds.
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z", finished: nil)
  // Eighty seconds after the job began at global scan start, and moving on
  // every reading. Discovery is dated thirty seconds later for absence, then
  // this runner's own launchd probe another thirty seconds after that. The
  // latter is still the instant a present runner's snapshot represents.
  let clock = TestClock(Date(timeIntervalSince1970: 1_785_962_174 + 80), step: 30)
  let fleet = model(box, clock: clock.read)

  await fleet.quiesce()

  #expect(fleet.snapshots[0].row.progress?.contains(DurationText.precise(140)) == true)
  #expect(fleet.snapshots[0].row.progress?.contains(DurationText.precise(110)) == false)
  #expect(fleet.snapshots[0].row.progress?.contains(DurationText.precise(80)) == false)
}

@Test @MainActor func aRunnerStillInstalledIsNotReReadFromScratchEachTime()
  async throws
{
  // The refresh runs every fifteen seconds for as long as the app is open, and
  // the reader that knows how much of the log it has already consumed lives
  // here — one per runner, carried across scans the way the settling window is.
  // Rebuilding it each time throws that away and re-reads `_diag` on every
  // tick, which is the entire thing it exists to avoid.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z")
  let fleet = model(box)
  await fleet.quiesce()
  #expect(fleet.snapshots[0].jobs.records.count == 1)

  // Bytes it has already consumed, replaced. A reader that kept its place does
  // not look at them again.
  try box.garbleListenerLog(in: directory)
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots[0].jobs.records.map(\.name) == ["testflight"])
}

@Test @MainActor func aRunnerThatLeavesTheMachineTakesItsLogReaderWithIt()
  async throws
{
  // The other half: a reader for a runner that is no longer installed would
  // hold its parsed jobs for as long as the app runs, with nothing left to ever
  // clear it — the same leak the settling window is swept for. Forgetting it
  // also means a reinstalled runner is read from disk rather than from a memory
  // of the machine as it used to be.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z")
  let fleet = model(box)
  await fleet.quiesce()
  #expect(fleet.snapshots[0].jobs.records.count == 1)

  try box.removeRunner()
  fleet.refresh()
  await fleet.quiesce()
  #expect(fleet.snapshots.isEmpty)

  // Reinstalled, with a log that no longer says what it said. Anything still
  // showing `testflight` is showing it from a reader that outlived its runner.
  try box.garbleListenerLog(in: directory)
  try box.addRunner()
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.count == 1)
  #expect(fleet.snapshots[0].jobs.records.isEmpty)
}

@Test @MainActor func aRunnerWithNoDiagnosticsDirectoryStillGetsARow() async throws {
  // A runner started by hand, a `_diag` somebody cleared out, a permissions
  // problem. None of it may cost the row that says whether the runner is up.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)

  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.idle)])
  #expect(fleet.snapshots[0].jobs == .empty)
  #expect(fleet.snapshots[0].row.recentJobs.isEmpty)
}

// MARK: - The settling window, from the outside

@Test @MainActor func aRunnerJustStartedIsNotReportedAsDisconnected() async throws {
  // The process is up the moment `svc.sh start` returns; GitHub takes seconds
  // more to register it. In between the resolver says `.disconnected` — a
  // fault, one second after the user did exactly the right thing.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])

  box.set(serviceRunning: true)
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.starting])
  // And the icon does not raise a warning over it either.
  #expect(
    FleetSummary.symbolName(for: fleet.snapshots.map(\.display))
      == DisplayState.starting.symbolName)
}

@Test @MainActor func aStartThatNeverCameUpStillReportsStopped() async throws {
  // `svc.sh start` exits 0 even when the `launchctl load` under it failed, so
  // the re-probe is the only report a failed start produces. The settling
  // window must not eat it.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
}

@Test @MainActor func stoppingARunnerEndsItsSettlingWindow() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.starting])

  // The service stays up in this sandbox, so what comes back is the same
  // `.disconnected` — this time with nothing covering for it.
  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.disconnected)])
}

@Test @MainActor func restartAlsoGetsTheBenefitOfTheDoubt() async throws {
  // The case that needs it most: `ServiceController.restart` waits 1.5s, which
  // is launchd's requirement and nothing like long enough for a registration,
  // so a restart lands inside the window nearly every time.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.starting])
}

@Test @MainActor func aRunnerThatNeverRegistersIsEventuallyReported() async throws {
  // The benefit of the doubt runs out. A window already past its duration by
  // the time the re-probe lands leaves `.disconnected` showing.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let fleet = model(box, settling: SettlingWindow(duration: 0))
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.disconnected)])
}

@Test @MainActor func aRefreshDuringARestartDoesNotSpendTheWindowEarly() async throws {
  // Why the window opens when the action returns and not when the button is
  // pressed. A restart takes the service down first, and any refresh landing
  // in that gap finds a perfectly real `.stopped` — which is exactly what ends
  // the benefit of the doubt, so a window opened at the click would already be
  // gone by the time the runner started registering.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let fleet = model(box, commands: box.svcDrivingCommandRunner, settleDelay: 0.2)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  try await Task.sleep(for: .milliseconds(50))
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.starting])
}

@Test @MainActor func aRunnerThatLeavesTheMachineTakesItsWindowWithIt() async throws {
  // A settling window is closed by the answer that reads it, so a runner that
  // stops being discovered leaves one behind with nothing left to clear it.
  // Uninstall and reinstall inside the window and the new runner would inherit
  // the old one's benefit of the doubt.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let fleet = model(box)
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.starting])

  try box.removeRunner()
  fleet.refresh()
  await fleet.quiesce()
  #expect(fleet.snapshots.isEmpty)

  try box.addRunner()
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.disconnected)])
}

@Test @MainActor func aScanOlderThanTheClickDoesNotSpendTheWindowItNeverSaw()
  async throws
{
  // Reproduces the sequence a reviewer measured on one real runner, via
  // Restart:
  //
  //   1. the ticker starts a scan; `gh` is slow. What it reads is `.idle`.
  //   2. the user presses Restart. It returns, and the window opens.
  //   3. the old scan lands and applies the `.idle` it read *before the click*.
  //      Not `.disconnected`, so it closes the window.
  //   4. the real re-probe arrives — `.disconnected`, with nothing left to
  //      cover for it — and the menu bar raises a warning triangle over a
  //      restart that is going perfectly well.
  //
  // Every layer is right on its own. The gap is that `apply` used to believe
  // readings older than the window they were closing.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.resolved(.idle)])

  // Step 1: a scan that will take longer than the click does, reading `.idle`.
  box.set(delay: 0.3)
  fleet.refresh()
  // Long enough for that scan to have asked GitHub and be sitting in the pause,
  // so what it carries is the answer from before the restart.
  try await Task.sleep(for: .milliseconds(80))

  // Step 2: the click. From here on the machine answers `.disconnected`, which
  // is what a runner mid-registration looks like.
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  fleet.restart(fleet.snapshots[0].runner)

  // Steps 3 and 4: the stale scan lands, then the re-probe it delayed.
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.starting])
  #expect(
    FleetSummary.symbolName(for: fleet.snapshots.map(\.display))
      == DisplayState.starting.symbolName)
}

// MARK: - Two runners, one name

@Test @MainActor func oneMacInTwoRepositoriesDrawsTwoDistinguishableRows()
  async throws
{
  // The headline case for a multi-runner release, and the one where the menu
  // used to give up: `config.sh` proposes the hostname, so both runners call
  // themselves the same thing and both rows read `mac-mini-m4 — Idle`.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "mac-mini-m4", scope: "widget", agentId: 7)
  try box.addRunner(name: "mac-mini-m4", scope: "gadget", agentId: 8)
  let fleet = model(box)

  await fleet.quiesce()

  let titles = fleet.snapshots.map(\.row.title)
  #expect(titles.count == 2)
  #expect(Set(titles).count == 2)
  #expect(titles.allSatisfy { $0.contains("mac-mini-m4") })
  #expect(titles.contains { $0.contains("acme/widget") })
  #expect(titles.contains { $0.contains("acme/gadget") })
}

@Test @MainActor func aMacWithOneRunnerKeepsTheShortRow() async throws {
  // The other half of the same decision: nothing to disambiguate, nothing
  // added. A menu bar row has very little width to spend.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "mac-mini-m4", scope: "widget")
  let fleet = model(box)

  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.qualifier) == [nil])
  #expect(fleet.snapshots[0].row.title == L10n.runnerRow("mac-mini-m4", L10n.stateIdle))
}

// MARK: - Acting on one runner, not on the machine

@Test @MainActor func oneRunnerAcceptsOnlyOneServiceActionAtATime() async throws {
  // Hold Start inside svc.sh, then press every service button again. All three
  // overlap the same label and therefore belong to the one ignored group.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = BlockingCommandRunner()
  defer { commands.release(10) }
  let fleet = model(box, commands: commands)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.start(runner)
  try await commands.waitForInvocationCount(1)
  fleet.start(runner)
  fleet.stop(runner)
  fleet.restart(runner)
  commands.release(10)
  await fleet.quiesce()

  #expect(commands.invocations.map(\.last) == ["start"])
}

@Test @MainActor func differentRunnersCanActAtTheSameTime() async throws {
  // The first command is still blocked when the second reaches the runner, so
  // this proves the guard is keyed by label rather than fleet-wide.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner(name: "build-mac", scope: "widget")
  try box.addRunner(name: "release-mac", scope: "gadget")
  let commands = BlockingCommandRunner()
  defer { commands.release(10) }
  let fleet = model(box, commands: commands)
  await fleet.quiesce()
  let runners = Dictionary(
    uniqueKeysWithValues: fleet.snapshots.map {
      ($0.runner.displayName, $0.runner)
    })

  fleet.start(runners["build-mac"]!)
  try await commands.waitForInvocationCount(1)
  fleet.stop(runners["release-mac"]!)
  try await commands.waitForInvocationCount(2)
  commands.release(10)
  await fleet.quiesce()

  #expect(Set(commands.invocations.compactMap(\.last)) == ["start", "stop"])
}

@Test @MainActor func openingGitHubIsNotBlockedByAServiceAction() async throws {
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner(scope: "widget")
  let commands = BlockingCommandRunner()
  defer { commands.release(10) }
  let opener = FakeURLOpener()
  let fleet = model(box, commands: commands, opener: opener)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.start(runner)
  try await commands.waitForInvocationCount(1)
  fleet.perform(.openOnGitHub, on: runner)

  #expect(
    opener.urls.map(\.absoluteString) == [
      "https://github.com/acme/widget/settings/actions/runners"
    ])
  commands.release()
  await fleet.quiesce()
}

@Test @MainActor func anActionThatCouldNotRunOpensNoWindow() async throws {
  // Half-uninstalled runner: no `svc.sh`, so Start throws before anything
  // happens. Nothing was started, so nothing is settling, and the state the
  // machine reports is the state to show.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(withScript: false)
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let fleet = model(box)
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.disconnected)])
}

@Test @MainActor func anActionKilledByTheTimeoutStillGetsItsSettlingWindow()
  async throws
{
  // `svc.sh start` is a `launchctl load` and a little shell. When it takes
  // more than the command runner's thirty seconds it is the machine that is
  // struggling, and the load has usually already happened — which is exactly
  // when a runner needs longest to register, and so needs the window most.
  // Treating the timeout as a failure raised the warning triangle over a start
  // that had gone through.
  //
  // Not the same as an action that could not run at all: the test below stages
  // a missing `svc.sh`, where nothing was launched, and gets no window.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  // The command is killed at the deadline having already started the service,
  // and GitHub has not yet heard of it — which is `.disconnected`, the state
  // the window exists to hold back.
  let commands = TimingOutCommandRunner { [box] _ in box.set(serviceRunning: true) }
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let fleet = model(box, commands: commands)
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.starting])
  #expect(fleet.snapshots.map(\.display) != [.resolved(.disconnected)])
}

@Test @MainActor func eachActionRunsSvcInThatRunnersOwnDirectory() async throws {
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  let directory = try box.addRunner(name: "build-mac")
  let commands = RecordingCommandRunner()
  let fleet = model(box, commands: commands)
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  let script = directory.appendingPathComponent("svc.sh").path
  #expect(commands.invocations == [["/bin/bash", script, "start"]])
}

@Test @MainActor func everyActionIsFollowedByAFreshProbe() async throws {
  // `svc.sh` exits 0 whatever happened underneath, so re-reading the machine
  // is the only honest feedback an action ever gets.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()
  let before = box.probeCount

  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(box.probeCount > before)
}

// MARK: - Service-operation outcomes

@Test @MainActor func aServiceActionPublishesInFlightBeforeItsCommandReturns() async throws
{
  // Removing the synchronous publication lets a menu click look ignored until
  // a blocked `svc.sh` returns, even though this runner is already reserved.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = BlockingCommandRunner()
  defer { commands.release(10) }
  let fleet = model(box, commands: commands)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.start(runner)

  #expect(fleet.operations[runner.label]?.action == .start)
  #expect(fleet.operations[runner.label]?.phase == .inFlight)
  #expect(fleet.snapshots[0].operation?.phase == .inFlight)
  commands.release()
  await fleet.quiesce()
}

@Test @MainActor func aReturnedServiceCommandIsAcceptedNotAProvedRunnerState() async throws
{
  for (kind, action) in [
    (RunnerRow.Action.Kind.start, ServiceOperationAction.start),
    (.stop, .stop), (.restart, .restart),
  ] {
    let box = try FleetSandbox(serviceRunning: false)
    defer { box.cleanUp() }
    try box.addRunner()
    let fleet = model(box)
    await fleet.quiesce()
    let runner = fleet.snapshots[0].runner

    fleet.perform(kind, on: runner)
    await fleet.quiesce()

    #expect(fleet.operations[runner.label]?.action == action)
    #expect(fleet.operations[runner.label]?.phase == .requestAccepted)
  }
}

@Test @MainActor func serviceCommandFailuresPublishTheirSpecificOutcome() async throws {
  let cases: [(any CommandRunning, RunnerRow.Action.Kind, ServiceOperationPhase)] = [
    (TimingOutCommandRunner(), .start, .uncertain(.commandTimedOut)),
    (FailingCommandRunner(), .start, .failed(.unexpectedFailure)),
    (CouldNotLaunchCommandRunner(), .stop, .failed(.commandCouldNotLaunch)),
  ]
  for (commands, kind, phase) in cases {
    let box = try FleetSandbox(serviceRunning: true)
    defer { box.cleanUp() }
    try box.addRunner()
    let fleet = model(box, commands: commands)
    await fleet.quiesce()
    let runner = fleet.snapshots[0].runner

    fleet.perform(kind, on: runner)
    await fleet.quiesce()

    #expect(fleet.operations[runner.label]?.phase == phase)
  }
}

@Test @MainActor func aMissingServiceScriptPublishesTheSpecificFailure() async throws {
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner(withScript: false)
  let fleet = model(box)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.start(runner)
  await fleet.quiesce()

  #expect(fleet.operations[runner.label]?.phase == .failed(.scriptMissing))
}

@Test @MainActor func restartSeparatesAFailedStartFromATimedOutStart() async throws {
  for (commands, phase) in [
    (
      FailingVerbCommandRunner(failingVerb: "start") as any CommandRunning,
      ServiceOperationPhase.failed(.restartStartFailed)
    ),
    (
      TimingOutVerbCommandRunner(timingOutVerb: "start") as any CommandRunning,
      .uncertain(.restartStartTimedOut)
    ),
  ] {
    let box = try FleetSandbox(serviceRunning: true)
    defer { box.cleanUp() }
    try box.addRunner()
    let fleet = model(box, commands: commands)
    await fleet.quiesce()
    let runner = fleet.snapshots[0].runner

    fleet.restart(runner)
    await fleet.quiesce()

    #expect(fleet.operations[runner.label]?.phase == phase)
  }
}

@Test @MainActor func eachRunnerRetainsItsOwnOutcomeAndANewActionOnlyReplacesItsOwn()
  async throws
{
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "first", scope: "widget")
  try box.addRunner(name: "second", scope: "gadget")
  let commands = BlockingCommandRunner()
  defer { commands.release(10) }
  let fleet = model(box, commands: commands)
  await fleet.quiesce()
  let first = try #require(
    fleet.snapshots.first { $0.runner.displayName == "first" }?.runner)
  let second = try #require(
    fleet.snapshots.first { $0.runner.displayName == "second" }?.runner)

  fleet.stop(first)
  try await commands.waitForInvocationCount(1)
  commands.release()
  await fleet.quiesce()
  #expect(fleet.operations[first.label]?.phase == .requestAccepted)

  fleet.stop(second)
  try await commands.waitForInvocationCount(2)
  commands.release()
  await fleet.quiesce()
  #expect(fleet.operations[second.label]?.phase == .requestAccepted)

  fleet.start(first)
  try await commands.waitForInvocationCount(3)
  #expect(fleet.operations[first.label]?.phase == .inFlight)
  #expect(fleet.operations[second.label]?.phase == .requestAccepted)
  commands.release()
  await fleet.quiesce()
}

@Test @MainActor
func anInconclusiveDiscoveryRetainsAnOutcomeButAConclusiveUninstallPrunesIt()
  async throws
{
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.start(runner)
  await fleet.quiesce()
  #expect(fleet.operations[runner.label]?.phase == .requestAccepted)

  box.set(discoveryFailure: .launchAgentsUnreadable(box.launchAgents))
  fleet.refresh()
  await fleet.quiesce()
  #expect(fleet.operations[runner.label]?.phase == .requestAccepted)

  box.set(discoveryFailure: nil)
  try box.removeRunner()
  fleet.refresh()
  await fleet.quiesce()
  #expect(fleet.operations[runner.label] == nil)
}

// MARK: - Telling somebody who is not looking at the menu

@Test @MainActor func openingTheAppAnnouncesNoneOfWhatItFindsOnDisk() async throws {
  // The rule, end to end and through the real log reader: a runner that is
  // already disconnected, with a failed build sitting in `_diag`, produces
  // nothing. `_diag` reaches back two days — announcing what is in it at launch
  // would fire at every login for as long as the log survives.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z", result: "Failed")
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let (fleet, delivery) = await listening(box)

  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.disconnected)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aRunnerThatFallsOffGitHubWhileTheAppRunsIsAnnounced()
  async throws
{
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let (fleet, delivery) = await listening(box)
  await fleet.quiesce()
  #expect(delivery.posted.isEmpty)

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  fleet.refresh()
  await fleet.quiesce()

  #expect(delivery.posted.count == 1)
  #expect(delivery.posted[0].title == L10n.notificationDisconnectedTitle)
  #expect(delivery.posted[0].body.contains("build-mac"))
}

@Test @MainActor func aJobThatFailsWhileTheAppRunsIsAnnounced() async throws {
  // Through the whole path this time: the listener log on disk, the reader, the
  // snapshot, the watcher and the banner. Nothing stubbed but GitHub and the
  // notification centre.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z")
  let (fleet, delivery) = await listening(box)
  await fleet.quiesce()

  try box.appendJob(
    in: directory, job: "deploy", startedAt: "2026-08-05 21:00:00Z",
    finished: "2026-08-05 21:02:00Z", result: "Failed")
  fleet.refresh()
  await fleet.quiesce()

  #expect(delivery.posted.count == 1)
  #expect(delivery.posted[0].title == L10n.notificationJobFailedTitle)
  #expect(delivery.posted[0].body.contains("deploy"))
}

@Test @MainActor func stoppingARunnerFromThisMenuAnnouncesNothing() async throws {
  // The one distinction there is between "you stopped it" and "it stopped":
  // this app saw the click. A banner telling somebody that the runner they just
  // stopped has stopped is the fastest way to have every switch turned off.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let (fleet, delivery) = await listening(box, commands: box.svcDrivingCommandRunner)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func anIdleScanDuringStopCannotSpendItsIntent() async throws {
  // The command has entered svc.sh but has not stopped the service yet. A scan
  // in that interval is newer than the click and still says idle; it is not
  // evidence that the ordered stop has already been and gone.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let commands = BlockingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()
  let before = fleet.lastReadAt

  fleet.stop(fleet.snapshots[0].runner)
  try await commands.waitForInvocationCount(1)
  clock.advance(1)
  fleet.refresh()
  try await waitUntil { fleet.lastReadAt != before }
  #expect(fleet.snapshots.map(\.display) == [.resolved(.idle)])

  commands.release()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aProbeAfterTheClickBelongsToTheOrderedStop() async throws {
  // The scan begins first, but its per-runner launchd probe is held until after
  // Stop completes. Dating every runner from scan start misclassifies this
  // genuinely post-click `.stopped` observation as stale and announces it.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let commands = BlockingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()

  let probe = box.blockNextProbe()
  defer { probe.release() }
  fleet.refresh()
  try await probe.waitUntilEntered()
  clock.advance(1)
  fleet.stop(fleet.snapshots[0].runner)
  try await commands.waitForInvocationCount(1)
  commands.release()
  try await commands.waitForCompletionCount(1)
  probe.release()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aRemoteAnswerAfterTheClickStaysSilentThroughSuccessfulStop()
  async throws
{
  // launchd says running before the click, then GitHub's offline answer lands
  // while Stop is in flight. The state transition belongs to the remote answer,
  // not the older local probe, and a successful Stop must announce neither it
  // nor the stopped observation that follows.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let commands = BlockingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let remote = box.blockNextRemoteAnswer()
  defer { remote.release() }
  fleet.refresh()
  try await remote.waitUntilEntered()

  clock.advance(1)
  fleet.stop(runner)
  try await commands.waitForInvocationCount(1)
  remote.release()
  try await waitUntil {
    fleet.snapshots.map(\.display) == [.resolved(.disconnected)]
  }
  #expect(delivery.posted.isEmpty)

  commands.release()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aPostCompletionDisconnectionWaitsForTheOrderedStop()
  async throws
{
  // svc.sh has returned, but launchd has not settled yet. Its first local
  // post-completion answer still says running and GitHub says disconnected;
  // neither that transient answer nor the stopped answer behind it belongs in
  // notifications.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = RecordingCommandRunner()
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let postCompletionProbe = box.blockNextProbe()
  defer { postCompletionProbe.release() }
  fleet.stop(runner)
  try await postCompletionProbe.waitUntilEntered()
  postCompletionProbe.release()
  try await waitUntil {
    fleet.snapshots.map(\.display) == [.resolved(.disconnected)]
  }
  #expect(delivery.posted.isEmpty)

  box.set(serviceRunning: false)
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aRemoteAnswerDeferredDuringStopReappearsWhenStopFails()
  async throws
{
  // The same split observation is provisional only while the command might
  // explain it. A definite failure revokes that intent, so the unchanged next
  // scan must compare against the pre-click baseline and report disconnection.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let commands = BlockingCommandRunner(failureAfterRelease: true)
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let remote = box.blockNextRemoteAnswer()
  defer { remote.release() }
  fleet.refresh()
  try await remote.waitUntilEntered()

  clock.advance(1)
  fleet.stop(runner)
  try await commands.waitForInvocationCount(1)
  remote.release()
  try await waitUntil {
    fleet.snapshots.map(\.display) == [.resolved(.disconnected)]
  }
  #expect(delivery.posted.isEmpty)

  commands.release()
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title) == [L10n.notificationDisconnectedTitle])
}

@Test @MainActor func aRemoteAnswerBeforeTheClickIsNotHiddenByLateScanArrival()
  async throws
{
  // The target's complete disconnected observation predates Stop, but another
  // runner delays apply until after the click. A blanket "intent in flight"
  // suppression would lose this real transition; its own remote stamp keeps it
  // attributable to the pre-click machine.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "build-mac", scope: "aaa")
  try box.addRunner(name: "release-mac", scope: "zzz")
  let clock = TestClock()
  let commands = BlockingCommandRunner(failureAfterRelease: true)
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()
  let runner = try #require(
    fleet.snapshots.first { $0.runner.displayName == "build-mac" }?.runner)

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let targetRemote = box.blockNextRemoteAnswer()
  defer { targetRemote.release() }
  fleet.refresh()
  try await targetRemote.waitUntilEntered()
  let otherProbe = box.blockNextProbe()
  defer { otherProbe.release() }
  targetRemote.release()
  try await otherProbe.waitUntilEntered()

  clock.advance(1)
  fleet.stop(runner)
  try await commands.waitForInvocationCount(1)
  box.set(remote: .success(RemoteStatus(online: true, busy: false)))
  otherProbe.release()
  try await waitUntil {
    fleet.snapshots.first { $0.runner.label == runner.label }?.display
      == .resolved(.disconnected)
  }

  #expect(delivery.posted.map(\.title) == [L10n.notificationDisconnectedTitle])

  commands.release()
  await fleet.quiesce()
}

@Test @MainActor func aRunnerRemainsOwnedUntilItsReprobeIsApplied() async throws {
  // Stop has returned and its re-probe has started, but that probe has not
  // reached apply. A second mutation here must not replace the first action's
  // still-unobserved intent. The same mutation is accepted after apply.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let commands = box.svcDrivingCommandRunner
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  let probe = box.blockNextProbe()
  defer { probe.release() }
  fleet.stop(runner)
  try await probe.waitUntilEntered()
  clock.advance(1)
  fleet.restart(runner)
  probe.release()
  await fleet.quiesce()

  #expect(commands.invocations.compactMap(\.last) == ["stop"])
  #expect(delivery.posted.isEmpty)

  fleet.restart(runner)
  await fleet.quiesce()
  #expect(commands.invocations.compactMap(\.last) == ["stop", "stop", "start"])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func absenceAtTheCompletionClockCannotReleaseThatAction() async throws {
  // Discovery has already enumerated build-mac as absent, but a slow candidate
  // keeps the call from returning until Start completes. A coarse clock gives
  // both facts the same timestamp, so their ordering is ambiguous: applying
  // the absence must not release Start's reservation. The listing failure that
  // follows is inconclusive too, so neither scan permits a second mutation.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "build-mac", scope: "widget")
  let commands = RecordingCommandRunner()
  let clock = TestClock()
  let fleet = model(box, commands: commands, probeDelay: 0.2, clock: clock.read)
  await fleet.quiesce()
  let runner = try #require(
    fleet.snapshots.first { $0.runner.displayName == "build-mac" }?.runner)

  try box.removeRunner(name: "build-mac", scope: "widget")
  let staleDiscovery = box.blockNextDiscoveryAfterReading()
  defer { staleDiscovery.release() }
  let before = fleet.lastReadAt
  clock.advance(1)
  fleet.refresh()
  try await staleDiscovery.waitUntilEntered()

  fleet.start(runner)
  try await waitUntil { commands.invocations.count == 1 }
  // Let the action resume from its off-pool command and record completedAt;
  // probeDelay keeps its own refresh from racing the stale scan below.
  try await Task.sleep(for: .milliseconds(20))
  staleDiscovery.release()
  try await waitUntil { fleet.lastReadAt != before }

  box.set(discoveryFailure: .launchAgentsUnreadable(box.launchAgents))
  fleet.start(runner)
  await fleet.quiesce()

  #expect(commands.invocations.compactMap(\.last) == ["start"])

  box.set(discoveryFailure: nil)
  try box.addRunner(name: "build-mac", scope: "widget")
  fleet.refresh()
  await fleet.quiesce()
}

@Test @MainActor func staleAbsenceCannotDiscardTheWatchersRunnerBaseline() async throws {
  // The scan enumerates build-mac as absent, then stalls before discovery
  // returns. A service action completing afterward makes that absence stale.
  // Keeping the old baseline is observable when a newly-finished failed job is
  // read: it is a transition, not history from a newly-installed runner.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner(name: "build-mac", scope: "widget")
  let clock = TestClock()
  let (fleet, delivery) = await listening(
    box, commands: RecordingCommandRunner(), probeDelay: 0.2, clock: clock.read)
  await fleet.quiesce()
  let runner = try #require(
    fleet.snapshots.first { $0.runner.displayName == "build-mac" }?.runner)

  try box.removeRunner(name: "build-mac", scope: "widget")
  let staleDiscovery = box.blockNextDiscoveryAfterReading()
  defer { staleDiscovery.release() }
  let before = fleet.lastReadAt
  clock.advance(1)
  fleet.refresh()
  try await staleDiscovery.waitUntilEntered()

  clock.advance(1)
  fleet.start(runner)
  try await Task.sleep(for: .milliseconds(20))
  staleDiscovery.release()
  try await waitUntil { fleet.lastReadAt != before }

  try box.addRunner(name: "build-mac", scope: "widget")
  try box.writeListenerLog(
    in: directory, job: "deploy", startedAt: "2026-08-05 21:00:00Z",
    finished: "2026-08-05 21:02:00Z", result: "Failed")
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title) == [L10n.notificationJobFailedTitle])
}

@Test @MainActor func removingARunnerReleasesItsServiceAction() async throws {
  // No post-completion probe can exist after uninstall. Applying that absence
  // must release ownership so a runner later installed under the same label is
  // not born permanently blocked by its predecessor.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = BlockingCommandRunner { [box] verb in
    box.set(serviceRunning: verb == "start")
  }
  defer { commands.release(10) }
  let fleet = model(box, commands: commands)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  try await commands.waitForInvocationCount(1)
  try box.removeRunner()
  commands.release()
  await fleet.quiesce()
  #expect(fleet.snapshots.isEmpty)

  try box.addRunner()
  fleet.refresh()
  await fleet.quiesce()
  fleet.start(fleet.snapshots[0].runner)
  try await commands.waitForInvocationCount(2)
  commands.release()
  await fleet.quiesce()

  #expect(commands.invocations.compactMap(\.last) == ["stop", "start"])
}

@Test @MainActor func aListingFailureCannotMasqueradeAsActionRemoval() async throws {
  // Stop completes while LaunchAgents itself cannot be listed. That empty
  // result says nothing about uninstall: ownership and the watcher baseline
  // must survive until a later conclusive probe is applied.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  let commands = BlockingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.stop(runner)
  try await commands.waitForInvocationCount(1)
  box.set(discoveryFailure: .launchAgentsUnreadable(box.launchAgents))
  commands.release()
  await fleet.quiesce()
  #expect(fleet.snapshots.isEmpty)

  fleet.restart(runner)
  commands.release(10)
  await fleet.quiesce()

  try box.writeListenerLog(
    in: directory, job: "deploy", startedAt: "2026-08-05 21:00:00Z",
    finished: "2026-08-05 21:02:00Z", result: "Failed")
  box.set(discoveryFailure: nil)
  fleet.refresh()
  await fleet.quiesce()

  #expect(commands.invocations.compactMap(\.last) == ["stop"])
  #expect(delivery.posted.map(\.title) == [L10n.notificationJobFailedTitle])
  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
}

@Test @MainActor func anUnreadableCandidateCannotMasqueradeAsActionRemoval() async throws {
  // Directory enumeration succeeds, but this runner's plist/config candidate
  // cannot resolve. Its label is still potentially installed, so the result
  // cannot erase ownership or the watcher baseline.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  let commands = BlockingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()
  let runner = fleet.snapshots[0].runner

  fleet.stop(runner)
  try await commands.waitForInvocationCount(1)
  try FileManager.default.removeItem(at: directory.appendingPathComponent(".runner"))
  commands.release()
  await fleet.quiesce()
  #expect(fleet.snapshots.isEmpty)

  fleet.restart(runner)
  commands.release(10)
  await fleet.quiesce()

  try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "deploy", startedAt: "2026-08-05 21:00:00Z",
    finished: "2026-08-05 21:02:00Z", result: "Failed")
  fleet.refresh()
  await fleet.quiesce()

  #expect(commands.invocations.compactMap(\.last) == ["stop"])
  #expect(delivery.posted.map(\.title) == [L10n.notificationJobFailedTitle])
  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
}

@Test @MainActor func aPostCompletionUnreadableProbeReleasesOnlyActionOwnership()
  async throws
{
  // Unknown normally keeps Stop/Restart available. They stay disabled while
  // svc.sh owns the label, but the first post-completion local probe releases
  // that reservation even when launchd cannot answer. The expected-stop intent
  // is separate: a later stopped reading still belongs to the ordered Stop.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = BlockingCommandRunner()
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  try await commands.waitForInvocationCount(1)
  box.set(serviceRunning: nil)
  fleet.refresh()
  try await waitUntil {
    fleet.snapshots.map(\.display)
      == [.resolved(.unknown(.serviceStateUnreadable))]
  }

  #expect(fleet.snapshots[0].row.action(.stop)?.isEnabled == false)
  #expect(fleet.snapshots[0].row.action(.restart)?.isEnabled == false)
  #expect(fleet.snapshots[0].row.action(.openOnGitHub)?.isEnabled == true)

  commands.release()
  await fleet.quiesce()
  #expect(fleet.snapshots[0].row.action(.stop)?.isEnabled == true)
  #expect(fleet.snapshots[0].row.action(.restart)?.isEnabled == true)

  box.set(serviceRunning: false)
  fleet.refresh()
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aLaterFailedMutationCannotCancelAnEarlierExpectedStop()
  async throws
{
  // Stop1 completed, but launchd's unreadable re-probe released only action
  // ownership and left its stop evidence alive. Stop2 or Restart2 can now be
  // clicked; a definite failure belongs only to that second lifecycle and must
  // reveal Stop1 again rather than erase it.
  for action in [RunnerRow.Action.Kind.stop, .restart] {
    let box = try FleetSandbox(serviceRunning: true)
    defer { box.cleanUp() }
    try box.addRunner()
    let clock = TestClock()
    let commands = SecondCommandOutcomeRunner(.definiteFailure)
    let (fleet, delivery) = await listening(
      box, commands: commands, clock: clock.read)
    await fleet.quiesce()
    let runner = fleet.snapshots[0].runner

    box.set(serviceRunning: nil)
    fleet.stop(runner)
    await fleet.quiesce()
    #expect(
      fleet.snapshots.map(\.display)
        == [.resolved(.unknown(.serviceStateUnreadable))])
    #expect(fleet.snapshots[0].row.action(action)?.isEnabled == true)

    clock.advance(1)
    fleet.perform(action, on: runner)
    await fleet.quiesce()
    #expect(commands.invocations.count == 2)

    box.set(serviceRunning: false)
    fleet.refresh()
    await fleet.quiesce()
    #expect(delivery.posted.isEmpty)

    box.set(serviceRunning: true)
    fleet.refresh()
    await fleet.quiesce()
    box.set(serviceRunning: false)
    fleet.refresh()
    await fleet.quiesce()

    #expect(delivery.posted.map(\.title) == [L10n.notificationStoppedTitle])
  }
}

@Test @MainActor func aLaterTimedOutMutationCannotReplaceAnEarlierExpectedStop()
  async throws
{
  // A timeout creates bounded evidence of its own. Once that second evidence
  // expires, Stop1's confirmed lifecycle must still own the delayed stopped
  // transition; consuming it must then leave the following crash visible.
  for action in [RunnerRow.Action.Kind.stop, .restart] {
    let box = try FleetSandbox(serviceRunning: true)
    defer { box.cleanUp() }
    try box.addRunner()
    let clock = TestClock()
    let commands = SecondCommandOutcomeRunner(.timeout)
    let (fleet, delivery) = await listening(
      box, commands: commands, clock: clock.read)
    await fleet.quiesce()
    let runner = fleet.snapshots[0].runner

    box.set(serviceRunning: nil)
    fleet.stop(runner)
    await fleet.quiesce()
    #expect(
      fleet.snapshots.map(\.display)
        == [.resolved(.unknown(.serviceStateUnreadable))])

    clock.advance(1)
    fleet.perform(action, on: runner)
    await fleet.quiesce()
    #expect(commands.invocations.count == 2)

    clock.advance(30)
    box.set(serviceRunning: false)
    fleet.refresh()
    await fleet.quiesce()
    #expect(delivery.posted.isEmpty)

    box.set(serviceRunning: true)
    fleet.refresh()
    await fleet.quiesce()
    box.set(serviceRunning: false)
    fleet.refresh()
    await fleet.quiesce()

    #expect(delivery.posted.map(\.title) == [L10n.notificationStoppedTitle])
  }
}

@Test @MainActor func aFailedStopDoesNotSilenceTheNextRealCrash() async throws {
  // A definite command failure revokes the intent immediately. The runner can
  // go down independently before the re-probe, and that crash still belongs
  // in notifications rather than under a stop the app never performed.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = FailingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title) == [L10n.notificationStoppedTitle])
}

@Test @MainActor func aStopSeenInFlightIsRecoveredWhenTheCommandFails() async throws {
  // The stopped transition lands while svc.sh is still running, so it is
  // provisionally suppressed. If svc.sh then fails definitively, the next
  // probe must recover that transition instead of accepting stopped as the
  // new baseline forever.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = BlockingCommandRunner(failureAfterRelease: true)
  defer { commands.release(10) }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  try await commands.waitForInvocationCount(1)
  box.set(serviceRunning: false)
  fleet.refresh()
  try await waitUntil { fleet.snapshots.map(\.display) == [.resolved(.stopped)] }
  #expect(delivery.posted.isEmpty)

  commands.release()
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title) == [L10n.notificationStoppedTitle])
}

@Test @MainActor func aFailedRestartDoesNotSilenceTheNextRealCrash() async throws {
  // Restart fails in its stop half here. It is still a definite failure, so
  // its expected-stop intent cannot be inherited by an unrelated crash.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = FailingCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title) == [L10n.notificationStoppedTitle])
}

@Test @MainActor func aRestartWhoseStartFailsStillOwnsItsStop() async throws {
  // Stop returns successfully and leaves launchd down; only the subsequent
  // Start fails. Cancelling the whole intent here turns the ordered first half
  // into a false unexpected-stop notification.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = FailingVerbCommandRunner(failingVerb: "start") { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(commands.invocations == ["stop", "start"])
  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aConfirmedRestartReturningToRunningSpendsItsStopIntent()
  async throws
{
  // Once both halves of Restart returned, any conclusive running answer proves
  // its stop has been and gone. It must spend immediately rather than silence
  // a real crash for the Stop grace that only an unsettled Stop needs.
  let returning: [(Result<RemoteStatus, GitHubError>, DisplayState)] = [
    (.success(RemoteStatus(online: true, busy: false)), .resolved(.idle)),
    (.success(RemoteStatus(online: true, busy: true)), .resolved(.busy)),
    (.failure(.noAnswer), .resolved(.unknown(.noAnswer))),
  ]
  for (remote, display) in returning {
    let box = try FleetSandbox(serviceRunning: true)
    defer { box.cleanUp() }
    try box.addRunner()
    let (fleet, delivery) = await listening(
      box, commands: box.svcDrivingCommandRunner)
    await fleet.quiesce()

    box.set(remote: remote)
    fleet.restart(fleet.snapshots[0].runner)
    await fleet.quiesce()
    #expect(fleet.snapshots.map(\.display) == [display])

    box.set(serviceRunning: false)
    fleet.refresh()
    await fleet.quiesce()

    #expect(delivery.posted.map(\.title).last == L10n.notificationStoppedTitle)
  }
}

@Test @MainActor func aRestartWhoseStopTimesOutKeepsIntentThroughStarting()
  async throws
{
  // Stop timed out before Restart could attempt Start. A locally-running,
  // remotely-disconnected re-probe may only mean launchd has not settled Stop
  // yet, so `.starting` cannot spend uncertain intent inside its grace.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let commands = TimingOutCommandRunner()
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.starting])

  box.set(serviceRunning: false)
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aRestartWhoseStartTimesOutCanBeSettledByStarting()
  async throws
{
  // Here Stop is known complete and Start was attempted before timing out.
  // Seeing launchd running under `.starting` resolves that uncertainty, so a
  // later independent stop must not inherit Restart's token.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  let commands = TimingOutVerbCommandRunner(timingOutVerb: "start") { [box] verb in
    box.set(serviceRunning: verb == "start")
  }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.starting])

  box.set(serviceRunning: false)
  fleet.refresh()
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title).last == L10n.notificationStoppedTitle)
}

@Test @MainActor func aTimedOutStopKeepsItsExpectedStopIntent() async throws {
  // A timeout says only that the process was killed at its deadline. If the
  // stop already took effect, its resulting scan is still the ordered stop.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = TimingOutCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: false) }
  }
  let (fleet, delivery) = await listening(box, commands: commands)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aTimedOutStopCannotSilenceACrashAfterItsLifetime() async throws {
  // The timeout leaves effects uncertain and launchd cannot answer the first
  // probe. Thirty seconds later the uncertain intent expires; a new stopped
  // transition is announced instead of inheriting old silence.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()
  let commands = TimingOutCommandRunner { [box] verb in
    if verb == "stop" { box.set(serviceRunning: nil) }
  }
  let (fleet, delivery) = await listening(
    box, commands: commands, clock: clock.read)
  await fleet.quiesce()

  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(
    fleet.snapshots.map(\.display)
      == [.resolved(.unknown(.serviceStateUnreadable))])

  clock.advance(30)
  box.set(serviceRunning: false)
  fleet.refresh()
  await fleet.quiesce()

  #expect(delivery.posted.map(\.title).last == L10n.notificationStoppedTitle)
}

@Test @MainActor func aRunnerThatGoesDownByItselfIsAnnounced() async throws {
  // The same reading as the test above, reached without a click. Everything the
  // resolver can see is identical; only the click is missing.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let (fleet, delivery) = await listening(box)
  await fleet.quiesce()

  box.set(serviceRunning: false)
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.resolved(.stopped)])
  #expect(delivery.posted.map(\.title) == [L10n.notificationStoppedTitle])
}

@Test @MainActor func aRestartAnnouncesNeitherHalfOfItself() async throws {
  // A restart takes the service down and brings it back, which looks like a
  // stop to `launchctl` and like a disconnection to GitHub. Both are this app's
  // own doing, and the settling window already covers the second.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let (fleet, delivery) = await listening(
    box, commands: box.svcDrivingCommandRunner)
  await fleet.quiesce()

  box.set(remote: .success(RemoteStatus(online: false, busy: false)))
  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(fleet.snapshots.map(\.display) == [.starting])
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func aScanLandingInsideARestartAnnouncesNoStop() async throws {
  // The gap a restart leaves is launchd's 1.5s, and a refresh can land right
  // inside it — the same sequence the settling window was built for, measured
  // on a real runner. What that scan finds is a perfectly real `.stopped`, and
  // nothing about it says this app is the one that caused it.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let (fleet, delivery) = await listening(
    box, commands: box.svcDrivingCommandRunner, settleDelay: 0.2)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  try await Task.sleep(for: .milliseconds(50))
  fleet.refresh()
  await fleet.quiesce()

  #expect(delivery.posted.isEmpty)
}

// MARK: - Keeping the Mac awake

@Test @MainActor func theMacIsHeldAwakeForAsLongAsARunnerIsBuilding() async throws {
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  try box.addRunner()
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)

  await fleet.quiesce()
  #expect(activity.isHeld)

  box.set(remote: .success(RemoteStatus(online: true, busy: false)))
  fleet.refresh()
  await fleet.quiesce()

  #expect(!activity.isHeld)
  #expect(activity.ended == 1)
}

@Test @MainActor func aListingFailureCannotEndPreviouslyObservedBusyWork() async throws {
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  try box.addRunner()
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)
  await fleet.quiesce()
  #expect(activity.isHeld)

  box.set(discoveryFailure: .launchAgentsUnreadable(box.launchAgents))
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.isEmpty)
  #expect(activity.isHeld)
  #expect(activity.ended == 0)

  box.set(discoveryFailure: nil)
  box.set(remote: .success(RemoteStatus(online: true, busy: false)))
  fleet.refresh()
  await fleet.quiesce()

  #expect(!activity.isHeld)
  #expect(activity.ended == 1)
}

@Test @MainActor func anUnreadableCandidateCannotEndItsObservedRunningLog()
  async throws
{
  let box = try FleetSandbox(
    serviceRunning: true, remote: .init(online: false, busy: false))
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: nil)
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)
  await fleet.quiesce()
  #expect(activity.isHeld)

  try FileManager.default.removeItem(at: directory.appendingPathComponent(".runner"))
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots.isEmpty)
  #expect(activity.isHeld)
  #expect(activity.ended == 0)
}

@Test @MainActor func runningLogKeepsTheMacAwakeWhenGitHubSaysDisconnected()
  async throws
{
  let box = try FleetSandbox(
    serviceRunning: true, remote: .init(online: false, busy: false))
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: nil)
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)

  await fleet.quiesce()

  #expect(fleet.snapshots[0].display == .resolved(.disconnected))
  #expect(fleet.snapshots[0].row.progress == nil)
  #expect(activity.isHeld)
}

@Test @MainActor func runningLogKeepsTheMacAwakeWhenGitHubStateIsUnknown()
  async throws
{
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: nil)
  box.set(remote: .failure(.noAnswer))
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)

  await fleet.quiesce()

  #expect(fleet.snapshots[0].display == .resolved(.unknown(.noAnswer)))
  #expect(fleet.snapshots[0].row.progress == nil)
  #expect(activity.isHeld)
}

@Test @MainActor func runningLogDoesNotKeepTheMacAwakeWhenServiceIsStopped()
  async throws
{
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: nil)
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)

  await fleet.quiesce()

  #expect(fleet.snapshots[0].display == .resolved(.stopped))
  #expect(!activity.isHeld)
}

@Test @MainActor func aMacWithNoRunnersLeftIsNotHeldAwakeForever() async throws {
  // Uninstall the runner mid-build and the snapshots go empty, which is a fleet
  // that is not busy — but only if the answer is read from the scan rather than
  // from the last thing that happened to be true.
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  try box.addRunner()
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.setEnabled(true)
  let fleet = model(box, sleep: sleepGuard)
  await fleet.quiesce()
  #expect(activity.isHeld)

  try box.removeRunner()
  fleet.refresh()
  await fleet.quiesce()

  #expect(!activity.isHeld)
}

// MARK: - Why the build is slow

@Test @MainActor func aJobPastItsUsualTimeIsWhatMakesTheHeatWorthMentioning()
  async throws
{
  // The cross with v0.2's estimate. Five successful runs of `testflight` at two
  // minutes each, and a sixth that has been going twenty — which is the only
  // situation where "this Mac is throttled" answers a question somebody has.
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeSlowRun(
    in: directory, job: "testflight", finishedRuns: 5, each: 120,
    runningFor: 20 * 60)
  let fleet = model(box)

  await fleet.quiesce()

  #expect(fleet.isOverrunning)
  #expect(
    ThermalNotice.lines(pressure: .serious, overrunning: fleet.isOverrunning).count == 2)
}

@Test @MainActor func aJobWellInsideItsUsualTimeExplainsNothing() async throws {
  // The other half: with no overrun the temperature is a fact about the
  // hardware and not an answer to anything, and the extra line would be noise
  // on top of a line that is already borderline.
  let box = try FleetSandbox(serviceRunning: true, remote: .init(online: true, busy: true))
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeSlowRun(
    in: directory, job: "testflight", finishedRuns: 5, each: 120, runningFor: 30)
  let fleet = model(box)

  await fleet.quiesce()

  #expect(!fleet.isOverrunning)
  #expect(
    ThermalNotice.lines(pressure: .serious, overrunning: fleet.isOverrunning).count == 1)
}

@Test @MainActor func aRunnerDoingNothingIsNotOverrunningAnything() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)

  await fleet.quiesce()

  #expect(!fleet.isOverrunning)
}

// MARK: - Off the main thread

@Test @MainActor func scanningDoesNotBlockTheMainThread() async throws {
  // The resolver blocks on `launchctl` and then on `gh` for up to 30s each;
  // doing that on the main actor freezes the menu bar.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  // With a log beside it, so the version read below actually happens: it is
  // only reached for a runner whose listener has written something.
  try box.writeListenerLog(
    in: directory, job: "build", startedAt: "2026-08-05 20:36:14Z", finished: nil,
    version: "2.336.0")
  let fleet = model(box)

  await fleet.quiesce()

  #expect(!box.queuesUsed.isEmpty)
  #expect(box.queuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
  // And not on the cooperative pool either, which has one thread per core and
  // is where every `Task` — detached or not — would otherwise park.
  #expect(!box.queuesUsed.contains { $0.contains("cooperative") })
  // Discovery too, and to the same standard. It is the cheap half on this
  // machine, and a directory listing plus two file reads per runner on a
  // networked home directory is not cheap anywhere. Off the main thread was
  // never the bar: `scan` is `nonisolated async`, so simply being called from
  // there already satisfies it — on the cooperative pool, which is the one
  // place this must not run.
  #expect(!box.discoveryQueuesUsed.isEmpty)
  #expect(box.discoveryQueuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
  #expect(!box.discoveryQueuesUsed.contains { $0.contains("cooperative") })
  // And the two reads v0.4 added, which had no assertion of their own. Both
  // block: one opens a file off a home directory that may be on a network
  // volume, and the other spawns `gh` and waits on the network.
  #expect(!box.versionQueuesUsed.isEmpty)
  #expect(!box.versionQueuesUsed.contains { $0.contains("cooperative") })
  #expect(box.versionQueuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
  #expect(!box.releaseQueuesUsed.isEmpty)
  #expect(!box.releaseQueuesUsed.contains { $0.contains("cooperative") })
  #expect(box.releaseQueuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
}

@Test @MainActor func actionsDoNotBlockTheMainThreadEither() async throws {
  // A button wired straight to `svc.sh` freezes the menu bar for as long as
  // the command takes, which the command timeout puts at up to 30s. The
  // action runs from a `Task` on this model, and a `Task` on a `@MainActor`
  // type runs on the main actor unless something moves it.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = RecordingCommandRunner()
  let fleet = model(box, commands: commands)
  await fleet.quiesce()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()
  box.set(serviceRunning: true)
  fleet.refresh()
  await fleet.quiesce()
  fleet.stop(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(commands.invocations.count == 2)
  #expect(commands.queuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
  #expect(!commands.queuesUsed.contains { $0.contains("cooperative") })
}

@Test @MainActor func restartKeepsItsBlockingOffBothPoolsToo() async throws {
  // Restart is the one action that goes through `ServiceController.restart`
  // rather than being handed to a queue here, because it is already `async`
  // and taking it apart would move launchd's unload-before-load gap out of the
  // controller and into the menu. It makes the hop itself instead, so the
  // guarantee is identical to Start's and Stop's — no exception to the
  // concurrency model, and nothing left to argue about.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let commands = RecordingCommandRunner()
  let fleet = model(box, commands: commands)
  await fleet.quiesce()

  fleet.restart(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(commands.invocations.count == 2)
  #expect(commands.queuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
  #expect(!commands.queuesUsed.contains { $0.contains("cooperative") })
}

@Test @MainActor func theReProbeWaitsForLaunchdBeforeItAsks() async throws {
  // `svc.sh` returns before launchd has settled, so a re-probe fired the
  // instant the command exits reports the state we just left.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box, probeDelay: 0.3)
  await fleet.quiesce()
  let probesBefore = box.probeCount
  let started = Date()

  fleet.start(fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(box.probeCount > probesBefore)
  #expect(Date().timeIntervalSince(started) >= 0.3)
}

@Test @MainActor func theMenusSingleEntryPointReachesEveryAction() async throws {
  // The view calls only `perform(_:on:)`, so a kind wired to the wrong verb
  // would be a menu whose Stop button starts things.
  let box = try FleetSandbox(serviceRunning: false)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  let commands = RecordingCommandRunner()
  let fleet = model(box, commands: commands)
  await fleet.quiesce()
  let script = directory.appendingPathComponent("svc.sh").path

  fleet.perform(.start, on: fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(commands.invocations.last == ["/bin/bash", script, "start"])

  fleet.perform(.stop, on: fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(commands.invocations.last == ["/bin/bash", script, "stop"])

  // Counted from where restart began rather than read off the tail: the verb
  // before it was already `stop`, so a restart that only started would leave
  // the last two entries looking exactly right.
  let beforeRestart = commands.invocations.count
  fleet.perform(.restart, on: fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(
    commands.invocations.dropFirst(beforeRestart).map { $0 } == [
      ["/bin/bash", script, "stop"], ["/bin/bash", script, "start"],
    ])

  // `openOnGitHub` spawns no command, so counting invocations says only that
  // nothing else happened. What it opens is the part worth pinning.
  let before = commands.invocations.count
  fleet.perform(.openOnGitHub, on: fleet.snapshots[0].runner)
  await fleet.quiesce()
  #expect(commands.invocations.count == before)
}

@Test @MainActor func openOnGitHubHandsTheBrowserThisRunnersOwnSettingsPage() async throws {
  let sandbox = try FleetSandbox()
  defer { sandbox.cleanUp() }
  _ = try sandbox.addRunner(name: "build-mac", scope: "widget")
  let opener = FakeURLOpener()
  let fleet = model(sandbox, opener: opener)
  await fleet.quiesce()

  #expect(opener.urls.isEmpty)
  fleet.perform(.openOnGitHub, on: fleet.snapshots[0].runner)
  await fleet.quiesce()

  #expect(
    opener.urls.map(\.absoluteString)
      == ["https://github.com/acme/widget/settings/actions/runners"])
}

// MARK: - Which runner is installed, and whether there is a newer one

@Test @MainActor func theVersionTheRunnerPrintsReachesTheMenu() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner(name: "build-mac")
  // The header a listener writes at the top of every log it opens, which is the
  // only place on disk that says which runner is installed.
  try box.writeListenerLog(
    in: directory, job: "build", startedAt: "2026-08-05 20:36:14Z", finished: nil,
    version: "2.336.0")

  let fleet = model(box)
  await fleet.quiesce()
  #expect(fleet.snapshots.first?.version == RunnerVersion(2, 336, 0))
}

@Test @MainActor func aRunnerThatSaysNothingAboutItsVersionIsGivenNoNumber() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner(name: "build-mac")
  try box.writeListenerLog(
    in: directory, job: "build", startedAt: "2026-08-05 20:36:14Z", finished: nil)

  let fleet = model(box)
  await fleet.quiesce()
  // Nothing rather than a number this app made up, which would then sit in the
  // menu next to a real one and be indistinguishable from it.
  #expect(fleet.snapshots.first?.version == nil)
}

@Test @MainActor func theLatestReleaseIsAskedForOnceADayAndNotEveryFifteenSeconds()
  async throws
{
  // The rule this had to obey. The status call is about this machine and runs
  // every fifteen seconds; this one is about a repository on the internet that
  // ships every few weeks, and it costs the same rate limit.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let clock = TestClock()

  let fleet = model(box, clock: clock.read)
  await fleet.quiesce()
  #expect(box.releaseCheckCount == 1)
  #expect(fleet.latestRelease == RunnerVersion(2, 336, 0))

  for _ in 0..<5 {
    clock.advance(15)
    fleet.refresh()
    await fleet.quiesce()
  }
  // Five more scans, and the runner's own state was read for every one of them.
  #expect(box.scanCount >= 6)
  #expect(box.releaseCheckCount == 1)

  clock.advance(24 * 60 * 60)
  fleet.refresh()
  await fleet.quiesce()
  #expect(box.releaseCheckCount == 2)
}

@Test @MainActor func aSlowReleaseCheckDoesNotHoldUpTheMenu() async throws {
  // It used to be inside the scan, and the scan is what paints the menu. The
  // very first one of every launch asks — `lastReleaseCheck` is process memory
  // that starts at nil — so a `gh` hanging on its 30s timeout meant half a
  // minute of empty menu at every start of the app, over the one question here
  // that nobody is waiting for. Being hours late with "there is a newer runner"
  // costs nothing; being seconds late with the runner rows is the whole app.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(releaseDelay: 0.4)

  let fleet = model(box)
  // Long enough for a scan that waited on the release check to still be inside
  // it, and short enough to be well under the delay.
  try await Task.sleep(for: .milliseconds(150))
  #expect(!fleet.snapshots.isEmpty)
  #expect(fleet.latestRelease == nil)

  // And the answer still lands, once it comes.
  await fleet.quiesce()
  #expect(fleet.latestRelease == RunnerVersion(2, 336, 0))
}

@Test @MainActor func aReleaseCheckThatGotNoAnswerStillCountsAsHavingAsked() async throws {
  // Otherwise a Mac with no network spends an API call on every single scan,
  // all day, for an answer it is not going to get — and does it fastest when
  // the connection is worst.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(latest: .failure(.noAnswer))
  let clock = TestClock()

  let fleet = model(box, clock: clock.read)
  await fleet.quiesce()
  #expect(box.releaseCheckCount == 1)
  #expect(fleet.latestRelease == nil)

  clock.advance(60)
  fleet.refresh()
  await fleet.quiesce()
  #expect(box.releaseCheckCount == 1)
}

@Test @MainActor func aReleaseAnswerSurvivesTheNextCheckFailing() async throws {
  // The runner did not stop being out of date because the Wi-Fi dropped.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(latest: .success(RunnerVersion(2, 337, 0)))
  let clock = TestClock()

  let fleet = model(box, clock: clock.read)
  await fleet.quiesce()
  #expect(fleet.latestRelease == RunnerVersion(2, 337, 0))

  box.set(latest: .failure(.noAnswer))
  clock.advance(24 * 60 * 60)
  fleet.refresh()
  await fleet.quiesce()
  #expect(box.releaseCheckCount == 2)
  #expect(fleet.latestRelease == RunnerVersion(2, 337, 0))
}

@Test @MainActor func aRunnerThatLeavesTheMachineTakesItsDiskNumbersWithIt() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner(name: "build-mac")
  let fleet = model(box)
  await fleet.quiesce()
  let runner = try #require(fleet.snapshots.first?.runner)
  fleet.housekeeping.measure(runner)
  await fleet.housekeeping.quiesce()
  #expect(fleet.housekeeping.measurement(for: runner) != nil)

  try box.removeRunner(name: "build-mac")
  fleet.refresh()
  await fleet.quiesce()
  // Otherwise a measurement of four gigabytes sits in memory for the life of
  // the app, describing a directory the uninstall may well have taken with it.
  #expect(fleet.housekeeping.measurement(for: runner) == nil)
}
