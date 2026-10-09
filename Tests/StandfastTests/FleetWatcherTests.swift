import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let launch = Date(timeIntervalSince1970: 1_785_962_174)

/// The one runner, read `seconds` after `launch`, for a test about a sequence
/// of scans rather than a single one.
private func reading(_ display: DisplayState, at seconds: TimeInterval) -> RunnerSnapshot {
  let readAt = launch.addingTimeInterval(seconds)
  return snapshot(display: display, readAt: readAt, stateReadAt: readAt)
}

// MARK: - Nothing from before the app was watching

@Test func theFirstReadingOfARunnerAnnouncesNoneOfItsJobs() {
  // The rule the whole feature stands on. `_diag` reaches back about two days,
  // so a failed build from Tuesday is sitting in the log the moment the app
  // opens — and announcing it would be a banner about something the user
  // already dealt with, arriving at login every single morning.
  //
  // D-R19 carved one exception out of this, and only one: the *state* of a
  // runner found already disconnected. The job history is untouched.
  var watcher = FleetWatcher()
  let broken = history([
    job("testflight", at: 1_785_960_000, result: .failed),
    job("testflight", at: 1_785_950_000, result: .failed),
  ])

  let events = watcher.events(in: [snapshot(display: .resolved(.idle), jobs: broken)])

  #expect(events.isEmpty)
}

@Test func aRunnerInstalledWhileTheAppIsOpenIsAlsoBaselined() {
  // New to this app, not new to the machine. A runner that appears at the
  // second scan brings the same two days of log with it, and it is not this
  // app's business to report a history it simply had not read yet.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot("build-mac")])

  let events = watcher.events(in: [
    snapshot("build-mac"),
    snapshot(
      "release-mac", display: .resolved(.stopped),
      jobs: history([job("deploy", at: 1_785_960_000, result: .failed)])),
  ])

  #expect(events.isEmpty)
}

// MARK: - Failed jobs

@Test func aJobThatFailsWhileTheAppIsWatchingIsReported() {
  var watcher = FleetWatcher()
  // A successful empty read is a baseline, unlike an unavailable empty read.
  // The failure appearing after it is therefore new and must be reported.
  #expect(
    watcher.events(in: [
      snapshot(jobs: .empty, isJobHistoryAvailable: true)
    ]).isEmpty)

  let events = watcher.events(in: [
    snapshot(
      jobs: history([
        job("testflight", at: 1_785_960_000, result: .failed),
        job("testflight", at: 1_785_950_000, result: .succeeded),
      ]))
  ])

  #expect(events == [.jobFailed(runner: "build-mac", job: "testflight")])
}

@Test func theSameFailureIsNotReportedTwice() {
  // The scan runs every fifteen seconds and the failed job stays in the log for
  // two days. Reporting what is there rather than what changed would be 5,760
  // banners about one broken build.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot()])
  let failed = history([job("testflight", at: 1_785_960_000, result: .failed)])
  #expect(watcher.events(in: [snapshot(jobs: failed)]).count == 1)

  #expect(watcher.events(in: [snapshot(jobs: failed)]).isEmpty)
  #expect(watcher.events(in: [snapshot(jobs: failed)]).isEmpty)
}

@Test func theEightGoodBuildsADayStaySilent() {
  // The measured shape of a real runner: two days on the machine this was built
  // against held 14 `Succeeded`, 2 `Canceled` and 1 `Failed`. Only the last of
  // those is worth interrupting somebody for — a cancelled job is nearly always
  // one the person cancelled themselves, and eight banners a day for work that
  // went fine is how a user ends up switching all of this off, failures
  // included.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot()])

  let events = watcher.events(in: [
    snapshot(
      jobs: history([
        job("testflight", at: 1_785_960_300, result: .canceled),
        job("testflight", at: 1_785_960_200, result: .succeeded),
        job("lint", at: 1_785_960_100, result: .succeeded),
      ]))
  ])

  #expect(events.isEmpty)
}

@Test func anOutcomeThisVersionHasNeverMetIsNotCalledAFailure() {
  // The runner serialises the name of an enum it may add to, so a word this app
  // does not know could be `SucceededWithIssues` as easily as anything alarming.
  // Waking somebody up over a word nobody has read the meaning of is the one
  // mistake a notification cannot take back.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot()])

  let events = watcher.events(in: [
    snapshot(
      jobs: history([job("testflight", at: 1_785_960_000, result: .other("Abandoned"))])
    )
  ])

  #expect(events.isEmpty)
}

@Test func aJobStillRunningIsNotAFailureYet() {
  // A record with no completion line is either a job in flight or a listener
  // that died mid-job. Neither is a `Failed`, and the running one becomes a
  // result of its own a few minutes later.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot()])
  let running = job("testflight", at: 1_785_960_000, result: nil)

  let events = watcher.events(in: [
    snapshot(display: .resolved(.busy), jobs: history([running], running: running))
  ])

  #expect(events.isEmpty)
}

