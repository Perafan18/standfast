import Foundation
import Testing

@testable import RunnerKit

/// One job, start to finish, as two lines in a listener log.
private func job(
  _ name: String, from start: String, to end: String, _ result: String = "Succeeded"
) -> [String] {
  [startedJob(name, at: start), finishedJob(name, result, at: end)]
}

// MARK: - Reading a log

@Test func readsWhatTheRunnerHasBeenDoing() throws {
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-173458",
    listenerChatter(at: "2026-08-05 17:34:58Z")
      + job("testflight", from: "2026-08-05 20:36:14Z", to: "2026-08-05 20:38:59Z")
      + job("lint", from: "2026-08-05 21:00:00Z", to: "2026-08-05 21:00:17Z", "Failed"))
  var reader = JobLogReader()

  let history = reader.read(diagnosticsIn: box.diagnostics)

  #expect(history.records.map(\.name) == ["lint", "testflight"])
  #expect(history.records.map(\.result) == [.failed, .succeeded])
  #expect(history.records.map(\.duration) == [17, 165])
  #expect(history.running == nil)
}

@Test func theJobWithNoResultYetIsTheOneRunningNow() throws {
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-173458",
    job("testflight", from: "2026-08-05 20:36:14Z", to: "2026-08-05 20:38:59Z")
      + [startedJob("testflight", at: "2026-08-05 21:54:53Z")])
  var reader = JobLogReader()

  let history = reader.read(diagnosticsIn: box.diagnostics)

  #expect(history.running?.name == "testflight")
  #expect(history.running?.startedAt == utcInstant("2026-08-05 21:54:53Z"))
  #expect(history.running == history.records.first)
}

@Test func anEmptyDirectoryIsAnEmptyHistoryRatherThanAFailure() throws {
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  var reader = JobLogReader()
  let empty = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(empty.history == .empty)
  #expect(empty.isAvailable)
  // And a `_diag` that is not there at all — a runner directory removed while
  // the app was running.
  let gone = reader.reading(
    diagnosticsIn: box.root.appendingPathComponent("gone"))
  #expect(gone.history == .empty)
  #expect(gone.isAvailable)
}

@Test func aListingFailurePreservesHistoryUntilAnEmptyDirectoryIsConfirmed() throws {
  // A failed listing is not evidence that the files disappeared. Park the real
  // directory and put a regular file at `_diag`: this makes
  // `contentsOfDirectory` fail deterministically without depending on the
  // account running the suite honoring chmod restrictions.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-173458",
    job("testflight", from: "2026-08-05 20:36:14Z", to: "2026-08-05 20:38:59Z"))
  var reader = JobLogReader()
  let initial = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(initial.history.records.map(\.name) == ["testflight"])
  #expect(initial.isAvailable)

  let parked = box.root.appendingPathComponent("_diag-parked")
  try FileManager.default.moveItem(at: box.diagnostics, to: parked)
  try Data("temporarily unavailable".utf8).write(to: box.diagnostics)

  let unavailable = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(unavailable.history.records.map(\.name) == ["testflight"])
  #expect(unavailable.history.records.map(\.result) == [.succeeded])
  #expect(!unavailable.isAvailable)
  #expect(reader.activeLog?.lastPathComponent == "Runner_20260805-173458-utc.log")

  // An actual, successfully listed empty directory is different evidence: the
  // logs really are gone, so stale history and its active-log pointer must go.
  try FileManager.default.removeItem(at: box.diagnostics)
  try FileManager.default.createDirectory(
    at: box.diagnostics, withIntermediateDirectories: true)
  let confirmedEmpty = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(confirmedEmpty.history == .empty)
  #expect(confirmedEmpty.isAvailable)
  #expect(reader.activeLog == nil)
}

