import Foundation
import Testing

@testable import Standfast

@MainActor
private func settings(
  _ delivery: FakeNotificationDelivery, defaults: UserDefaults = scratchDefaults()
) -> NotificationSettings {
  NotificationSettings(delivery: delivery, defaults: defaults)
}

// MARK: - Off until asked, and not asking early

@Test @MainActor func aFreshInstallNotifiesAboutNothing() {
  // Every switch off. This runner takes eight jobs a day; an app that arrives
  // with notifications on is one whose notifications are switched off again by
  // the end of the first afternoon — failures and all.
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)

  #expect(notifications.enabled.isEmpty)
  for kind in NotificationKind.allCases { #expect(!notifications.isEnabled(kind)) }
}

@Test @MainActor func launchingTheAppAsksNobodyForPermission() {
  // Asking on first launch is asking before this app has shown anybody why they
  // would say yes — and the no that follows is a no that then applies to the
  // failure notification they would have wanted a week later. macOS only offers
  // the prompt once.
  let delivery = FakeNotificationDelivery()

  let notifications = settings(delivery)

  #expect(delivery.authorizationRequests == 0)
  #expect(notifications.authorization == .notDetermined)
}

@Test @MainActor func permissionIsAskedForWhenASwitchGoesOn() async {
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)

  notifications.setEnabled(.jobFailed, true)
  await notifications.quiesce()

  #expect(delivery.authorizationRequests == 1)
  #expect(notifications.authorization == .authorized)
}

@Test @MainActor func enablingASwitchReadsTheSystemVerdictAfterRequestingPermission()
  async
{
  let delivery = FakeNotificationDelivery()
  delivery.grants = true
  delivery.currentAuthorization = .denied
  let notifications = settings(delivery)

  notifications.setEnabled(.jobFailed, true)
  await notifications.quiesce()

  #expect(delivery.authorizationRequests == 1)
  #expect(delivery.authorizationStatusReads == 1)
  #expect(notifications.authorization == .denied)
}

@Test @MainActor func switchingSomethingOffAsksForNothing() async {
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)
  notifications.setEnabled(.jobFailed, true)
  await notifications.quiesce()

  notifications.setEnabled(.jobFailed, false)
  await notifications.quiesce()

  #expect(delivery.authorizationRequests == 1)
  #expect(!notifications.isEnabled(.jobFailed))
}

@Test @MainActor func aRefusedPermissionIsSaidOutLoudRatherThanSwallowed() async {
  // The same rule the login item follows: never louder than the truth. A switch
  // sitting on `on` over a system that will not deliver anything leaves somebody
  // waiting for a warning that can never arrive.
  let delivery = FakeNotificationDelivery()
  delivery.grants = false
  delivery.currentAuthorization = .denied
  let notifications = settings(delivery)

  notifications.setEnabled(.runnerDisconnected, true)
  await notifications.quiesce()

  #expect(notifications.authorization == .denied)
  #expect(notifications.notice != nil)
}

@Test @MainActor func thereIsNothingToExplainBeforeAnybodyHasAskedForAnything() {
  let delivery = FakeNotificationDelivery()

  #expect(settings(delivery).notice == nil)
}

// MARK: - Remembering the switches

@Test @MainActor func theSwitchesSurviveARelaunch() {
  let defaults = scratchDefaults()
  let first = settings(FakeNotificationDelivery(), defaults: defaults)
  first.setEnabled(.jobFailed, true)
  first.setEnabled(.runnerStopped, true)

  let second = settings(FakeNotificationDelivery(), defaults: defaults)

  #expect(second.isEnabled(.jobFailed))
  #expect(second.isEnabled(.runnerStopped))
  #expect(!second.isEnabled(.runnerDisconnected))
}

@Test @MainActor func relaunchWithAnEnabledSwitchRestoresAuthorizedSystemState()
  async
{
  let defaults = scratchDefaults()
  defaults.set(true, forKey: NotificationKind.jobFailed.defaultsKey)
  let delivery = FakeNotificationDelivery()
  delivery.currentAuthorization = .authorized

  let notifications = settings(delivery, defaults: defaults)
  await notifications.quiesce()

  #expect(delivery.authorizationRequests == 0)
  #expect(delivery.authorizationStatusReads == 1)
  #expect(notifications.authorization == .authorized)
}

@Test @MainActor func relaunchWithAnEnabledSwitchRestoresDeniedSystemState()
  async
{
  let defaults = scratchDefaults()
  defaults.set(true, forKey: NotificationKind.runnerStopped.defaultsKey)
  let delivery = FakeNotificationDelivery()
  delivery.currentAuthorization = .denied

  let notifications = settings(delivery, defaults: defaults)
  await notifications.quiesce()

  #expect(delivery.authorizationRequests == 0)
  #expect(delivery.authorizationStatusReads == 1)
  #expect(notifications.authorization == .denied)
  #expect(notifications.notice != nil)
}