@Test func twoFailuresBetweenTwoScansAreBothReportedOldestFirst() {
  // The scan can be minutes apart — a slow `gh`, a Mac that was asleep — and a
  // watcher that only ever looked at the newest record would quietly drop the
  // rest.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [
    snapshot(jobs: history([job("lint", at: 1_785_940_000, result: .succeeded)]))
  ])

  let events = watcher.events(in: [
    snapshot(
      jobs: history([
        job("deploy", at: 1_785_960_000, result: .failed),
        job("testflight", at: 1_785_950_000, result: .failed),
        job("lint", at: 1_785_940_000, result: .succeeded),
      ]))
  ])

  #expect(
    events == [
      .jobFailed(runner: "build-mac", job: "testflight"),
      .jobFailed(runner: "build-mac", job: "deploy"),
    ])
}

@Test func aRunnerWithNoHistoryAtAllStillReportsItsFirstFailure() {
  // The baseline for a runner whose `_diag` held nothing is "no finished job",
  // not "nothing to compare against ever again".
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(jobs: .empty)])

  let events = watcher.events(in: [
    snapshot(jobs: history([job("testflight", at: 1_785_960_000, result: .failed)]))
  ])

  #expect(events == [.jobFailed(runner: "build-mac", job: "testflight")])
}

@Test func theRunnerNamedInAFailureIsTheOneTheMenuShows() {
  // One Mac in two repositories is two runners both called `mac-mini-m4`,
  // because `config.sh` proposes the hostname and everybody presses enter. A
  // banner naming only that tells the reader nothing they can act on.
  var watcher = FleetWatcher()
  let one = snapshot("mac-mini-m4", scope: "widget", qualifier: "acme/widget")
  let two = snapshot("mac-mini-m4", scope: "gadget", qualifier: "acme/gadget")
  _ = watcher.events(in: [one, two])

  let events = watcher.events(in: [
    one,
    snapshot(
      "mac-mini-m4", scope: "gadget", qualifier: "acme/gadget",
      jobs: history([job("deploy", at: 1_785_960_000, result: .failed)])),
  ])

  #expect(events == [.jobFailed(runner: "mac-mini-m4 (acme/gadget)", job: "deploy")])
}

@Test func theLaunchAnnouncementNamesTheRunnerTheWayTheMenuDoes() {
  // The same two `mac-mini-m4`s, both down when the app opens. Named bare, the
  // two banners share one identifier, the second replaces the first, and the
  // one left standing does not say which repository has lost its runner.
  var watcher = FleetWatcher()
  func bothDown(at second: TimeInterval) -> [RunnerSnapshot] {
    let at = launch.addingTimeInterval(second)
    return [
      snapshot(
        "mac-mini-m4", scope: "widget", display: .resolved(.disconnected),
        qualifier: "acme/widget", readAt: at, stateReadAt: at),
      snapshot(
        "mac-mini-m4", scope: "gadget", display: .resolved(.disconnected),
        qualifier: "acme/gadget", readAt: at, stateReadAt: at),
    ]
  }
  _ = watcher.events(in: bothDown(at: 0))

  let events = watcher.events(in: bothDown(at: 30))

  #expect(
    events == [
      .runnerDisconnected(runner: "mac-mini-m4 (acme/widget)"),
      .runnerDisconnected(runner: "mac-mini-m4 (acme/gadget)"),
    ])
}

// MARK: - A runner GitHub cannot see

@Test func aRunnerFallingOffGitHubIsReportedOnce() {
  // The silent failure this app exists for. Reported once it has outlasted a
  // registration, and not again: "still disconnected" every fifteen seconds is
  // the same fact 240 times an hour.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])

  var announced: [Int] = []
  for second in stride(from: 15.0, through: 120, by: 15) {
    announced.append(
      watcher.events(in: [reading(.resolved(.disconnected), at: second)]).count)
  }

  // First read at 15 and still down at 45: the settling window's thirty seconds.
  #expect(announced == [0, 0, 1, 0, 0, 0, 0, 0])
}

@Test func aRunnerThatComesBackCanBeReportedAgainIfItGoesAgain() {
  // The other half of "only transitions": a flapping runner is a real problem,
  // and a watcher that reported a state once and never again would go quiet
  // exactly where the trouble is.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 15)])
  #expect(watcher.events(in: [reading(.resolved(.disconnected), at: 45)]).count == 1)
  #expect(watcher.events(in: [reading(.resolved(.idle), at: 60)]).isEmpty)

  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 75)])
  let again = watcher.events(in: [reading(.resolved(.disconnected), at: 105)])

  #expect(again == [.runnerDisconnected(runner: "build-mac")])
}

@Test func aRunnerReconnectingAfterAWakeIsNotCalledDisconnected() {
  // The laptop sleeps, GitHub marks the runner offline, and the first scan
  // after waking reaches GitHub before the listener has. It is back a scan
  // later: the same gap the settling window hides after a Start.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])

  let waking = watcher.events(in: [reading(.resolved(.disconnected), at: 3_600)])
  let back = watcher.events(in: [reading(.resolved(.idle), at: 3_615)])

  #expect(waking.isEmpty)
  #expect(back.isEmpty)
}

@Test func aDisconnectionReadBeforeASleepWaitsItsGraceAgainAfterTheWake() {
  // A scan in a dark wake reads the runner offline, and the Mac sleeps again
  // before the grace has run. That reading says nothing about the hour slept
  // through, so the first scan after the real wake, which lands in the
  // registration gap, starts the thirty seconds over instead of finding them
  // long gone.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 15)])

  let waking = watcher.events(in: [reading(.resolved(.disconnected), at: 3_615)])
  let stillDown = watcher.events(in: [reading(.resolved(.disconnected), at: 3_645)])

  #expect(waking.isEmpty)
  #expect(stillDown == [.runnerDisconnected(runner: "build-mac")])
}

