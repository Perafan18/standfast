import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// Builds the real scan/apply path while keeping every external or destructive
/// dependency inert. The filesystem reader remains real: it is the boundary
/// these regressions exercise.
@MainActor
private func diagnosticsModel(
  _ sandbox: FleetSandbox, notifications: NotificationSettings,
  sleep: SleepGuard
) -> RunnerFleetModel {
  RunnerFleetModel(
    discover: sandbox.discover, resolver: sandbox.resolver,
    controller: ServiceController(commandRunner: RecordingCommandRunner(), settleDelay: 0),
    notifications: notifications, sleep: sleep,
    housekeeping: HousekeepingModel(
      housekeeper: Housekeeper(files: DiagnosticsUntouchableFiles()),
      confirmation: DiagnosticsRefusingConfirmation(), probe: { _ in .busy }),
    versions: sandbox.versions, releases: sandbox.releases,
    opener: FakeURLOpener(), serviceConfirmation: RejectingServiceConfirmation(),
    probeDelay: 0, refreshInterval: nil)
}

@MainActor
private func enabledNotifications() async -> (
  NotificationSettings, FakeNotificationDelivery
) {
  let delivery = FakeNotificationDelivery()
  let settings = NotificationSettings(delivery: delivery, defaults: scratchDefaults())
  for kind in NotificationKind.allCases { settings.setEnabled(kind, true) }
  await settings.quiesce()
  return (settings, delivery)
}

/// Replaces `_diag` with something FileManager cannot enumerate, retaining the
/// original directory for an explicit recovery later in the test.
private struct SuspendedDiagnostics {
  let diagnostics: URL
  let parked: URL

  init(runnerDirectory: URL) throws {
    diagnostics = runnerDirectory.appendingPathComponent("_diag")
    parked = runnerDirectory.appendingPathComponent("_diag-parked")
    try FileManager.default.moveItem(at: diagnostics, to: parked)
    try Data("temporarily unavailable".utf8).write(to: diagnostics)
  }

  func restore() throws {
    try FileManager.default.removeItem(at: diagnostics)
    try FileManager.default.moveItem(at: parked, to: diagnostics)
  }
}

@MainActor
private struct DiagnosticsRefusingConfirmation: CleanupConfirming {
  func confirm(_ prompt: CleanupPrompt) -> Bool { false }
}

private struct DiagnosticsUntouchableFiles: DestructiveFileOperations {
  func createDirectory(at url: URL) throws {}
  func move(_ url: URL, to destination: URL) throws {}
  func remove(_ url: URL) throws {}
}

@Test @MainActor func anInconclusiveRemoteReadAndUnavailableDiagnosticsKeepSleepHeld()
  async throws
{
  // A missing GitHub answer cannot end a job, and neither can a directory that
  // failed to answer. The last observed running line remains the only positive
  // evidence available, so releasing the power assertion here risks sleeping
  // through the build that assertion exists to protect.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: nil)
  box.set(remote: .failure(.noAnswer))
  let activity = FakeSleepPreventer()
  let sleep = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleep.setEnabled(true)
  let (notifications, _) = await enabledNotifications()
  let fleet = diagnosticsModel(box, notifications: notifications, sleep: sleep)
  await fleet.quiesce()
  #expect(activity.isHeld)

  let suspended = try SuspendedDiagnostics(runnerDirectory: directory)
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots[0].display == .resolved(.unknown(.noAnswer)))
  #expect(fleet.snapshots[0].jobs.running?.name == "testflight")
  #expect(activity.isHeld)
  #expect(activity.ended == 0)

  try suspended.restore()
}