@Test @MainActor func staleRelaunchReadCannotOverwriteANewerPermissionVerdict()
  async
{
  let defaults = scratchDefaults()
  defaults.set(true, forKey: NotificationKind.jobFailed.defaultsKey)
  let delivery = FakeNotificationDelivery()
  delivery.suspendsAuthorizationStatusReads = true
  let notifications = settings(delivery, defaults: defaults)
  for _ in 0..<100 where delivery.authorizationStatusReads < 1 {
    await Task.yield()
  }
  #expect(delivery.authorizationStatusReads >= 1)
  guard delivery.authorizationStatusReads >= 1 else { return }

  notifications.setEnabled(.runnerStopped, true)
  for _ in 0..<100 where delivery.authorizationStatusReads < 2 {
    await Task.yield()
  }
  #expect(delivery.authorizationStatusReads >= 2)
  guard delivery.authorizationStatusReads >= 2 else {
    delivery.resolveAuthorizationStatusRead(1, as: .denied)
    return
  }
  delivery.resolveAuthorizationStatusRead(2, as: .authorized)
  await notifications.quiesce()
  #expect(notifications.authorization == .authorized)

  delivery.resolveAuthorizationStatusRead(1, as: .denied)
  for _ in 0..<5 { await Task.yield() }

  #expect(notifications.authorization == .authorized)
}

@Test @MainActor func everySwitchIsRememberedSomewhereOfItsOwn() {
  // Two kinds sharing a key is one switch that turns two things on, and the
  // symptom — "I only asked for failures and now it tells me everything" — is
  // exactly the noise this whole feature is arranged against.
  let keys = NotificationKind.allCases.map(\.defaultsKey)

  #expect(Set(keys).count == NotificationKind.allCases.count)
  #expect(!keys.contains { $0.isEmpty })
}

// MARK: - Delivering

@Test @MainActor func onlyTheEventsWhoseSwitchIsOnReachTheScreen() async {
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)
  notifications.setEnabled(.jobFailed, true)
  await notifications.quiesce()

  notifications.deliver([
    .jobFailed(runner: "mac-mini-m4", job: "testflight"),
    .runnerDisconnected(runner: "mac-mini-m4"),
    .runnerStoppedUnexpectedly(runner: "mac-mini-m4"),
  ])

  #expect(delivery.posted.count == 1)
  #expect(delivery.posted[0].body.contains("testflight"))
}

@Test @MainActor func withEverySwitchOffNothingIsPostedAtAll() {
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)

  notifications.deliver([
    .jobFailed(runner: "mac-mini-m4", job: "testflight"),
    .runnerDisconnected(runner: "mac-mini-m4"),
    .runnerStoppedUnexpectedly(runner: "mac-mini-m4"),
  ])

  #expect(delivery.posted.isEmpty)
}

@Test @MainActor func twoRunnersInTroubleGetTwoBannersRatherThanOne() async {
  // Identifiers are how macOS decides whether a notification replaces an
  // earlier one. Anything constant across events would mean the second runner
  // going down quietly erases the first one's banner.
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)
  for kind in NotificationKind.allCases { notifications.setEnabled(kind, true) }
  await notifications.quiesce()

  notifications.deliver([
    .runnerDisconnected(runner: "mac-mini-m4"),
    .runnerDisconnected(runner: "build-mac"),
    .runnerStoppedUnexpectedly(runner: "mac-mini-m4"),
  ])

  #expect(Set(delivery.posted.map(\.id)).count == 3)
}

@Test @MainActor func theSameTroubleTwiceReplacesItsOwnBannerRatherThanStacking()
  async
{
  // A runner that flaps produces the same event again, and two banners saying
  // the same thing is the noise a menu bar app has no room for.
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)
  notifications.setEnabled(.runnerDisconnected, true)
  await notifications.quiesce()

  notifications.deliver([.runnerDisconnected(runner: "mac-mini-m4")])
  notifications.deliver([.runnerDisconnected(runner: "mac-mini-m4")])

  #expect(delivery.posted.count == 2)
  #expect(delivery.posted[0].id == delivery.posted[1].id)
}

@Test @MainActor func aBannerCarriesTheTitleAndBodyItsEventNames() async {
  let delivery = FakeNotificationDelivery()
  let notifications = settings(delivery)
  notifications.setEnabled(.jobFailed, true)
  await notifications.quiesce()
  let event = FleetEvent.jobFailed(runner: "mac-mini-m4", job: "testflight")

  notifications.deliver([event])

  #expect(delivery.posted.first?.title == event.title)
  #expect(delivery.posted.first?.body == event.body)
}