@Test func aClockSetBackHoldsADisconnectionNoLongerThanItsGrace() {
  // `timed` steps the wall clock back ten minutes while a disconnection is
  // waiting out its grace. Measured from a first reading that now lies in the
  // future, the banner would wait out the whole step.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 15)])

  let stepped = watcher.events(in: [reading(.resolved(.disconnected), at: -570)])
  let settled = watcher.events(in: [reading(.resolved(.disconnected), at: -540)])

  #expect(stepped.isEmpty)
  #expect(settled == [.runnerDisconnected(runner: "build-mac")])
}

@Test func aScanSlowerThanTheTickStillReportsADisconnection() {
  // Other runners' requests timing out can stretch a scan well past the tick,
  // so this runner is read every ninety seconds instead of every fifteen. The
  // app never stopped watching, and a gap that started the grace over on every
  // reading would never let it run out.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 90)])

  #expect(
    watcher.events(in: [reading(.resolved(.disconnected), at: 180)])
      == [.runnerDisconnected(runner: "build-mac")])
}

@Test func readingsGitHubDidNotAnswerStillCountAsWatching() {
  // GitHub stops answering for a few minutes while the runner is off it. This
  // app read the runner throughout, so the disconnection on either side is one
  // disconnection, long past its grace.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 15)])
  for second in stride(from: 30.0, through: 390, by: 15) {
    _ = watcher.events(in: [reading(.resolved(.unknown(.noAnswer)), at: second)])
  }

  #expect(
    watcher.events(in: [reading(.resolved(.disconnected), at: 405)])
      == [.runnerDisconnected(runner: "build-mac")])
}

@Test func aRunnerStillComingUpAtLoginIsNotAnnouncedAsDown() {
  // launchd starts the runner at login and this app's first scan finds it up
  // but not yet registered. D-R19 is for a runner that is down, and this one
  // is idle a scan later.
  var watcher = FleetWatcher()

  let launching = watcher.events(in: [reading(.resolved(.disconnected), at: 0)])
  let registered = watcher.events(in: [reading(.resolved(.idle), at: 15)])

  #expect(launching.isEmpty)
  #expect(registered.isEmpty)
}

@Test func aDisconnectedReadingDuringStopIsProvisional() {
  // Stop has been requested but svc.sh has not returned. launchd can still say
  // running while GitHub has already moved the runner offline; that transient
  // reading belongs to the mutation and must not announce a disconnection.
  let requestedAt = Date(timeIntervalSince1970: 200)
  var watcher = FleetWatcher()
  let runner = snapshot(
    display: .resolved(.idle), readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  watcher.expectStop(for: runner.runner.label, at: requestedAt)

  let events = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(1))
  ])
  let stillInFlight = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(31))
  ])

  #expect(events.isEmpty)
  #expect(stillInFlight.isEmpty)
}

@Test func aFailedStopReplaysItsProvisionalDisconnection() {
  // Deferring the in-flight transition must not erase it. If svc.sh then
  // fails and revokes the stop intent, the unchanged next scan compares with
  // the pre-click baseline and reports the real disconnection.
  let requestedAt = Date(timeIntervalSince1970: 200)
  var watcher = FleetWatcher()
  let runner = snapshot(
    display: .resolved(.idle), readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
  _ = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(1))
  ])

  watcher.cancelExpectedStop(expectedStop)
  _ = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(2))
  ])
  let events = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(32))
  ])

  #expect(events == [.runnerDisconnected(runner: "build-mac")])
}

@Test func nonStoppedReadingsInsideTheCompletionGracePreserveTheOrderedStop() {
  // launchd can lag behind svc.sh returning, and GitHub can answer only after
  // that local grace has ended. The local observation still belongs inside the
  // grace; remote latency must neither spend its token nor announce it, and the
  // stopped reading behind it must remain silent.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  for display in [
    DisplayState.resolved(.idle),
    .resolved(.busy),
    .resolved(.disconnected),
    .resolved(.unknown(.noAnswer)),
  ] {
    var watcher = FleetWatcher(expectedStopLifetime: 30)
    let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
    _ = watcher.events(in: [runner])
    let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
    watcher.completeExpectedStop(expectedStop, at: completedAt)

    let provisional = watcher.events(in: [
      snapshot(
        display: display, readAt: completedAt.addingTimeInterval(29),
        stateReadAt: completedAt.addingTimeInterval(31))
    ])
    let stopped = watcher.events(in: [
      snapshot(
        display: .resolved(.stopped),
        readAt: completedAt.addingTimeInterval(32))
    ])

    #expect(provisional.isEmpty)
    #expect(stopped.isEmpty)
  }
}