@Test func anUnreadableHistoricalLogMakesAColdReadUnavailable() throws {
  // The active listener can be perfectly readable while an older log needed
  // to build the retained history is not. Installing a partial cold cache here
  // would both declare a false empty baseline and prevent that older log from
  // being retried on the next refresh.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let historical = box.diagnostics.appendingPathComponent(
    "Runner_20260805-000000-utc.log")
  try FileManager.default.createDirectory(
    at: historical, withIntermediateDirectories: true)
  _ = try box.writeLog(startedAt: "20260806-000000", [])
  var reader = JobLogReader()

  let unavailable = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(unavailable.history == .empty)
  #expect(!unavailable.isAvailable)
  #expect(reader.activeLog == nil)

  try FileManager.default.removeItem(at: historical)
  try box.writeLog(
    startedAt: "20260805-000000",
    job(
      "testflight", from: "2026-08-05 20:36:14Z", to: "2026-08-05 20:38:59Z",
      "Failed"))
  let recovered = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(recovered.isAvailable)
  #expect(recovered.history.records.map(\.name) == ["testflight"])
  #expect(recovered.history.records.map(\.result) == [.failed])
}

@Test func theWorkerLogsBesideItAreNeverOpened() throws {
  // They are ten times the size, there is one per job, and the only thing this
  // needs from them is nothing. A filter that matched `*.log` would multiply
  // the work by twenty and produce the same answer.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-173458",
    job("testflight", from: "2026-08-05 20:36:14Z", to: "2026-08-05 20:38:59Z"))
  try box.writeWorkerLog(
    startedAt: "20260805-203614",
    job("ghost", from: "2026-08-05 20:36:14Z", to: "2026-08-05 20:38:59Z"))
  var reader = JobLogReader()

  #expect(reader.read(diagnosticsIn: box.diagnostics).records.map(\.name) == ["testflight"])
}

// MARK: - Rotation

@Test func historyIsGatheredAcrossRotations() throws {
  // The listener opens a new log every time it starts, and a Mac that sleeps
  // and wakes rotates without running a single job. Reading only the newest
  // file would leave an empty history on exactly the machines that have one —
  // measured: on the runner this was built against, the newest two logs held
  // no jobs at all and the one before them held sixteen.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260804-155219",
    job("testflight", from: "2026-08-04 22:11:49Z", to: "2026-08-04 22:15:34Z"))
  try box.writeLog(
    startedAt: "20260805-233458", listenerChatter(at: "2026-08-05 23:34:58Z"))
  try box.writeLog(
    startedAt: "20260806-035225", listenerChatter(at: "2026-08-06 03:52:25Z"))
  var reader = JobLogReader()

  let history = reader.read(diagnosticsIn: box.diagnostics)

  #expect(history.records.map(\.name) == ["testflight"])
  #expect(history.running == nil)
}

@Test func theWalkBackwardsStopsAtEnoughJobsRatherThanAtEnoughFiles() throws {
  // Measured on a real runner, where a fixed count of four files was wrong:
  // it had rotated five times in two days, four of those without running
  // anything, and every one of its sixteen jobs sat in the fifth file back. The
  // menu showed one.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260804-155219",
    job("testflight", from: "2026-08-04 22:11:49Z", to: "2026-08-04 22:15:34Z")
      + job("testflight", from: "2026-08-04 22:35:33Z", to: "2026-08-04 22:38:08Z"))
  // Four restarts that ran nothing, which is what a Mac that sleeps and wakes
  // looks like from here.
  for start in ["20260805-233458", "20260805-233708", "20260806-025341", "20260806-035225"]
  {
    try box.writeLog(startedAt: start, listenerChatter(at: "2026-08-06 03:52:25Z"))
  }
  var reader = JobLogReader()

  #expect(reader.read(diagnosticsIn: box.diagnostics).records.count == 2)
}

@Test func aCompletionAtTheTopOfOneLogCannotCloseAJobLeftOpenInTheOneBefore()
  throws
{
  // Each listener log is a closed world: a job never spans two of them, because
  // the process that would have written the second line is the one that ended.
  // Folding them together hands the interrupted job hours of somebody else's
  // time — here, twelve of them.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-100000", [startedJob("testflight", at: "2026-08-05 10:00:00Z")])
  try box.writeLog(
    startedAt: "20260805-220000",
    [finishedJob("lint", "Succeeded", at: "2026-08-05 22:00:00Z")])
  try box.writeLog(
    startedAt: "20260806-035225", listenerChatter(at: "2026-08-06 03:52:25Z"))
  var reader = JobLogReader()

  let history = reader.read(diagnosticsIn: box.diagnostics)

  #expect(history.records.map(\.name) == ["testflight"])
  #expect(history.records.first?.duration == nil)
}