@Test @MainActor func recoveringDiagnosticsDoesNotRepeatABaselinedFailure() async throws {
  // The failed job predates monitoring and is baselined on the first scan. A
  // temporary listing error must not lower that watermark to nil; otherwise
  // the same old failure looks new when the directory answers again.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z", result: "Failed")
  box.set(remote: .failure(.noAnswer))
  let (notifications, delivery) = await enabledNotifications()
  let sleep = SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults())
  let fleet = diagnosticsModel(box, notifications: notifications, sleep: sleep)
  await fleet.quiesce()
  #expect(delivery.posted.isEmpty)
  #expect(fleet.snapshots[0].isJobHistoryAvailable)

  let suspended = try SuspendedDiagnostics(runnerDirectory: directory)
  fleet.refresh()
  await fleet.quiesce()
  #expect(delivery.posted.isEmpty)
  #expect(!fleet.snapshots[0].isJobHistoryAvailable)

  try suspended.restore()
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots[0].jobs.records.map(\.name) == ["testflight"])
  #expect(fleet.snapshots[0].isJobHistoryAvailable)
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor
func firstAvailableDiagnosticsReadBaselinesHistoricalFailures() async throws {
  // The app may launch while permissions or a transient volume failure makes `_diag`
  // unreadable. That empty answer is not a job-history baseline: once the
  // directory answers, everything already in it still predates monitoring and
  // must be absorbed without a login-time failure banner.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z", result: "Failed")
  let suspended = try SuspendedDiagnostics(runnerDirectory: directory)
  box.set(remote: .failure(.noAnswer))
  let (notifications, delivery) = await enabledNotifications()
  let sleep = SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults())

  let fleet = diagnosticsModel(box, notifications: notifications, sleep: sleep)
  await fleet.quiesce()
  #expect(fleet.snapshots[0].jobs == .empty)
  #expect(!fleet.snapshots[0].isJobHistoryAvailable)
  #expect(delivery.posted.isEmpty)

  try suspended.restore()
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots[0].jobs.records.map(\.name) == ["testflight"])
  #expect(fleet.snapshots[0].isJobHistoryAvailable)
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func firstReadableListenerLogBaselinesHistoricalFailures() async throws {
  // Listing and stat can both succeed while the listener path itself cannot be
  // read. A directory named like the log makes that boundary deterministic:
  // treating the failed cold read as an available empty history recreates the
  // same launch-time false notification when a real log replaces it.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  let diagnostics = directory.appendingPathComponent("_diag")
  let listener = diagnostics.appendingPathComponent(
    "Runner_20260805-000000-utc.log")
  try FileManager.default.createDirectory(
    at: listener, withIntermediateDirectories: true)
  box.set(remote: .failure(.noAnswer))
  let (notifications, delivery) = await enabledNotifications()
  let sleep = SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults())

  let fleet = diagnosticsModel(box, notifications: notifications, sleep: sleep)
  await fleet.quiesce()
  #expect(fleet.snapshots[0].jobs == .empty)
  #expect(!fleet.snapshots[0].isJobHistoryAvailable)
  #expect(delivery.posted.isEmpty)

  try FileManager.default.removeItem(at: listener)
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z", result: "Failed")
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.snapshots[0].jobs.records.map(\.name) == ["testflight"])
  #expect(fleet.snapshots[0].isJobHistoryAvailable)
  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func unavailableDiagnosticsPreserveTheLastInstalledVersion() async throws {
  // History and the installed version come from the same listener log. When
  // `_diag` stops answering, keeping one while erasing the other would make an
  // update warning flicker off on evidence that says nothing changed.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  let directory = try box.addRunner()
  try box.writeListenerLog(
    in: directory, job: "testflight", startedAt: "2026-08-05 20:36:14Z",
    finished: "2026-08-05 20:38:59Z", version: "2.320.0")
  box.set(remote: .failure(.noAnswer))
  let (notifications, _) = await enabledNotifications()
  let sleep = SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults())
  let fleet = diagnosticsModel(box, notifications: notifications, sleep: sleep)
  await fleet.quiesce()
  #expect(fleet.snapshots[0].version == RunnerVersion(2, 320, 0))
  #expect(box.versionQueuesUsed.count == 1)

  let suspended = try SuspendedDiagnostics(runnerDirectory: directory)
  fleet.refresh()
  await fleet.quiesce()

  #expect(!fleet.snapshots[0].isJobHistoryAvailable)
  #expect(fleet.snapshots[0].version == RunnerVersion(2, 320, 0))
  #expect(box.versionQueuesUsed.count == 1)

  try suspended.restore()
}
