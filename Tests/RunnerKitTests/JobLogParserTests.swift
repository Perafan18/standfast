import Foundation
import Testing

@testable import RunnerKit

private func event(_ line: String) -> JobLogEvent? {
  JobLogParser.event(in: line[...])
}

// MARK: - The two lines that matter

@Test func readsTheJobNameAndTheInstantItStarted() {
  let line = startedJob("testflight", at: "2026-08-05 20:36:14Z")
  // The expected instant comes from Foundation, not from the parser: a reader
  // that read the fields correctly and then built the date in the host's time
  // zone would agree with itself all day.
  #expect(
    event(line) == .started(name: "testflight", at: utcInstant("2026-08-05 20:36:14Z")))
}

@Test func aTimestampIsReadAsUTCWhereverTheMacIs() {
  // The runner writes `Z` and means it. Reading it in the host's zone puts
  // every job hours out, and on the machine this was built on that would have
  // read as a six-hour-old job still running.
  let at = JobLogParser.timestamp("2026-08-05 20:36:14Z"[...])
  #expect(at == Date(timeIntervalSince1970: 1_785_962_174))
}

@Test func readsHowAJobEnded() {
  let stamp = "2026-08-05 20:38:59Z"
  #expect(
    event(finishedJob("testflight", "Succeeded", at: stamp))
      == .finished(result: .succeeded, at: utcInstant(stamp)))
  #expect(
    event(finishedJob("testflight", "Failed", at: stamp))
      == .finished(result: .failed, at: utcInstant(stamp)))
  #expect(
    event(finishedJob("testflight", "Canceled", at: stamp))
      == .finished(result: .canceled, at: utcInstant(stamp)))
}

@Test func anUnfamiliarResultIsKeptWholeRatherThanCalledAFailure() {
  // Three results have been seen on a real runner; the runner serialises an
  // enum case it is free to add to. `Abandoned` is not a failure and calling it
  // one would be this app inventing an outcome.
  #expect(
    event(finishedJob("deploy", "Abandoned", at: "2026-08-05 20:38:59Z"))
      == .finished(result: .other("Abandoned"), at: utcInstant("2026-08-05 20:38:59Z")))
}

// MARK: - Everything else in the file

@Test func ordinaryListenerChatterIsNotAJobEvent() {
  for line in listenerChatter(at: "2026-08-06 03:52:27Z") {
    #expect(event(line) == nil)
  }
  // Including the one terminal line with no timestamp of its own, which sits
  // directly above `Listening for Jobs` in every real log.
  #expect(
    event("[2026-08-06 03:52:27Z INFO Terminal] WRITE LINE: Current runner version:")
      == nil)
}

@Test func onlyTheRunnersOwnTerminalOutputCounts() {
  // `WRITE LINE:` is the runner echoing what it printed to the terminal, and it
  // is the only source read here. Every other component traces its own view of
  // the same job, and reading those too would double every job in the history
  // — the same build listed twice, each with its own duration.
  //
  // The line below is shaped so that only the anchor rejects it: it carries the
  // repeated timestamp and the words in the right order, and a parser that took
  // everything after the trace's closing bracket would read it as a job called
  // `ghost`.
  #expect(
    event(
      "[2026-08-05 20:36:14Z INFO JobDispatcher] "
        + "2026-08-05 20:36:14Z: Running job: ghost") == nil)
  #expect(
    event(
      "[2026-08-05 20:38:59Z INFO JobDispatcher] "
        + "2026-08-05 20:38:59Z: Job ghost completed with result: Succeeded") == nil)
}

@Test func aMalformedTimestampIsNotGuessedAt() {
  #expect(
    event("[x INFO Terminal] WRITE LINE: 2026-13-99 99:99:99Z: Running job: a") == nil)
  #expect(
    event("[x INFO Terminal] WRITE LINE: 2026-08-05 20:36:14: Running job: a") == nil)
  #expect(JobLogParser.timestamp("2026-08-05 20:36:1Z"[...]) == nil)
}

@Test func aStartWithNoJobNameIsNotAJob() {
  // A nameless row with a timer running next to it is worse than no row.
  #expect(event(startedJob("", at: "2026-08-05 20:36:14Z")) == nil)
}

// MARK: - Job names that look like the log

@Test func aJobNamedAfterTheCompletionLineStillReadsItsRealResult() {
  // Display names come from the workflow and are free text. Splitting on the
  // first match here would report this job as having succeeded.
  let line = finishedJob(
    "deploy completed with result: Succeeded", "Failed", at: "2026-08-05 20:38:59Z")
  #expect(
    event(line)
      == .finished(result: .failed, at: utcInstant("2026-08-05 20:38:59Z")))
}

@Test func aJobNamedAfterTheStartLineKeepsItsWholeName() {
  let line = startedJob("build: Running job: twice", at: "2026-08-05 20:36:14Z")
  #expect(
    event(line)
      == .started(
        name: "build: Running job: twice", at: utcInstant("2026-08-05 20:36:14Z")))
}