@Test func aJobCutShortByARotationIsNotStillRunning() throws {
  // The listener was killed mid-job, so no completion line was ever written.
  // Byte for byte that is what a job in progress looks like — and reading it as
  // one leaves "Running testflight" over a machine that rebooted last night.
  // The log it is in is the only thing that tells them apart.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-233458", [startedJob("testflight", at: "2026-08-05 23:40:00Z")])
  try box.writeLog(
    startedAt: "20260806-035225", listenerChatter(at: "2026-08-06 03:52:25Z"))
  var reader = JobLogReader()

  let history = reader.read(diagnosticsIn: box.diagnostics)

  #expect(history.records.map(\.name) == ["testflight"])
  // Still reported, and reported as unfinished: a job the machine dropped is
  // worth seeing.
  #expect(history.records.first?.result == nil)
  #expect(history.running == nil)
}

@Test func theActiveLogIsTheNewestByNameAndNotTheNewestByModificationDate() throws {
  // The name carries the UTC instant the listener started and is written once.
  // An mtime is rewritten by anything that touches the file — a backup restore
  // rewrites all of them — and picking the active log by mtime would make a
  // finished job start running again.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let old = try box.writeLog(
    startedAt: "20260805-233458", [startedJob("testflight", at: "2026-08-05 23:40:00Z")])
  try box.writeLog(
    startedAt: "20260806-035225", listenerChatter(at: "2026-08-06 03:52:25Z"))
  try FileManager.default.setAttributes(
    [.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: old.path)
  var reader = JobLogReader()

  #expect(reader.read(diagnosticsIn: box.diagnostics).running == nil)
}

@Test func aRotationAfterAReadIsPickedUp() throws {
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-233458",
    job("testflight", from: "2026-08-05 23:36:14Z", to: "2026-08-05 23:38:59Z"))
  var reader = JobLogReader()
  #expect(reader.read(diagnosticsIn: box.diagnostics).records.count == 1)

  try box.writeLog(
    startedAt: "20260806-035225", [startedJob("lint", at: "2026-08-06 03:55:00Z")])

  let history = reader.read(diagnosticsIn: box.diagnostics)
  #expect(history.records.map(\.name) == ["lint", "testflight"])
  #expect(history.running?.name == "lint")
}

// MARK: - Reading the delta and nothing else

@Test func anUnchangedLogIsNotReadASecondTime() throws {
  // The refresh runs every fifteen seconds for as long as the app is open and
  // `_diag` grows by about ten megabytes a day. Re-reading it each time is what
  // this type exists to avoid, and on a real runner an idle listener writes
  // nothing at all — so "same size" is the common case, not the lucky one.
  //
  // Asked by rewriting bytes the reader has already consumed. Nothing about the
  // history may change, because nothing may be read.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let log = try box.writeLog(
    startedAt: "20260805-233458",
    job("testflight", from: "2026-08-05 23:36:14Z", to: "2026-08-05 23:38:59Z"))
  var reader = JobLogReader()
  let first = reader.read(diagnosticsIn: box.diagnostics)
  #expect(first.records.map(\.name) == ["testflight"])

  let size = try #require(
    FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int)
  try box.overwrite(log, at: 0, with: String(repeating: "x", count: size - 1))

  #expect(reader.read(diagnosticsIn: box.diagnostics) == first)
}

