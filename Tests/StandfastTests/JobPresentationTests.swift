import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let noon = Date(timeIntervalSince1970: 1_785_962_174)

private func record(
  _ name: String, ago: TimeInterval, lasting: TimeInterval?, _ result: JobResult? = nil
) -> JobRecord {
  let startedAt = noon.addingTimeInterval(-ago)
  return JobRecord(
    name: name, startedAt: startedAt,
    finishedAt: lasting.map { startedAt.addingTimeInterval($0) }, result: result)
}

private func running(
  _ name: String, forSeconds elapsed: TimeInterval, past: [JobRecord] = []
) -> JobHistory {
  let live = record(name, ago: elapsed, lasting: nil)
  return JobHistory(records: [live] + past, running: live)
}

/// Three identical successes, which is the least history an estimate is made
/// from.
private func threeGoodRuns(_ name: String, _ seconds: TimeInterval) -> [JobRecord] {
  (1...3).map { record(name, ago: 3600 * Double($0), lasting: seconds, .succeeded) }
}

private func snapshot(
  _ display: DisplayState, jobs: JobHistory = .empty, readAt: Date = noon
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac",
      directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "widget")),
    display: display, jobs: jobs, readAt: readAt)
}

// MARK: - The line over a running job

@Test func theRunningLineNamesTheJobAndHowLongItHasBeenGoing() {
  let progress = JobProgress.reading(
    running("testflight", forSeconds: 80, past: []), display: .resolved(.busy),
    at: noon)

  #expect(progress?.name == "testflight")
  #expect(progress?.elapsed == 80)
  #expect(progress?.line.contains("testflight") == true)
  #expect(progress?.line.contains(DurationText.precise(80)) == true)
}

@Test func theRunningLineSaysWhatTheJobUsuallyTakes() {
  let progress = JobProgress.reading(
    running("testflight", forSeconds: 80, past: threeGoodRuns("testflight", 170)),
    display: .resolved(.busy), at: noon)

  #expect(progress?.typical == 170)
  #expect(progress?.line.contains(DurationText.precise(80)) == true)
  #expect(progress?.line.contains(DurationText.precise(170)) == true)
}

@Test func withoutEnoughHistoryTheLineCarriesNoNumberItMadeUp() {
  // Two samples, which is one short. An estimate here would be the mean of two
  // runs printed as though it were knowledge.
  let past = Array(threeGoodRuns("testflight", 170).prefix(2))
  let progress = JobProgress.reading(
    running("testflight", forSeconds: 80, past: past), display: .resolved(.busy),
    at: noon)

  #expect(progress?.typical == nil)
  #expect(progress?.line.contains("testflight") == true)
  #expect(progress?.line.contains(DurationText.precise(80)) == true)
  #expect(progress?.line != JobProgress(name: "testflight", elapsed: 80, typical: 170).line)
}

@Test func aJobPastItsUsualTimeStillSaysWhatItsUsualTimeIs() {
  // Elapsed and a reference, never a countdown. "1m30s remaining" would have
  // gone negative here — and a job running twice as long as it should is
  // exactly when somebody looks at this.
  let progress = JobProgress.reading(
    running("testflight", forSeconds: 400, past: threeGoodRuns("testflight", 170)),
    display: .resolved(.busy), at: noon)

  #expect(progress?.line.contains(DurationText.precise(400)) == true)
  #expect(progress?.line.contains(DurationText.precise(170)) == true)
  #expect(progress?.line.contains("-") == false)
}

// MARK: - The log is not allowed to speak on its own

@Test func aLogSayingAJobIsRunningIsNotEnoughOnItsOwn() {
  // A listener killed mid-job leaves a start line no completion follows. Byte
  // for byte that is a job in progress, and believing it would leave "Running
  // testflight — 14h" over a machine that has been idle since breakfast.
  let history = running("testflight", forSeconds: 50_000, past: [])
  for state in [
    DisplayState.resolved(.idle), .resolved(.stopped), .resolved(.disconnected),
    .resolved(.unknown(.noAnswer)), .starting,
  ] {
    #expect(JobProgress.reading(history, display: state, at: noon) == nil)
  }
  // And with the one state that does mean work is happening, it appears.
  #expect(JobProgress.reading(history, display: .resolved(.busy), at: noon) != nil)
}

@Test func aBusyRunnerWithNoReadableLogSimplyHasNoProgressLine() {
  // `_diag` cleared out, a runner started by hand, a permissions problem. The
  // row still says the runner is busy; there is just nothing to add.
  #expect(JobProgress.reading(.empty, display: .resolved(.busy), at: noon) == nil)
}

// MARK: - Durations

@Test func aDurationReadsAsMinutesAndSeconds() {
  // The seconds are the whole signal: this runner does the same job in 2m45s
  // to 2m57s, and rounding to minutes would flatten every difference there is.
  #expect(DurationText.precise(167) == "2m 47s")
  #expect(DurationText.precise(17) == "17s")
  #expect(DurationText.precise(3720) == "1h 02m")
  #expect(DurationText.precise(60) == "1m 00s")
}

