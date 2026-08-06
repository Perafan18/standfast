import Foundation
import Testing

@testable import RunnerKit

/// Newest first, which is the order the reader hands back. Each run is placed
/// an hour apart so "most recent" means something without the durations having
/// to encode it.
private typealias Run = (name: String, seconds: TimeInterval, result: JobResult?)

private func history(_ runs: [Run]) -> JobHistory {
  let base = Date(timeIntervalSince1970: 1_785_962_174)
  let records = runs.enumerated().map { index, run in
    let startedAt = base.addingTimeInterval(-3600 * Double(index))
    return JobRecord(
      name: run.name, startedAt: startedAt,
      finishedAt: run.result == nil ? nil : startedAt.addingTimeInterval(run.seconds),
      result: run.result)
  }
  return JobHistory(records: records)
}

private func succeeded(_ name: String, _ seconds: TimeInterval) -> Run {
  (name, seconds, .succeeded)
}

// MARK: - What the estimate is

@Test func theEstimateIsTheMiddleOfTheSameJobsSuccessfulRuns() {
  let runs = history([
    succeeded("testflight", 165), succeeded("testflight", 175),
    succeeded("testflight", 170),
  ])
  #expect(runs.typicalDuration(ofJobNamed: "testflight") == 170)
}

@Test func anEvenNumberOfSamplesLandsBetweenTheMiddleTwo() {
  let runs = history([
    succeeded("t", 160), succeeded("t", 170), succeeded("t", 180),
    succeeded("t", 190),
  ])
  #expect(runs.typicalDuration(ofJobNamed: "t") == 175)
}

// MARK: - Why it is a median of successes and not a mean of everything

@Test func aRunCancelledAfterTenSecondsDoesNotDragTheEstimateDown() {
  // The measured shape, from a real runner: fourteen successes just under three
  // minutes, two cancellations and a failure that stopped at the first broken
  // step. A mean over all of them answers 107s for a job that takes 170 —
  // wrong by a minute, and wrong for every build after it.
  let runs = history([
    succeeded("testflight", 165), succeeded("testflight", 170),
    succeeded("testflight", 175),
    ("testflight", 10, .canceled), ("testflight", 17, .failed),
  ])

  #expect(runs.typicalDuration(ofJobNamed: "testflight") == 170)
  // Spelled out rather than left implied: this is the number the obvious
  // implementation gives, and the only thing separating the two.
  let everyRun: [TimeInterval] = [165, 170, 175, 10, 17]
  #expect(everyRun.reduce(0, +) / 5 != 170)
}

@Test func aJobStillRunningIsNotOneOfItsOwnSamples() {
  // It has no duration yet, and counting the elapsed time so far would make
  // every estimate a function of how long ago you opened the menu.
  let runs = history([
    ("testflight", 0, nil), succeeded("testflight", 170),
    succeeded("testflight", 170), succeeded("testflight", 170),
  ])
  #expect(runs.typicalDuration(ofJobNamed: "testflight") == 170)
}

// MARK: - Which runs count

@Test func onlyRunsOfTheSameJobCount() {
  // A Mac that builds an iOS app and lints a README has no meaningful average
  // job, and the average of the two is a number that describes neither.
  let runs = history([
    succeeded("testflight", 170), succeeded("testflight", 170),
    succeeded("testflight", 170), succeeded("lint", 4), succeeded("lint", 4),
    succeeded("lint", 4),
  ])
  #expect(runs.typicalDuration(ofJobNamed: "testflight") == 170)
  #expect(runs.typicalDuration(ofJobNamed: "lint") == 4)
}

@Test func aJobWithNoHistoryAtAllHasNoEstimate() {
  #expect(history([succeeded("t", 170)]).typicalDuration(ofJobNamed: "other") == nil)
}

@Test func onlyTheMostRecentRunsCount() {
  // A build gets slower as the project grows and faster the day somebody adds
  // a cache. Runs from before that change are evidence about a build that no
  // longer exists.
  let runs = history([
    succeeded("t", 100), succeeded("t", 110), succeeded("t", 120),
    succeeded("t", 130), succeeded("t", 140),
    succeeded("t", 10), succeeded("t", 10), succeeded("t", 10),
  ])
  #expect(runs.typicalDuration(ofJobNamed: "t") == 120)
  // What a median over the whole history would have said. Pinned so that
  // dropping the window is a failure rather than a slightly different number.
  #expect(runs.typicalDuration(ofJobNamed: "t") != 105)
}

// MARK: - When there is not enough to say

@Test func twoSamplesAreNotAnEstimate() {
  // The middle of two numbers is their mean, which is the statistic this is
  // here to avoid — and a "usually" built from two runs is a guess wearing a
  // number's clothes. Nothing is the honest answer.
  let runs = history([succeeded("t", 170), succeeded("t", 10)])
  #expect(runs.typicalDuration(ofJobNamed: "t") == nil)
}

@Test func threeSamplesAre() {
  // The other half of the same decision: the threshold has to let something
  // through, or the feature never appears.
  let runs = history([succeeded("t", 170), succeeded("t", 10), succeeded("t", 175)])
  #expect(runs.typicalDuration(ofJobNamed: "t") == 170)
}

@Test func aJobThatHasOnlyEverFailedHasNoEstimate() {
  // Its durations measure how early something broke, not how long the work
  // takes.
  let runs = history([
    ("t", 17, .failed), ("t", 12, .failed), ("t", 20, .failed),
    ("t", 15, .canceled),
  ])
  #expect(runs.typicalDuration(ofJobNamed: "t") == nil)
}

// MARK: - Results

@Test func theResultsARunnerWritesAreRecognised() {
  #expect(JobResult(logWord: "Succeeded") == .succeeded)
  #expect(JobResult(logWord: "Failed") == .failed)
  #expect(JobResult(logWord: "Canceled") == .canceled)
  // American spelling, which is what the runner writes. The British one would
  // silently become an unknown outcome.
  #expect(JobResult(logWord: "Cancelled") == .other("Cancelled"))
}

@Test func aRecordsDurationIsNilUntilItHasFinished() {
  let started = Date(timeIntervalSince1970: 1_785_962_174)
  #expect(JobRecord(name: "t", startedAt: started).duration == nil)
  #expect(
    JobRecord(
      name: "t", startedAt: started, finishedAt: started.addingTimeInterval(170),
      result: .succeeded
    ).duration == 170)
}