@Test func onlyTheBytesAddedSinceLastTimeAreRead() throws {
  // The same question, with the file actually growing. What was consumed stays
  // consumed: a reader that re-read the whole file to pick up two new lines
  // would lose the job whose bytes have been replaced.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let log = try box.writeLog(
    startedAt: "20260805-233458",
    job("testflight", from: "2026-08-05 23:36:14Z", to: "2026-08-05 23:38:59Z"))
  var reader = JobLogReader()
  #expect(reader.read(diagnosticsIn: box.diagnostics).records.count == 1)

  let size = try #require(
    FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int)
  try box.overwrite(log, at: 0, with: String(repeating: "x", count: size - 1))
  try box.append(
    job("lint", from: "2026-08-06 00:00:00Z", to: "2026-08-06 00:00:17Z", "Failed")
      .map { $0 + "\n" }.joined(), to: log)

  let history = reader.read(diagnosticsIn: box.diagnostics)
  #expect(history.records.map(\.name) == ["lint", "testflight"])
  #expect(history.records.map(\.result) == [.failed, .succeeded])
}

@Test func aCompletionLandingAfterItsStartClosesTheRightJob() throws {
  // The two lines are minutes apart, so they arrive in different reads almost
  // every time: the job is started, the menu refreshes ten times, and only then
  // does the result appear.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let log = try box.writeLog(
    startedAt: "20260805-233458", [startedJob("testflight", at: "2026-08-05 23:36:14Z")])
  var reader = JobLogReader()
  #expect(reader.read(diagnosticsIn: box.diagnostics).running?.name == "testflight")

  try box.append(
    finishedJob("testflight", "Succeeded", at: "2026-08-05 23:38:59Z") + "\n", to: log)

  let history = reader.read(diagnosticsIn: box.diagnostics)
  #expect(history.running == nil)
  #expect(history.records.count == 1)
  #expect(history.records.first?.duration == 165)
}

@Test func aHalfWrittenLineIsNotReadUntilItIsWhole() throws {
  // The listener is writing while this reads, so the last line in the file is
  // routinely a fragment — and the read that catches it usually has whole lines
  // in front of it, which is why the fragment cannot simply be the reason to
  // give up on the batch.
  //
  // A fragment parsed is a job start seen as neither one thing nor the other:
  // `testfl` here. And once its bytes are counted as consumed, the rest of that
  // line never gets a second chance, so the real job never appears at all.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let log = try box.writeLog(
    startedAt: "20260805-233458", [startedJob("lint", at: "2026-08-05 23:34:58Z")])
  var reader = JobLogReader()
  #expect(reader.read(diagnosticsIn: box.diagnostics).running?.name == "lint")

  let line = startedJob("testflight", at: "2026-08-05 23:36:14Z")
  try box.append(
    finishedJob("lint", "Succeeded", at: "2026-08-05 23:35:15Z") + "\n"
      + String(line.dropLast(4)), to: log)

  // The whole line in front of the fragment lands; the fragment does not.
  let midWrite = reader.reading(diagnosticsIn: box.diagnostics)
  #expect(midWrite.isAvailable)
  #expect(midWrite.history.running == nil)
  #expect(midWrite.history.records.map(\.name) == ["lint"])

  try box.append(String(line.suffix(4)) + "\n", to: log)

  let complete = reader.read(diagnosticsIn: box.diagnostics)
  #expect(complete.running?.name == "testflight")
  #expect(complete.records.map(\.name) == ["testflight", "lint"])
}

// MARK: - Bounds

@Test func onlyTheMostRecentJobsAreKept() throws {
  // Every record is held for the life of the process, one per runner. A runner
  // that builds all day for a fortnight must not turn the menu into a ledger.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let runs = (0..<(JobLogReader.maxRecords + 8)).flatMap { index in
    job(
      "testflight", from: String(format: "2026-08-05 %02d:00:00Z", index % 24),
      to: String(format: "2026-08-05 %02d:02:45Z", index % 24))
  }
  try box.writeLog(startedAt: "20260805-000000", runs)
  var reader = JobLogReader()

  #expect(
    reader.read(diagnosticsIn: box.diagnostics).records.count
      == JobLogReader.maxRecords)
}

