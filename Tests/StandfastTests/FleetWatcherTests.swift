import Foundation
import RunnerKit
import Testing

@testable import Standfast

// MARK: - Nothing from before the app was watching

@Test func theFirstReadingOfARunnerAnnouncesNothingAtAll() {
  // The rule the whole feature stands on. `_diag` reaches back about two days,
  // so a failed build from Tuesday is sitting in the log the moment the app
  // opens — and announcing it would be a banner about something the user
  // already dealt with, arriving at login every single morning.
  var watcher = FleetWatcher()
  let broken = history([
    job("testflight", at: 1_785_960_000, result: .failed),
    job("testflight", at: 1_785_950_000, result: .failed),
  ])

  let events = watcher.events(in: [
    snapshot(display: .resolved(.disconnected), jobs: broken)
  ])

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
  _ = watcher.events(in: [
    snapshot(jobs: history([job("testflight", at: 1_785_950_000, result: .succeeded)]))
  ])

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

// MARK: - A runner GitHub cannot see

@Test func aRunnerFallingOffGitHubIsReportedOnce() {
  // The silent failure this app exists for: the process is up, the machine
  // looks fine, and no work ever arrives. Reported when it happens and not
  // again, because "still disconnected" every fifteen seconds is the same fact
  // 240 times an hour.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])

  let first = watcher.events(in: [snapshot(display: .resolved(.disconnected))])
  let second = watcher.events(in: [snapshot(display: .resolved(.disconnected))])

  #expect(first == [.runnerDisconnected(runner: "build-mac")])
  #expect(second.isEmpty)
}

@Test func aRunnerThatComesBackCanBeReportedAgainIfItGoesAgain() {
  // The other half of "only transitions": a flapping runner is a real problem,
  // and a watcher that reported a state once and never again would go quiet
  // exactly where the trouble is.
  var watcher = FleetWatcher()
  _ = watcher.events(in: [snapshot(display: .resolved(.idle))])
  #expect(watcher.events(in: [snapshot(display: .resolved(.disconnected))]).count == 1)
  #expect(watcher.events(in: [snapshot(display: .resolved(.idle))]).isEmpty)

  let again = watcher.events(in: [snapshot(display: .resolved(.disconnected))])

  #expect(again == [.runnerDisconnected(runner: "build-mac")])
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

  #expect(events.isEmpty)
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
  watcher.expectStop(for: runner.runner.label, at: requestedAt)
  _ = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(1))
  ])

  watcher.cancelExpectedStop(for: runner.runner.label)
  let events = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(2))
  ])

  #expect(events == [.runnerDisconnected(runner: "build-mac")])
}

@Test func nonStoppedReadingsInsideTheCompletionGracePreserveTheOrderedStop() {
  // launchd can lag behind svc.sh returning. Every conclusive running state
  // reached through a post-click observation is therefore provisional for a
  // bounded grace; the stopped reading behind it must still spend the token.
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
    watcher.expectStop(for: runner.runner.label, at: requestedAt)
    watcher.completeExpectedStop(for: runner.runner.label, at: completedAt)

    let provisional = watcher.events(in: [
      snapshot(
        display: display, readAt: completedAt.addingTimeInterval(1),
        stateReadAt: completedAt.addingTimeInterval(2))
    ])
    let stopped = watcher.events(in: [
      snapshot(
        display: .resolved(.stopped),
        readAt: completedAt.addingTimeInterval(3))
    ])

    #expect(provisional.isEmpty)
    #expect(stopped.isEmpty)
  }
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
    watcher.expectStop(for: runner.runner.label, at: requestedAt)
    watcher.completeExpectedStop(for: runner.runner.label, at: completedAt)

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
  watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: completedAt)

  let provisional = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(1),
      stateReadAt: completedAt.addingTimeInterval(2))
  ])
  watcher.cancelExpectedStop(for: runner.runner.label)
  let recovered = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: completedAt.addingTimeInterval(3),
      stateReadAt: completedAt.addingTimeInterval(4))
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
  watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: completedAt)

  let events = watcher.events(in: [
    snapshot(
      display: .resolved(.disconnected),
      readAt: requestedAt.addingTimeInterval(-1),
      stateReadAt: requestedAt.addingTimeInterval(-0.5))
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
  ] {
    #expect(watcher.events(in: [snapshot(display: .resolved(.unknown(reason)))]).isEmpty)
  }
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

  watcher.expectStop(for: runner.runner.label, at: clickedAt)
  #expect(
    watcher.events(in: [snapshot(display: .resolved(.busy), readAt: beforeClick)]).isEmpty)
  watcher.completeExpectedStop(
    for: runner.runner.label, at: clickedAt.addingTimeInterval(50))

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
  watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: runner.readAt)
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
  watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: completedAt)

  _ = watcher.events(in: [snapshot(display: .starting, readAt: completedAt)])
  let crash = watcher.events(in: [
    snapshot(display: .resolved(.stopped), readAt: completedAt.addingTimeInterval(1))
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
  watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: runner.readAt)
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
  watcher.expectStop(for: runner.runner.label, at: runner.readAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: runner.readAt)
  #expect(watcher.events(in: [snapshot(display: .resolved(.stopped))]).isEmpty)

  // Started again from a terminal; GitHub has not registered it yet.
  #expect(watcher.events(in: [snapshot(display: .resolved(.disconnected))]).count == 1)
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
  watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.completeExpectedStop(for: runner.runner.label, at: completedAt)

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
  watcher.expectStop(for: runner.runner.label, at: requestedAt)
  watcher.markExpectedStopUncertain(for: runner.runner.label, at: completedAt)

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
  let one = snapshot("build-mac", scope: "widget")
  let two = snapshot("release-mac", scope: "gadget")
  _ = watcher.events(in: [one, two])

  let events = watcher.events(in: [
    one, snapshot("release-mac", scope: "gadget", display: .resolved(.disconnected)),
  ])

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
