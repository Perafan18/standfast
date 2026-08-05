import Foundation
import RunnerKit
import Testing

@testable import RunnerMenubar

@MainActor
private func model(
  _ sandbox: FleetSandbox, commands: RecordingCommandRunner = RecordingCommandRunner(),
  settling: SettlingWindow = SettlingWindow(), settleDelay: TimeInterval = 0
) -> RunnerFleetModel {
  RunnerFleetModel(
    discover: sandbox.discover, resolver: sandbox.resolver,
    controller: ServiceController(commandRunner: commands, settleDelay: settleDelay),
    settling: settling, probeDelay: 0,
    // No ticker: these tests drive every refresh themselves.
    refreshInterval: nil)
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

// MARK: - Acting on one runner, not on the machine

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

// MARK: - Off the main thread

@Test @MainActor func scanningDoesNotBlockTheMainThread() async throws {
  // The resolver blocks on `launchctl` and then on `gh` for up to 30s each;
  // doing that on the main actor freezes the menu bar.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = model(box)

  await fleet.quiesce()

  #expect(!box.queuesUsed.isEmpty)
  #expect(box.queuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
  // And not on the cooperative pool either, which has one thread per core and
  // is where every `Task` — detached or not — would otherwise park.
  #expect(!box.queuesUsed.contains { $0.contains("cooperative") })
  // Discovery too. It is the cheap half on this machine, and a directory
  // listing on a networked home directory is not cheap anywhere.
  #expect(!box.discoveryQueuesUsed.isEmpty)
  #expect(box.discoveryQueuesUsed.allSatisfy { $0 != "com.apple.main-thread" })
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

@Test @MainActor func restartDoesNotBlockTheMainThreadEither() async throws {
  // Restart is the one action that goes through `ServiceController.restart`
  // rather than being handed to a queue, because it is already `async` and
  // taking it apart here would move launchd's unload-before-load gap into the
  // menu. That leaves its two `svc.sh` calls on the cooperative pool — which
  // this pins, so the trade stays a choice — but never on the main thread.
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
}