@Test func aLogTooBigToReadWholeIsReadFromItsEnd() throws {
  // The ceiling, and the only test that reaches the code path behind it. A
  // listener that has been up for a month has a log this must never slurp, so
  // a cold read starts half a megabyte from the end — which lands partway into
  // a line, and a half-line parsed is worse than one skipped.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let padding = (0..<4000).map {
    "[2026-08-05 12:00:00Z INFO Listener] " + String(repeating: "p", count: 120)
      + " \($0)"
  }
  try box.writeLog(
    startedAt: "20260805-000000",
    job("ancient", from: "2026-08-05 01:00:00Z", to: "2026-08-05 01:02:45Z")
      + padding
      + job("recent", from: "2026-08-05 20:00:00Z", to: "2026-08-05 20:02:45Z"))
  var reader = JobLogReader()

  let history = reader.read(diagnosticsIn: box.diagnostics)

  #expect(history.records.map(\.name) == ["recent"])
  #expect(history.records.first?.duration == 165)
  #expect(history.running == nil)
}

@Test func theLineTheCeilingCutsInHalfIsNotReadAsAJob() throws {
  // The other half of the ceiling, and the case it exists for. A window that
  // opens half a megabyte from the end opens partway into a line, and the tail
  // of a job start still holds everything the parser looks for: cut this one
  // five bytes in and `…WRITE LINE: …: Running job: phantom` reads perfectly.
  // The job would be real, its start time would be real, and it would be a job
  // that never started — a `phantom` row with no end, in a menu whose entire
  // premise is that it does not make things up.
  //
  // The arithmetic below puts the boundary exactly there, which is the only way
  // to reach this at all.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  let head = String(repeating: "y", count: 100) + "\n"
  let phantom = startedJob("phantom", at: "2026-08-05 03:00:00Z") + "\n"
  let real =
    job("recent", from: "2026-08-05 20:00:00Z", to: "2026-08-05 20:02:45Z")
    .map { $0 + "\n" }.joined()
  // Everything after `phantom` weighs exactly enough that the window opens five
  // bytes into it — past the `[`, and well before the `] WRITE LINE: ` the
  // parser anchors on.
  let cut = 5
  let tail = JobLogReader.tailWindow - phantom.utf8.count + cut
  let padding = String(repeating: "x", count: tail - real.utf8.count - 1) + "\n"
  let log = box.diagnostics.appendingPathComponent("Runner_20260805-000000-utc.log")
  try Data((head + phantom + padding + real).utf8).write(to: log)
  #expect(
    (try FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int)
      == head.utf8.count + JobLogReader.tailWindow + cut)
  var reader = JobLogReader()

  #expect(reader.read(diagnosticsIn: box.diagnostics).records.map(\.name) == ["recent"])
}

@Test func aCompletionWithNoStartInSightIsDropped() throws {
  // What the end of a truncated read looks like: the completion is inside the
  // window and the start that belongs to it is not. Inventing a record for it
  // would put a job of unknown name and unknowable duration in the menu.
  let box = try ListenerLogSandbox()
  defer { box.cleanUp() }
  try box.writeLog(
    startedAt: "20260805-233458",
    [finishedJob("testflight", "Succeeded", at: "2026-08-05 23:38:59Z")])
  var reader = JobLogReader()

  #expect(reader.read(diagnosticsIn: box.diagnostics).records.isEmpty)
}

@Test func onlyOneJobIsEverOpenAtATime() throws {
  // A self-hosted runner runs one job at a time, so a second start with the
  // first still open is a log this app has misread — and closing the wrong one
  // would hand a job the duration of another.
  let events: [JobLogEvent] = [
    .started(name: "a", at: utcInstant("2026-08-05 20:00:00Z")),
    .started(name: "b", at: utcInstant("2026-08-05 20:01:00Z")),
    .finished(result: .succeeded, at: utcInstant("2026-08-05 20:03:00Z")),
  ]
  let records = JobLogReader.fold(events, into: [])

  #expect(records.map(\.name) == ["a", "b"])
  #expect(records.map(\.duration) == [nil, 120])
}