@Test func anUncertainStopUsesLocalProbeTimeForItsCompletionGrace() {
  // A timed-out command has the same local grace boundary. The remote answer
  // crossing that deadline cannot announce a disconnection; once a new local
  // probe itself reaches the deadline, uncertain intent expires as before.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  var watcher = FleetWatcher(expectedStopLifetime: 30)
  let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(
    expectedStop, outcome: .stopUncertain, at: completedAt)

  let provisional = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(29),
      stateReadAt: completedAt.addingTimeInterval(31))
  ])
  let expired = watcher.events(in: [
    snapshot(
      display: .resolved(.stopped),
      readAt: completedAt.addingTimeInterval(32))
  ])

  #expect(provisional.isEmpty)
  #expect(expired == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func nonStoppedReadingsAtTheCompletionGraceDeadlineSpendTheOrderedStop() {
  // The grace is bounded. Once its horizon is reached, a conclusive running
  // state resolves the old intent so a later crash cannot inherit silence.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  for display in [
    DisplayState.resolved(.idle),
    .resolved(.busy),
    .resolved(.disconnected),
    .resolved(.unknown(.noAnswer)),
  ] {
    var watcher = FleetWatcher(expectedStopLifetime: 30)
    let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
    _ = watcher.events(in: [runner])
    let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
    watcher.completeExpectedStop(expectedStop, at: completedAt)

    _ = watcher.events(in: [
      snapshot(
        display: display, readAt: completedAt.addingTimeInterval(30),
        stateReadAt: completedAt.addingTimeInterval(30))
    ])
    let crash = watcher.events(in: [
      snapshot(
        display: .resolved(.stopped),
        readAt: completedAt.addingTimeInterval(31))
    ])

    #expect(crash == [.runnerStoppedUnexpectedly(runner: "build-mac")])
  }
}

@Test func cancellingDuringTheCompletionGraceReplaysItsDisconnection() {
  // Definite failure revokes the only reason to defer this transition. The
  // provisional reading must not have advanced the baseline while intent was
  // present, or the same disconnection cannot be recovered after cancellation.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  var watcher = FleetWatcher(expectedStopLifetime: 30)
  let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(expectedStop, at: completedAt)

  let provisional = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(1),
      stateReadAt: completedAt.addingTimeInterval(2))
  ])
  watcher.cancelExpectedStop(expectedStop)
  _ = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(3),
      stateReadAt: completedAt.addingTimeInterval(4))
  ])
  let recovered = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(33),
      stateReadAt: completedAt.addingTimeInterval(34))
  ])

  #expect(provisional.isEmpty)
  #expect(recovered == [.runnerDisconnected(runner: "build-mac")])
}

@Test func aRemoteDisconnectionReadBeforeTheClickIsVisibleDuringTheGrace() {
  // A late apply does not make an old remote answer part of Stop. Suppressing
  // solely because its timestamp precedes the grace deadline would hide a real
  // transition that GitHub had already reported before the click.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  var watcher = FleetWatcher(expectedStopLifetime: 30)
  let runner = snapshot(readAt: requestedAt.addingTimeInterval(-2))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(expectedStop, at: completedAt)

  _ = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(-1),
      stateReadAt: requestedAt.addingTimeInterval(-0.5))
  ])
  // Still down once the Stop grace has passed: the clock started at the
  // pre-click answer, so thirty seconds have gone by.
  let events = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(31),
      stateReadAt: completedAt.addingTimeInterval(31))
  ])

  #expect(events == [.runnerDisconnected(runner: "build-mac")])
}

@Test func aRunnerMidHandshakeIsNotCalledDisconnected() {
  // `.starting` is the settling window covering for a runner that GitHub has
  // not acknowledged yet. Underneath it the resolver is saying `.disconnected`,
  // which is precisely the reading the window exists not to believe — and this
  // reads the display the menu shows, so it cannot believe it either.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  let events = watcher.events(in: [snapshot(display: .starting)])

  #expect(events.isEmpty)
}

@Test func thisAppFailingToReadTheMachineIsNotTheMachineFailing() {
  // No `gh`, no credentials, no network, no answer from `launchctl`. Every one
  // of them means this app cannot tell, and a banner saying a runner is down
  // when what happened is that somebody's wifi dropped is worse than silence.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])

  for reason in [
    UnknownReason.cliUnavailable, .notAuthenticated, .noAnswer, .serviceStateUnreadable,
    .tokenRefused, .tokenUnreadable,
  ] {
    #expect(watcher.events(in: [snapshot(display: .resolved(.unknown(reason)))]).isEmpty)
  }
}

@Test func aReadingThatSaidNothingDoesNotMakeAnOldDisconnectionNews() {
  // Down for an hour, then one scan where nothing answered: dropped wifi, a
  // spent rate limit, a laptop just woken. The runner did not change, only
  // this app's view of it.
  for gap in [
    UnknownReason.noAnswer, .rateLimited, .serviceStateUnreadable,
    .managedFleetStatusUnavailable,
  ] {
    var watcher = FleetWatcher()
    var announced: [FleetEvent] = []
    for second in [0.0, 30, 60] {
      announced += watcher.events(in: [reading(.resolved(.disconnected), at: second)])
    }
    #expect(announced.count == 1)

    var after = watcher.events(in: [reading(.resolved(.unknown(gap)), at: 75)])
    for second in [90.0, 120, 150] {
      after += watcher.events(in: [reading(.resolved(.disconnected), at: second)])
    }

    #expect(after.isEmpty, "after \(gap)")
  }
}