@Test func aClockThatWentBackwardsDoesNotPrintAMinusSign() {
  // An NTP correction or a manual change between a job starting and this being
  // asked. "-4s" in a menu bar is the app announcing it has lost the plot.
  #expect(DurationText.precise(-4) == "0s")
  #expect(DurationText.coarse(-4) == "0s")
}

@Test func howLongAgoIsRoundedAndADurationIsNot() {
  // Two different questions. "Checked 3m 07s ago" is precision nobody asked
  // for; "the job took 2m" throws away the only thing worth knowing.
  #expect(DurationText.coarse(187) == "3m")
  #expect(DurationText.coarse(7200) == "2h")
  #expect(DurationText.coarse(42) == "42s")
  #expect(DurationText.coarse(187) != DurationText.precise(187))
}

// MARK: - The history rows

@Test func aFinishedJobReadsAsItsNameItsResultAndItsTime() {
  let line = record("testflight", ago: 3600, lasting: 167, .succeeded).historyLine
  #expect(line.contains("testflight"))
  #expect(line.contains(L10n.jobSucceeded))
  #expect(line.contains("2m 47s"))
}

@Test func everyOutcomeHasAWordOfItsOwn() {
  let words = [JobResult.succeeded, .failed, .canceled].map {
    record("t", ago: 60, lasting: 10, $0).resultText
  }
  #expect(words == [L10n.jobSucceeded, L10n.jobFailed, L10n.jobCanceled])
  #expect(Set(words).count == 3)
}

@Test func anOutcomeThisVersionHasNeverMetIsShownAsGitHubWroteIt() {
  // Not translated and not folded into "failed": a word this app made up would
  // be a claim nobody checked.
  #expect(record("t", ago: 60, lasting: 10, .other("Abandoned")).resultText == "Abandoned")
}

@Test func aJobThatNeverFinishedSaysSoInsteadOfShowingNoTime() {
  // The listener went down with the job still running. It is the one outcome
  // that means the machine went wrong rather than the code, so it earns a word.
  let line = record("testflight", ago: 3600, lasting: nil).historyLine
  #expect(line.contains("testflight"))
  #expect(line.contains(L10n.jobInterrupted))
  #expect(!line.contains("("))
}

@Test func aJobRowKeepsOutcomeDurationAndTimeAsSeparateValues() {
  let startedAt = noon.addingTimeInterval(-3_600)
  let finishedAt = startedAt.addingTimeInterval(167)
  let subject = JobRow.building(
    JobRecord(
      name: "testflight", startedAt: startedAt, finishedAt: finishedAt,
      result: .succeeded), now: noon)

  #expect(subject.id == JobRow.ID(startedAt: startedAt, occurrence: 0))
  #expect(subject.name == "testflight")
  #expect(subject.startedAt == startedAt)
  #expect(subject.finishedAt == finishedAt)
  #expect(subject.duration == "2m 47s")
  #expect(subject.outcome.label == L10n.jobSucceeded)
  #expect(subject.outcome.symbolName == "checkmark.circle.fill")
  #expect(subject.outcome.tone == .healthy)
}

@Test func sameSecondJobRowsReceiveUniqueDeterministicOccurrences() {
  let startedAt = noon.addingTimeInterval(-3_600)
  let records = [
    JobRecord(
      name: "first", startedAt: startedAt,
      finishedAt: startedAt.addingTimeInterval(10), result: .succeeded),
    JobRecord(
      name: "second", startedAt: startedAt,
      finishedAt: startedAt.addingTimeInterval(20), result: .failed),
  ]

  let firstBuild = JobRow.building(records, now: noon)
  let secondBuild = JobRow.building(records, now: noon)

  #expect(firstBuild.map(\.id) == secondBuild.map(\.id))
  #expect(Set(firstBuild.map(\.id)).count == 2)
  #expect(firstBuild.map(\.id.occurrence) == [0, 1])
  // The duration left `text` and moved to `circumstances`, behind the age:
  // a bare parenthesis after an outcome was being read as "hace 10s".
  #expect(
    firstBuild.map(\.text) == [
      L10n.jobRowNoDuration("first", L10n.jobSucceeded),
      L10n.jobRowNoDuration("second", L10n.jobFailed),
    ])
  #expect(
    firstBuild.map(\.circumstances) == [
      L10n.jobAgeAndDuration(L10n.durationMinutes(59), "10s"),
      L10n.jobAgeAndDuration(L10n.durationMinutes(59), "20s"),
    ])
}

@Test func unrelatedNewerJobsDoNotRenumberExistingRows() {
  let sharedStart = noon.addingTimeInterval(-3_600)
  let sameSecond = [
    JobRecord(name: "first", startedAt: sharedStart, result: .succeeded),
    JobRecord(name: "second", startedAt: sharedStart, result: .failed),
  ]
  let before = JobRow.building(sameSecond, now: noon)
  let unrelated = JobRecord(
    name: "newer", startedAt: sharedStart.addingTimeInterval(60), result: .canceled)

  let after = JobRow.building([unrelated] + sameSecond, now: noon)

  #expect(Array(after.dropFirst()).map(\.id) == before.map(\.id))
}

