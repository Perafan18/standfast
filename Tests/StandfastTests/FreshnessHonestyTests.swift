import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// UI-037: the freshness line dated the attempt, not the reading.
///
/// Codex, third pass: *"la cabecera dice que GitHub no respondió y debajo dice
/// `Consultado ahora mismo`. Es literalmente compatible, pero operativamente
/// puede leerse como «el estado es fresco». Debería distinguir `Actualización
/// fallida ahora mismo` de la última lectura válida."*
///
/// He is right and it matters exactly once: when somebody is deciding whether
/// to act on what the window says. A line that says "just now" over a state
/// nobody could read is the app sounding most confident at its least informed.
private let noon = Date(timeIntervalSince1970: 1_785_962_174)

// MARK: - What it said before, it still says

@Test func aGoodReadingStillJustSaysHowOldItIs() {
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: noon.addingTimeInterval(-245), now: noon, isScanning: false,
      lastAttemptFailed: false) == L10n.checkedAgo("4m"))
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: noon.addingTimeInterval(-3), now: noon, isScanning: false,
      lastAttemptFailed: false) == L10n.checkedJustNow)
}

@Test func aScanInFlightStillOutranksEverythingElse() {
  // Something is happening right now, which is more useful than either the age
  // or the last failure.
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: noon.addingTimeInterval(-245), now: noon, isScanning: true,
      lastAttemptFailed: true) == L10n.checkingRunners)
}

// MARK: - What it refused to say before

@Test func aFailedAttemptSaysSoAndStillDatesTheLastGoodReading() {
  // Both facts, in the order that matters: the attempt failed, and what you
  // are looking at is four minutes old.
  let line = FleetStatus.lastCheckedLine(
    readAt: noon.addingTimeInterval(-245), now: noon, isScanning: false,
    lastAttemptFailed: true)

  #expect(line == L10n.checkFailedThenChecked(L10n.checkedAgo("4m")))
  #expect(line != L10n.checkedAgo("4m"))
  #expect(line.contains("4m"))
}

@Test func aFailedAttemptWithNothingGoodBehindItDoesNotInventAnAge() {
  // First scan of the session, and it failed. Saying "just now" here would be
  // the exact lie this test exists to prevent.
  let line = FleetStatus.lastCheckedLine(
    readAt: nil, now: noon, isScanning: false, lastAttemptFailed: true)

  #expect(line == L10n.checkFailedThenChecked(L10n.checkedNever))
  #expect(!line.contains(L10n.checkedJustNow))
}

// MARK: - Where the flag comes from

@Test @MainActor func aRunnerNobodyCouldResolveMakesTheWholeReadingSuspect()
  async throws
{
  // The line speaks for the fleet, so it is only a good reading when every
  // runner resolved. One unknown means the window is showing something older
  // than the timestamp it was about to print.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  let fleet = freshnessModel(box)
  await fleet.quiesce()
  #expect(!fleet.lastAttemptFailed)
  let good = try #require(fleet.lastReadAt)

  box.set(remote: .failure(.notAuthenticated))
  fleet.refresh()
  await fleet.quiesce()

  #expect(fleet.lastAttemptFailed)
  // And the good reading is still the one being dated: the failed attempt did
  // not overwrite it.
  #expect(fleet.lastReadAt == good)
}

@Test @MainActor func aReadingThatRecoversStopsBlamingTheOldFailure()
  async throws
{
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .failure(.notAuthenticated))
  let fleet = freshnessModel(box)
  await fleet.quiesce()
  #expect(fleet.lastAttemptFailed)

  box.set(remote: .success(RemoteStatus(online: true, busy: false)))
  fleet.refresh()
  await fleet.quiesce()

  #expect(!fleet.lastAttemptFailed)
  #expect(fleet.lastReadAt != nil)
}

@Test @MainActor func aGitLabRunnerWithNoTokenIsNotAFailedReading() async throws {
  // No token is a setting, not a failed read: nothing was asked. Counting it
  // froze the line at "Update failed · Not checked yet" while the GitHub
  // runner beside it was read on schedule.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  try box.addGitLabRunner()
  let fleet = freshnessModel(box)
  await fleet.quiesce()
  #expect(
    fleet.snapshots.map(\.display).contains(.resolved(.unknown(.gitLabNoToken))))

  #expect(!fleet.lastAttemptFailed)
  #expect(fleet.lastReadAt != nil)
}

@Test @MainActor func aGitLabRunnerPausedInGitLabIsNotAFailedReading() async throws {
  // GitLab answered, and the answer was "paused". That is a reading, so the
  // line beside it must not say the update failed.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addGitLabRunner()
  box.set(gitLabAnswer: #"{"id":91,"status":"online","paused":true,"tag_list":[]}"#)
  let fleet = freshnessModel(box)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.resolved(.unknown(.gitLabPaused))])
}

@Test @MainActor func aGitLabInstanceServedOverHTTPIsNotAFailedReading() async throws {
  // Not asked on purpose, because a token goes only over https. Like no token,
  // that is a setting of the instance, and counting it would hold the line at
  // "Update failed" for as long as config.toml names an http address.
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  try box.addGitLabRunner(url: "http://gitlab.lan:8080")
  let fleet = freshnessModel(box)
  await fleet.quiesce()
  #expect(
    fleet.snapshots.map(\.display).contains(.resolved(.unknown(.gitLabInsecure))))

  #expect(!fleet.lastAttemptFailed)
  #expect(fleet.lastReadAt != nil)
}

@Test @MainActor func aGitHubRunnerWithNoTokenIsNotAFailedReadingEither() async throws {
  let box = try FleetSandbox(serviceRunning: true)
  defer { box.cleanUp() }
  try box.addRunner()
  box.set(remote: .failure(.noToken))
  let fleet = freshnessModel(box)
  await fleet.quiesce()
  #expect(fleet.snapshots.map(\.display) == [.resolved(.unknown(.noToken))])

  #expect(!fleet.lastAttemptFailed)
  #expect(fleet.lastReadAt != nil)
}

@MainActor
private func freshnessModel(_ sandbox: FleetSandbox) -> RunnerFleetModel {
  RunnerFleetModel(
    discover: sandbox.discover, resolver: sandbox.resolver,
    controller: ServiceController(commandRunner: RecordingCommandRunner()),
    notifications: NotificationSettings(
      delivery: FakeNotificationDelivery(), defaults: scratchDefaults()),
    sleep: SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults()),
    versions: sandbox.versions, releases: sandbox.releases, opener: FakeURLOpener(),
    serviceConfirmation: RejectingServiceConfirmation(), refreshInterval: nil)
}