@Test func oneUnreadableLaunchctlDoesNotTurnAStoppedRunnerIntoACrash() {
  // Stopped on purpose hours ago. A `launchctl list` that timed out says
  // nothing about the service, so the stopped reading behind it is the same
  // stopped as before, not a runner that has just gone down on its own.
  var watcher = FleetWatcher()
  #expect(watcher.events(in: [reading(.resolved(.stopped), at: 0)]).isEmpty)

  let unreadable = watcher.events(in: [
    reading(.resolved(.unknown(.serviceStateUnreadable)), at: 15)
  ])
  let stopped = watcher.events(in: [reading(.resolved(.stopped), at: 30)])

  #expect(unreadable.isEmpty)
  #expect(stopped.isEmpty)
}

@Test func aRunnerStartedBehindASilentGitHubCanStillBeSeenToStop() {
  // The other side of that line. A GitHub-side unknown is only reached after
  // launchd answered "running", so it does say the stopped runner came back,
  // from a terminal say, and the stop after it is a new one.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.stopped), at: 0)])
  #expect(watcher.events(in: [reading(.resolved(.unknown(.noAnswer)), at: 15)]).isEmpty)

  let events = watcher.events(in: [reading(.resolved(.stopped), at: 30)])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aRunnerFirstSeenThroughAnUnreadableLaunchctlIsStillBaselinedInSilence() {
  // Login, a slow `launchctl`, and a runner somebody stopped last week. The
  // first stopped reading this app manages is its first sight of the runner,
  // which is the stopped-at-launch case and not a crash.
  var watcher = FleetWatcher()
  #expect(
    watcher.events(in: [reading(.resolved(.unknown(.serviceStateUnreadable)), at: 0)])
      .isEmpty)
  #expect(watcher.events(in: [reading(.resolved(.stopped), at: 15)]).isEmpty)

  // Once it has been seen up, going down is news again.
  #expect(watcher.events(in: [reading(.resolved(.idle), at: 30)]).isEmpty)
  let events = watcher.events(in: [reading(.resolved(.stopped), at: 45)])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

// MARK: - A runner paused in GitLab

@Test func aRunnerPausedInGitLabIsNotAnnouncedHoweverLongItStaysPaused() {
  // Pausing is how somebody drains a GitLab runner. GitLab answered that it is
  // paused, so there is nothing to announce going in, staying, or coming back.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.idle), at: 0)])

  var events: [FleetEvent] = []
  for second in stride(from: 15.0, through: 120, by: 15) {
    events += watcher.events(in: [
      reading(.resolved(.unknown(.gitLabPaused)), at: second)
    ])
  }
  events += watcher.events(in: [reading(.resolved(.idle), at: 135)])

  #expect(events.isEmpty)
}

@Test func aRunnerAlreadyPausedAtLaunchIsNotAnnounced() {
  // D-R19 owes one banner for a runner that is down when the app opens. A
  // paused one is not down, and the banner would come back at every login for
  // as long as it stays paused.
  var watcher = FleetWatcher()

  var events: [FleetEvent] = []
  for second in stride(from: 0.0, through: 120, by: 15) {
    events += watcher.events(in: [
      reading(.resolved(.unknown(.gitLabPaused)), at: second)
    ])
  }

  #expect(events.isEmpty)
}

@Test func aPauseDoesNotMakeAnOldDisconnectionNews() {
  // A release that reports "paused" in place of contact says nothing about
  // whether the runner reconnected in between, so the disconnection after the
  // pause may be the one already announced.
  var watcher = FleetWatcher()
  var announced: [FleetEvent] = []
  for second in [0.0, 30, 60] {
    announced += watcher.events(in: [reading(.resolved(.disconnected), at: second)])
  }
  #expect(announced.count == 1)

  var after = watcher.events(in: [reading(.resolved(.unknown(.gitLabPaused)), at: 75)])
  for second in [90.0, 120, 150] {
    after += watcher.events(in: [reading(.resolved(.disconnected), at: second)])
  }

  #expect(after.isEmpty)
}

@Test func aRunnerStartedWhilePausedInGitLabCanStillBeSeenToStop() {
  // GitLab is only asked once the service answered "running", so a paused
  // reading after a stopped one says the runner came back, and the stop after
  // it is a new one.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.stopped), at: 0)])
  #expect(
    watcher.events(in: [reading(.resolved(.unknown(.gitLabPaused)), at: 15)]).isEmpty)

  let events = watcher.events(in: [reading(.resolved(.stopped), at: 30)])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

// MARK: - Who stopped the runner

@Test func aRunnerThatGoesDownOnItsOwnIsReported() {
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])

  let events = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aStopThisAppOrderedIsNotReportedBackToWhoeverOrderedIt() {
  // The distinction the whole case turns on. There is nothing in `launchctl`
  // that says who stopped a service, and guessing from timing would make a slow
  // machine look like a crashed one — so the one piece of evidence is that this
  // app saw the click.
  var watcher = FleetWatcher()
  let runner = snapshot()
  _ = watcher.events(in: [runner])

  watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  let events = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  #expect(events.isEmpty)
}