@Test func everyJobOutcomeKeepsItsOwnSemanticPresentation() {
  let outcomes = [
    JobRow.building(record("ok", ago: 60, lasting: 10, .succeeded), now: noon).outcome,
    JobRow.building(record("bad", ago: 60, lasting: 10, .failed), now: noon).outcome,
    JobRow.building(record("cancel", ago: 60, lasting: 10, .canceled), now: noon).outcome,
    JobRow.building(record("lost", ago: 60, lasting: nil), now: noon).outcome,
    JobRow.building(record("new", ago: 60, lasting: 10, .other("Skipped")), now: noon)
      .outcome,
  ]

  #expect(
    outcomes.map(\.label) == [
      L10n.jobSucceeded, L10n.jobFailed, L10n.jobCanceled, L10n.jobInterrupted,
      "Skipped",
    ])
  #expect(
    outcomes.map(\.tone) == [
      .healthy, .attention, .neutral, .attention, .neutral,
    ])
  #expect(!outcomes.contains { $0.symbolName.isEmpty })
}

// MARK: - How much of it the menu shows

@Test func theHistoryStopsAtAHandfulOfRows() {
  // A menu bar menu that has to be scrolled has stopped being readable at a
  // glance, which is the only thing it is for.
  let many = (1...12).map {
    record("testflight", ago: 3600 * Double($0), lasting: 170, .succeeded)
  }
  let row = snapshot(.resolved(.idle), jobs: JobHistory(records: many)).row
  #expect(row.recentJobs.count == RunnerRow.recentJobsShown)
  #expect(row.recentJobs.count < many.count)
}

@Test func theRunningJobIsNotRepeatedInTheHistoryBelowIt() {
  // It already has a line of its own, with the one thing the history cannot
  // give it: how long it has been going.
  let history = running("testflight", forSeconds: 80, past: threeGoodRuns("t", 170))
  let row = snapshot(.resolved(.busy), jobs: history, readAt: noon).row

  #expect(row.progress?.contains("testflight") == true)
  #expect(row.recentJobs.count == 3)
  #expect(!row.recentJobs.contains { $0.text.contains("testflight") })
}

@Test func everyHistoryRowCanBeToldApartFromAnIdenticalOne() {
  // Two runs of the same job that took the same time render the same text, and
  // `ForEach` over repeated identifiers is undefined behaviour.
  let identical = (1...3).map {
    record("testflight", ago: 3600 * Double($0), lasting: 170, .succeeded)
  }
  let rows = snapshot(.resolved(.idle), jobs: JobHistory(records: identical)).row
    .recentJobs

  #expect(Set(rows.map(\.text)).count == 1)
  #expect(Set(rows.map(\.id)).count == 3)
}

@Test func aRunnerWithNoHistoryGetsNoSubmenu() {
  #expect(snapshot(.resolved(.idle)).row.recentJobs.isEmpty)
  #expect(snapshot(.resolved(.idle)).row.progress == nil)
}

// MARK: - When the machine was last read

@Test func aMenuThatHasNeverReadTheMachineSaysSo() {
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: nil, now: noon, isScanning: false, lastAttemptFailed: false)
      == L10n.checkedNever)
}

@Test func aFreshReadingSaysJustNowRatherThanCountingSeconds() {
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: noon.addingTimeInterval(-3), now: noon, isScanning: false,
      lastAttemptFailed: false)
      == L10n.checkedJustNow)
}

@Test func aScanInFlightSaysSoInsteadOfAgeingTheLastOne() {
  // A `gh` call has a 30s ceiling per runner, so pressing Refresh can leave
  // the operator watching an unchanged window for most of a minute. The line
  // that exists to say how old this reading is, is the honest place to say
  // that a newer one is on its way.
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: noon.addingTimeInterval(-245), now: noon, isScanning: true,
      lastAttemptFailed: false)
      == L10n.checkingRunners)
}

@Test func aFinishedScanGoesBackToReportingItsAge() {
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: noon.addingTimeInterval(-245), now: noon, isScanning: false,
      lastAttemptFailed: false)
      == L10n.checkedAgo("4m"))
}

@Test func aMachineNeverReadStillSaysSoWhileTheFirstScanRuns() {
  // "Checking" and "not checked yet" answer different questions, and the one
  // in flight is the one that will change.
  #expect(
    FleetStatus.lastCheckedLine(
      readAt: nil, now: noon, isScanning: true, lastAttemptFailed: false)
      == L10n.checkingRunners)
}

@Test func aStaleReadingSaysHowStale() {
  // The whole point of the line. A `gh` that hangs leaves the menu describing a
  // machine from four minutes ago, and this is what says so.
  let line = FleetStatus.lastCheckedLine(
    readAt: noon.addingTimeInterval(-245), now: noon, isScanning: false,
    lastAttemptFailed: false)
  #expect(line == L10n.checkedAgo("4m"))
  #expect(line != L10n.checkedJustNow)
}
