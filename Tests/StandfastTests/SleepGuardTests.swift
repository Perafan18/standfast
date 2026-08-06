import Foundation
import Testing

@testable import Standfast

@MainActor
private func awakeGuard(
  _ activity: FakeSleepPreventer, defaults: UserDefaults = scratchDefaults(),
  enabled: Bool = true
) -> SleepGuard {
  let sleepGuard = SleepGuard(activity: activity, defaults: defaults)
  if enabled { sleepGuard.setEnabled(true) }
  return sleepGuard
}

// MARK: - Opt in

@Test @MainActor func theMacIsLeftAloneUntilSomebodyAsks() {
  // This does nothing at all on the Mac mini it was built against, which is on
  // mains power with sleep already off. It is for the laptop, where a build
  // that dies at 3am looks like a network error rather than a power setting —
  // and taking a power assertion out of somebody's MacBook without being asked
  // is not a default anybody would pick for them.
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())

  sleepGuard.update(busy: true)

  #expect(!sleepGuard.isEnabled)
  #expect(activity.begun == 0)
  #expect(!sleepGuard.isHoldingTheMacAwake)
}

@Test @MainActor func theSwitchSurvivesARelaunch() {
  let defaults = scratchDefaults()
  _ = awakeGuard(FakeSleepPreventer(), defaults: defaults)

  let second = SleepGuard(activity: FakeSleepPreventer(), defaults: defaults)

  #expect(second.isEnabled)
}

// MARK: - Held exactly while there is work

@Test @MainActor func theMacIsKeptAwakeWhileAJobIsRunning() {
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)

  sleepGuard.update(busy: true)

  #expect(sleepGuard.isHoldingTheMacAwake)
  #expect(activity.begun == 1)
  #expect(activity.ended == 0)
}

@Test @MainActor func theAssertionIsHandedBackWhenTheWorkStops() {
  // Held for the life of the app instead would be a Mac that never sleeps
  // again, which is the same bug as the `caffeinate` nobody remembered to kill.
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)
  sleepGuard.update(busy: true)

  sleepGuard.update(busy: false)

  #expect(!sleepGuard.isHoldingTheMacAwake)
  #expect(activity.ended == 1)
}

@Test @MainActor func aRunOfBusyScansTakesOutOneAssertionAndNotOnePerScan() {
  // The scan lands every fifteen seconds for as long as the job runs. One
  // assertion per scan is a leak that grows for the length of the build, and
  // the released count would never catch up.
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)

  for _ in 0..<10 { sleepGuard.update(busy: true) }

  #expect(activity.begun == 1)
  #expect(activity.ended == 0)
}

@Test @MainActor func anIdleRunOfScansHandsNothingBackTwice() {
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)
  sleepGuard.update(busy: true)

  for _ in 0..<10 { sleepGuard.update(busy: false) }

  #expect(activity.ended == 1)
}

@Test @MainActor func oneRunnerFinishingDoesNotLetTheMacSleepUnderTheOther() {
  // The multi-runner case, which is why `update` takes one answer for the whole
  // machine rather than one per runner: the assertion is either held or it is
  // not, and a Mac with two runners must stay awake until the last of them is
  // done.
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)

  // Two runners building; one finishes and the fleet is still busy.
  sleepGuard.update(busy: [true, true].contains(true))
  sleepGuard.update(busy: [false, true].contains(true))

  #expect(sleepGuard.isHoldingTheMacAwake)
  #expect(activity.ended == 0)
}

// MARK: - The switch moving mid-build

@Test @MainActor func switchingItOnDuringABuildTakesHoldStraightAway() {
  // Waiting for the next scan means up to fifteen seconds of a switch that is
  // on over a Mac that is not being kept awake — and somebody who reached for
  // this switch reached for it because a build is running right now.
  let activity = FakeSleepPreventer()
  let sleepGuard = SleepGuard(activity: activity, defaults: scratchDefaults())
  sleepGuard.update(busy: true)
  #expect(activity.begun == 0)

  sleepGuard.setEnabled(true)

  #expect(sleepGuard.isHoldingTheMacAwake)
  #expect(activity.begun == 1)
}

@Test @MainActor func switchingItOffDuringABuildReleasesTheMacStraightAway() {
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)
  sleepGuard.update(busy: true)

  sleepGuard.setEnabled(false)

  #expect(!sleepGuard.isHoldingTheMacAwake)
  #expect(activity.ended == 1)
}

@Test @MainActor func switchingItOnWithNothingRunningKeepsNothingAwake() {
  let activity = FakeSleepPreventer()

  let sleepGuard = awakeGuard(activity)

  #expect(sleepGuard.isEnabled)
  #expect(!sleepGuard.isHoldingTheMacAwake)
  #expect(activity.begun == 0)
}

@Test @MainActor func theAssertionSaysWhoTookItOut() {
  // What somebody staring at `pmset -g assertions`, wondering why their Mac
  // will not sleep, has to be able to read.
  let activity = FakeSleepPreventer()
  let sleepGuard = awakeGuard(activity)

  sleepGuard.update(busy: true)

  #expect(activity.reasons.first?.contains("Standfast") == true)
}