@Test func aScanReadBeforeTheClickCannotSpendTheExpectedStop() {
  // A slow scan can start before Stop is pressed and land afterward. Its
  // answer is older than the click, so seeing the runner up in that answer
  // cannot prove the ordered stop has already been and gone.
  let beforeClick = Date(timeIntervalSince1970: 100)
  let clickedAt = Date(timeIntervalSince1970: 200)
  let afterClick = Date(timeIntervalSince1970: 260)
  var watcher = FleetWatcher()
  let runner = snapshot(readAt: beforeClick.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])

  let expectedStop = watcher.expectStop(for: runner.runner.label, at: clickedAt)
  #expect(
    watcher.events(in: [snapshot(display: .resolved(.busy), readAt: beforeClick)]).isEmpty)
  watcher.completeExpectedStop(
    expectedStop, at: clickedAt.addingTimeInterval(50))

  let events = watcher.events(in: [
    snapshot(display: .resolved(.stopped), readAt: afterClick)
  ])
  #expect(events.isEmpty)
}

@Test func aStoppedScanReadBeforeTheClickIsStillUnexpected() {
  // The same ordering at the stop branch: a stale answer cannot be attributed
  // to a click that had not happened when the machine was read.
  let beforeClick = Date(timeIntervalSince1970: 100)
  let clickedAt = Date(timeIntervalSince1970: 200)
  var watcher = FleetWatcher()
  let runner = snapshot(readAt: beforeClick.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])

  watcher.expectStop(for: runner.runner.label, at: clickedAt)
  let events = watcher.events(in: [
    snapshot(display: .resolved(.stopped), readAt: beforeClick)
  ])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func theNextStopAfterAnOrderedOneIsReportedAgain() {
  // The token is spent by the stop it was taken out for. Leaving it behind
  // would mean that stopping a runner once buys silence over every crash it
  // ever has afterwards.
  var watcher = FleetWatcher()
  let runner = snapshot()
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  watcher.completeExpectedStop(expectedStop, at: runner.readAt)
  #expect(watcher.events(in: [snapshot(display: .resolved(.stopped))]).isEmpty)
  #expect(watcher.events(in: [snapshot(display: .resolved(.idle))]).isEmpty)

  let events = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aRestartStartingPresentationSettlesACompletedStopIntent() {
  // Restart's settling window turns its post-start disconnection into
  // `.starting`. That presentation means the stop half has already been and
  // gone, so it must keep spending its token immediately rather than granting
  // the next real crash the Stop grace.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  var watcher = FleetWatcher()
  let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(
    for: runner.runner.label, action: .restart, at: requestedAt)
  watcher.completeExpectedStop(expectedStop, at: completedAt)

  _ = watcher.events(in: [snapshot(display: .starting, readAt: completedAt)])
  let crash = watcher.events(in: [
    snapshot(display: .resolved(.stopped), readAt: completedAt.addingTimeInterval(1))
  ])

  #expect(crash == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aLaterSuccessfulRestartSupersedesAnEarlierExpectedStop() {
  // Once a newer action succeeds, its evidence is the authoritative reason
  // for the next stop. Spending that restart intent must not reveal an older
  // completed Stop token that can silence a subsequent crash.
  let firstRequestedAt = Date(timeIntervalSince1970: 100)
  let firstCompletedAt = Date(timeIntervalSince1970: 101)
  let secondRequestedAt = Date(timeIntervalSince1970: 102)
  let secondCompletedAt = Date(timeIntervalSince1970: 103)
  var watcher = FleetWatcher()
  let runner = snapshot(readAt: firstRequestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])

  let first = watcher.expectStop(for: runner.runner.label, at: firstRequestedAt)
  watcher.completeExpectedStop(first, at: firstCompletedAt)
  let second = watcher.expectStop(
    for: runner.runner.label, action: .restart, at: secondRequestedAt)
  watcher.completeExpectedStop(second, at: secondCompletedAt)

  _ = watcher.events(in: [
    snapshot(display: .starting, readAt: secondCompletedAt)
  ])
  let crash = watcher.events(in: [
    snapshot(
      display: .resolved(.stopped),
      readAt: secondCompletedAt.addingTimeInterval(1))
  ])

  #expect(crash == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func stoppingARunnerThatWasAlreadyStoppedStillSpendsTheToken() {
  // Nothing stops a user pressing Stop on a runner that is already down. No
  // transition follows, so nothing is reported either way — and the token must
  // not survive to swallow a real crash later.
  var watcher = FleetWatcher()
  let runner = snapshot(display: .resolved(.stopped))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  watcher.completeExpectedStop(expectedStop, at: runner.readAt)
  #expect(watcher.events(in: [snapshot(display: .resolved(.stopped))]).isEmpty)

  #expect(watcher.events(in: [snapshot(display: .resolved(.idle))]).isEmpty)
  let events = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aRunnerStoppedOnPurposeAndThenCrashingIsStillReported() {
  // The token has to be spent by the stop it was taken out for, and not merely
  // read. Left in place it would sit there until the runner next came fully up
  // — and a runner brought back by hand goes through `.disconnected` on its way,
  // which is not "up". The next real crash would pass in silence.
  var watcher = FleetWatcher()
  let runner = snapshot()
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  watcher.completeExpectedStop(expectedStop, at: runner.readAt)
  #expect(watcher.events(in: [snapshot(display: .resolved(.stopped))]).isEmpty)

  // Started again from a terminal; GitHub has not registered it yet.
  #expect(watcher.events(in: [snapshot(display: .resolved(.disconnected))]).isEmpty)
  let events = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aConfirmedStopWaitsForItsFirstObservationWithoutExpiring() {
  // svc.sh returned success, so the stop is not a guess with a deadline. A
  // slow fleet scan may reach this runner well after thirty seconds; its first
  // stopped observation still belongs to the confirmed command.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  var watcher = FleetWatcher(expectedStopLifetime: 10)
  let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(expectedStop, at: completedAt)

  let orderedStop = watcher.events(in: [
    snapshot(display: .resolved(.stopped), readAt: completedAt.addingTimeInterval(100))
  ])
  #expect(orderedStop.isEmpty)

  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])
  let laterCrash = watcher.events(in: [snapshot(display: .resolved(.stopped))])
  #expect(laterCrash == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func anUncertainStopIntentExpiresBeforeAFutureCrash() {
  // A timeout may have stopped the service, so its immediate observation is
  // suppressed. It may not buy silence forever when only inconclusive states
  // arrive; the first stopped transition at the deadline is a new crash.
  let requestedAt = Date(timeIntervalSince1970: 100)
  let completedAt = Date(timeIntervalSince1970: 101)
  var watcher = FleetWatcher(expectedStopLifetime: 10)
  let runner = snapshot(readAt: requestedAt.addingTimeInterval(-1))
  _ = watcher.events(in: [runner])
  let expectedStop = watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(
    expectedStop, outcome: .stopUncertain, at: completedAt)

  _ = watcher.events(in: [
    snapshot(
      display: .resolved(.unknown(.serviceStateUnreadable)),
      readAt: completedAt.addingTimeInterval(5))
  ])
  let events = watcher.events(in: [
    snapshot(display: .resolved(.stopped), readAt: completedAt.addingTimeInterval(10))
  ])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func aRunnerThatLeavesTheMachineTakesItsBaselineWithIt() {
  // The same sweep the settling window and the log readers get. A runner
  // uninstalled and reinstalled inside one session is new to this app again,
  // and comparing it against how it looked before would report its whole log.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])

  watcher.keepOnly([])
  let events = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      jobs: history([job("testflight", at: 1_785_960_000, result: .failed)]))
  ])

  #expect(events.isEmpty)
}

@Test func anUninstalledRunnerDoesNotLeaveAnExpectedStopBehindEither() {
  // A Stop pressed on a runner that is then uninstalled would otherwise leave a
  // token that the reinstalled runner inherits, and its first real crash would
  // pass unreported.
  var watcher = FleetWatcher()
  let runner = snapshot()
  _ = watcher.events(in: [runner])
  watcher.expectStop(for: runner.runner.label, at: runner.readAt)

  watcher.keepOnly([])
  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])
  let events = watcher.events(in: [snapshot(display: .resolved(.stopped))])

  #expect(events == [.runnerStoppedUnexpectedly(runner: "build-mac")])
}

@Test func oneRunnerGoingDownSaysNothingAboutTheOtherOne() {
  // Everything here is per runner, the same rule the buttons follow. A watcher
  // keyed on anything but the runner's own label would report the wrong machine
  // — and on a Mac with two runners the name in the banner is the only part
  // that decides what to do next.
  var watcher = FleetWatcher()
  func scan(at second: TimeInterval, release: DisplayState) -> [RunnerSnapshot] {
    let at = launch.addingTimeInterval(second)
    return [
      snapshot("build-mac", scope: "widget", readAt: at, stateReadAt: at),
      snapshot(
        "release-mac", scope: "gadget", display: release, readAt: at, stateReadAt: at),
    ]
  }
  _ = watcher.events(in: scan(at: 0, release: .resolved(.idle)))
  _ = watcher.events(in: scan(at: 15, release: .resolved(.disconnected)))

  let events = watcher.events(in: scan(at: 45, release: .resolved(.disconnected)))

  #expect(events == [.runnerDisconnected(runner: "release-mac")])
}

// MARK: - What a banner says

@Test func everyEventCarriesBothTheTroubleAndTheRunnerItHappenedTo() {
  // A notification is read out of the corner of an eye. The title says what
  // went wrong and the body says where, and an event that lost the runner's
  // name is one the reader has to go and look up.
  let events: [FleetEvent] = [
    .jobFailed(runner: "mac-mini-m4", job: "testflight"),
    .runnerDisconnected(runner: "mac-mini-m4"),
    .runnerStoppedUnexpectedly(runner: "mac-mini-m4"),
  ]

  for event in events {
    #expect(!event.title.isEmpty)
    #expect(event.body.contains("mac-mini-m4"))
  }
  #expect(Set(events.map(\.title)).count == events.count)
  #expect(
    FleetEvent.jobFailed(runner: "mac-mini-m4", job: "testflight").body
      .contains("testflight"))
}

// MARK: - D-R19: a runner already down when the app opens

@Test func aRunnerAlreadyDisconnectedAtLaunchIsAnnouncedOnce() {
  // D-001, resolved 2026-08-16. Treating it as a silent baseline was coherent
  // with "only events while the app is watching", and it ignored the case that
  // matters: you log in, walk away, and never learn the runner was down.
  var watcher = FleetWatcher()

  var events: [FleetEvent] = []
  for second in stride(from: 0.0, through: 120, by: 15) {
    events += watcher.events(in: [reading(.resolved(.disconnected), at: second)])
  }

  #expect(events == [.runnerDisconnected(runner: "build-mac")])
}

@Test func theSameRunnerStillDownIsNotAnnouncedAgain() {
  // The half of the old rule that was right: a runner down for an hour is the
  // same fact every fifteen seconds, and a fact repeated 240 times is how
  // somebody ends up switching notifications off — including the one that
  // mattered.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 0)])
  _ = watcher.events(in: [reading(.resolved(.disconnected), at: 30)])

  let again = watcher.events(in: [reading(.resolved(.disconnected), at: 45)])

  #expect(again.isEmpty)
}

@Test func aHealthyRunnerAtLaunchStillAnnouncesNothing() {
  var watcher = FleetWatcher()

  #expect(watcher.events(in: [snapshot(display: .resolved(.idle))]).isEmpty)
}

@Test func aRunnerStoppedAtLaunchIsNotAnnounced() {
  // Stopped at launch is most likely somebody's own decision — maintenance, a
  // machine deliberately taken out of the pool. Only the silent failure gets
  // to interrupt: the service is up and GitHub cannot see it.
  var watcher = FleetWatcher()

  #expect(watcher.events(in: [snapshot(display: .resolved(.stopped))]).isEmpty)
}

@Test func aRunnerThatAppearsLaterIsStillBaselinedInSilence() {
  // One announcement per app launch, not per runner discovered. A runner
  // installed mid-session is new to this app, not new to the machine, and
  // whoever just installed it is looking at the screen.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [
    snapshot("first", display: .resolved(.idle), readAt: launch, stateReadAt: launch)
  ])

  var events: [FleetEvent] = []
  for second in [15.0, 45, 75] {
    let at = launch.addingTimeInterval(second)
    events += watcher.events(in: [
      snapshot("first", display: .resolved(.idle), readAt: at, stateReadAt: at),
      snapshot("second", display: .resolved(.disconnected), readAt: at, stateReadAt: at),
    ])
  }

  #expect(events.isEmpty)
}

@Test func theLaunchAnnouncementDoesNotDragTheJobHistoryWithIt() {
  // The rule that has not changed, and the reason the old one existed:
  // `_diag` reaches back about two days, so announcing what it found at launch
  // would report a build that broke on Tuesday, every morning at login.
  var watcher = FleetWatcher()
  let broken = history([
    job("testflight", at: 1_785_960_000, result: .failed),
    job("testflight", at: 1_785_950_000, result: .failed),
  ])

  var events: [FleetEvent] = []
  for second in [0.0, 30] {
    let at = launch.addingTimeInterval(second)
    events += watcher.events(in: [
      snapshot(
        display: .resolved(.disconnected), jobs: broken, readAt: at, stateReadAt: at)
    ])
  }

  #expect(events == [.runnerDisconnected(runner: "build-mac")])
  #expect(
    !events.contains { if case .jobFailed = $0 { return true } else { return false } })
}

// MARK: - INV-002: a timestamp is not an identity

@Test func aSecondFailureInTheSameSecondIsStillReported() {
  // The listener writes its timestamps to the second. Two jobs that both begin
  // inside one second — a job that fails on a missing secret before it has
  // done anything, followed straight away by the retry — share a `startedAt`,
  // and the watermark treated that instant as an identity: the walk stopped at
  // the first record "at or before the mark", which was the new failure
  // itself. Nobody was told about it.
  var watcher = FleetWatcher()
  let first = job("testflight", at: 1_785_960_000, result: .failed, took: 0)
  _ = watcher.events(in: [snapshot(jobs: history([first]))])

  let second = job("testflight", at: 1_785_960_000, result: .failed, took: 0)
  let events = watcher.events(
    in: [snapshot(jobs: JobHistory(records: [second, first], running: nil))])

  #expect(events == [.jobFailed(runner: "build-mac", job: "testflight")])
}

@Test func aFailureAlreadyAnnouncedIsNotAnnouncedAgainByItsTwin() {
  // The other half, and the one the watermark got right by accident: two
  // records sharing an instant must not make the older one new again on every
  // later scan.
  var watcher = FleetWatcher()
  let first = job("testflight", at: 1_785_960_000, result: .failed, took: 0)
  let second = job("testflight", at: 1_785_960_000, result: .failed, took: 0)
  _ = watcher.events(in: [snapshot(jobs: history([first]))])
  let both = JobHistory(records: [second, first], running: nil)
  _ = watcher.events(in: [snapshot(jobs: both)])

  #expect(watcher.events(in: [snapshot(jobs: both)]).isEmpty)
}

@Test func threeFailuresInOneSecondAreAnnouncedOnceEach() {
  var watcher = FleetWatcher()
  let a = job("a", at: 1_785_960_000, result: .failed, took: 0)
  _ = watcher.events(in: [snapshot(jobs: history([a]))])

  let b = job("b", at: 1_785_960_000, result: .failed, took: 0)
  let c = job("c", at: 1_785_960_000, result: .failed, took: 0)
  // Built in order rather than through `history()`: these records share a
  // sort key, and Swift's sort does not promise to leave equal elements
  // where it found them.
  let events = watcher.events(
    in: [snapshot(jobs: JobHistory(records: [c, b, a], running: nil))])

  // Oldest first, the order the walk reverses into.
  #expect(
    events == [
      .jobFailed(runner: "build-mac", job: "b"),
      .jobFailed(runner: "build-mac", job: "c"),
    ])
}
