import Foundation
import Testing

@testable import RunnerKit

private let now = Date(timeIntervalSince1970: 1_785_962_174)
private let day: TimeInterval = 24 * 60 * 60

private func log(
  _ name: String, daysOld: Double, bytes: Int64 = 1024
) -> DiagnosticsFile {
  DiagnosticsFile(
    url: URL(fileURLWithPath: "/tmp/_diag/\(name)"),
    modifiedAt: now.addingTimeInterval(-daysOld * day), bytes: bytes)
}

// MARK: - What a sweep must never take

@Test func theLogTheListenerIsWritingToIsNeverSwept() {
  // The one file in `_diag` this app depends on. `JobLogReader` calls it
  // `logs.last`, holds an offset into it, and rebuilds the whole menu history
  // from it — and the runner has it open. Even asked for the most aggressive
  // sweep expressible, this has to leave it.
  let files = [
    log("Runner_20260101-000000-utc.log", daysOld: 400),
    log("Runner_20260102-000000-utc.log", daysOld: 399),
  ]
  let plan = DiagnosticsRotation.plan(
    files, retention: DiagnosticsRetention(keepFor: 0, listenerLogsKept: 0), now: now)
  #expect(!plan.doomed.contains(files[1].url))
  // And the older one is not spared with it: a floor of one is a floor, not a
  // reason to keep everything.
  #expect(plan.doomed == [files[0].url])
}

@Test func theHistoryTheMenuShowsSurvivesASweep() throws {
  // Twenty-five as a literal, deliberately not read off `retainedListenerLogs`.
  // A count built from the constant under test agrees with whatever that
  // constant says, including one, and one is exactly the value that leaves the
  // menu with a single log's worth of history after the next rotation.
  //
  // Each file a day older than the one before it, so "oldest first" below is a
  // claim about the order and not about whichever way `sorted` happened to
  // leave a run of equal dates.
  let files = (1...30).map {
    log(String(format: "Runner_202601%02d-000000-utc.log", $0), daysOld: Double(431 - $0))
  }
  let plan = DiagnosticsRotation.plan(files, retention: .standard, now: now)
  #expect(plan.count == 5)
  // The oldest five by name, which is the order the reader walks them in.
  #expect(plan.doomed == files.prefix(5).map(\.url))
}

@Test func theFloorIsAsFarBackAsTheJobHistoryCanReach() {
  // The literal, so that changing the reader's reach without changing the floor
  // fails here rather than in the menu a fortnight later. What the number *is*
  // is proved by `aRotationTheReaderCanStillWalkBackThroughKeepsItsJobs`, which
  // reads a real `_diag` on both sides of a sweep instead of restating the
  // arithmetic.
  #expect(DiagnosticsRetention.standard.listenerLogsKept == 25)
  // And only the literal. Restating it as `JobLogReader.maxFiles + 1` — or as
  // `retainedListenerLogs`, which this used to do — cannot fail on its own:
  // both sides evaluate to 25, so a floor that stopped tracking the reader and
  // became a copied constant satisfies either form. There is no runtime
  // assertion that tells a derivation from a coincidence, and a line that
  // cannot fail is worse than no line, because it reads like cover. What the
  // literal above does catch is the half that matters: moving the reader's
  // reach without moving the floor fails here rather than in the menu a
  // fortnight later.
}

@Test func aWorkerLogIsNotProtectedByTheListenerFloor() {
  // Which is the entire point of the sweep. On the machine this was measured
  // against, eight listener logs came to 0.45 MB and nineteen worker logs came
  // to 8.6 MB — so a floor that spared worker logs too would leave 95% of the
  // problem behind.
  let files = [
    log("Worker_20260101-000000-utc.log", daysOld: 400, bytes: 500_000),
    log("Runner_20260101-000000-utc.log", daysOld: 400),
  ]
  let plan = DiagnosticsRotation.plan(files, retention: .standard, now: now)
  #expect(plan.doomed == [files[0].url])
  #expect(plan.bytes == 500_000)
}

@Test func nothingWrittenThisWeekIsTouched() {
  let old = log("Worker_20260101-000000-utc.log", daysOld: 8)
  let recent = log("Worker_20260102-000000-utc.log", daysOld: 6)
  let plan = DiagnosticsRotation.plan([old, recent], retention: .standard, now: now)
  #expect(plan.doomed == [old.url])
}

@Test func aListenerThatHasBeenUpForAFortnightIsAgedByWhatItWrote() {
  // Its name says a fortnight ago, because the name is when the listener
  // started. Its mtime says a second ago, because it is the log that listener
  // is writing to. Ageing by the name would delete an open file the menu reads.
  let files = [
    log("Runner_20260101-000000-utc.log", daysOld: 0),
    log("Worker_20260120-000000-utc.log", daysOld: 30),
  ]
  let plan = DiagnosticsRotation.plan(
    files, retention: DiagnosticsRetention(keepFor: 7 * day, listenerLogsKept: 0),
    now: now)
  #expect(plan.doomed == [files[1].url])
}

@Test func aClockThatWentBackwardsDeletesNothing() {
  // An NTP correction, or a Mac restored from a backup with tomorrow's date on
  // its files. A negative age must not read as "older than a week".
  let future = log("Worker_20260101-000000-utc.log", daysOld: -30)
  let plan = DiagnosticsRotation.plan([future], retention: .standard, now: now)
  #expect(plan.isEmpty)
}

@Test func whatIsReportedIsWhatWouldGo() {
  // The number in the confirmation dialogue. It is the only thing the user has
  // to decide on, and it must be the sum of the files in the plan rather than
  // of everything looked at.
  let files = [
    log("Worker_20260101-000000-utc.log", daysOld: 400, bytes: 300),
    log("Worker_20260102-000000-utc.log", daysOld: 400, bytes: 700),
    log("Worker_20260103-000000-utc.log", daysOld: 1, bytes: 9_000_000),
  ]
  let plan = DiagnosticsRotation.plan(files, retention: .standard, now: now)
  #expect(plan.count == 2)
  #expect(plan.bytes == 1000)
}

// MARK: - The order a sweep goes in

@Test func logsWrittenAtTheSameInstantAreStillSweptInAFixedOrder() {
  // `doomed` promises oldest first, so that a sweep interrupted halfway has
  // done the useful half — and against equal dates `sorted(by:)` promises
  // nothing at all, because it is not stable. That is not a made-up directory:
  // a `_diag` copied or restored from a backup arrives with every modification
  // date set to the copy. The plan is `Equatable` and travels into `@Published`
  // state, where an order that reshuffles reads as a change.
  let tied = (1...20).map {
    log(String(format: "Worker_202601%02d-000000-utc.log", $0), daysOld: 400)
  }
  let retention = DiagnosticsRetention(keepFor: day, listenerLogsKept: 1)
  let once = DiagnosticsRotation.plan(tied, retention: retention, now: now)
  #expect(once.doomed == tied.map(\.url))
  // And the same answer for the same directory handed over in another order,
  // which is the only thing `contentsOfDirectory` ever promises.
  #expect(
    DiagnosticsRotation.plan(tied.reversed(), retention: retention, now: now) == once)
}

// MARK: - Holding a sweep to what was agreed to

@Test func aSweepCanBeHeldToTheFilesSomebodyWasShown() {
  // The confirmation names a count and a size taken from a measurement that
  // nothing expires, and the sweep decides what leaves against the clock at the
  // moment of the click. Those are two different sets, and the second is the
  // bigger one on any runner that keeps writing logs.
  let files = (1...6).map {
    log(String(format: "Worker_202601%02d-000000-utc.log", $0), daysOld: Double(407 - $0))
  }
  let agreed = Set(files.prefix(2).map(\.url))
  let plan = DiagnosticsRotation.plan(
    files, retention: DiagnosticsRetention(keepFor: day, listenerLogsKept: 1), now: now,
    limitedTo: agreed)

  #expect(plan.doomed == files.prefix(2).map(\.url))
  // Sized off this listing rather than off the older one, so the number is
  // exact and not merely smaller.
  #expect(plan.bytes == 2048)
}

@Test func agreementCannotSaveAFileThatHasBecomeTheActiveLog() {
  // The limit is a ceiling and never a floor. A listener that rotated between
  // the measurement and the click leaves the agreed plan naming a file the
  // runner now has open, and re-planning here is the only thing that catches
  // it.
  let files = [log("Runner_20260101-000000-utc.log", daysOld: 400)]
  let plan = DiagnosticsRotation.plan(
    files, retention: DiagnosticsRetention(keepFor: 0, listenerLogsKept: 0), now: now,
    limitedTo: Set(files.map(\.url)))
  #expect(plan.isEmpty)
}

// MARK: - What the listing sees

@Test func onlyLogFilesAreEverConsidered() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog("Runner_20260101-000000-utc.log", modified: now)
  try sandbox.makeLog("Worker_20260101-000000-utc.log", modified: now)
  // `_diag` also holds these two, which are the runner's own store rather than
  // logs. A sweep with no rule for them must not be the thing that decides.
  for folder in ["blocks", "pages"] {
    try FileManager.default.createDirectory(
      at: sandbox.diagnostics.appendingPathComponent(folder),
      withIntermediateDirectories: true)
  }
  try Data("{}".utf8).write(to: sandbox.diagnostics.appendingPathComponent("state.json"))
  // And one named like a log, which is what the extension filter alone cannot
  // keep out. Everything in a plan is handed to a recursive delete, so a
  // directory that got in would take whatever is under it — the one thing the
  // listing promises never to decide about.
  try FileManager.default.createDirectory(
    at: sandbox.diagnostics.appendingPathComponent("Runner_20260102-000000-utc.log"),
    withIntermediateDirectories: true)

  let listing = DiagnosticsFile.listing(in: sandbox.diagnostics)
  #expect(
    Set(listing.map(\.name)) == [
      "Runner_20260101-000000-utc.log", "Worker_20260101-000000-utc.log",
    ])
}

// MARK: - The reader on the other side of it

@Test func aSweptDiagStillTellsTheMenuTheSameHistory() throws {
  // The interaction this whole unit had to be careful about. `JobLogReader`
  // caches the active log and how far into it it has read; a sweep that took
  // the wrong file would leave the menu either short of jobs or reading from a
  // file that no longer exists.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let stamp = "2026-08-05 20:36:14Z"
  var written: [URL] = []
  for index in 1...3 {
    written.append(
      try sandbox.makeLog(
        String(format: "Runner_2026080%d-000000-utc.log", index),
        lines: listenerChatter(at: stamp) + [
          startedJob("build-\(index)", at: stamp),
          finishedJob("build-\(index)", "Succeeded", at: stamp),
        ],
        modified: now.addingTimeInterval(-400 * day)))
  }
  // Ancient worker logs beside them, which is where the megabytes are.
  let worker = try sandbox.makeLog(
    "Worker_20260801-000000-utc.log", bytes: 500_000,
    modified: now.addingTimeInterval(-400 * day))

  var reader = JobLogReader()
  let before = reader.read(diagnosticsIn: sandbox.diagnostics)
  #expect(before.records.map(\.name) == ["build-3", "build-2", "build-1"])

  let plan = Housekeeper.rotationPlan(
    for: sandbox.runner,
    // Every listener log here is older than the retention, so only the floor
    // stands between this sweep and the menu's history.
    retention: DiagnosticsRetention(keepFor: 7 * day, listenerLogsKept: 3), now: now)
  #expect(plan.doomed == [worker])

  Housekeeper().blockingRotateDiagnostics(
    in: sandbox.runner,
    retention: DiagnosticsRetention(keepFor: 7 * day, listenerLogsKept: 3), now: now,
    isStillSafe: { true })

  // Read again with the same reader a running app would still be holding, and
  // then with a fresh one, because a cache can hide a `_diag` that has been
  // gutted underneath it.
  #expect(reader.read(diagnosticsIn: sandbox.diagnostics).records == before.records)
  var cold = JobLogReader()
  #expect(cold.read(diagnosticsIn: sandbox.diagnostics).records == before.records)
  #expect(!sandbox.exists(worker))
  for url in written { #expect(sandbox.exists(url)) }
}

@Test func aRotationTheReaderCanStillWalkBackThroughKeepsItsJobs() throws {
  // The off-by-one this floor exists to avoid, written as the machine sees it
  // rather than as arithmetic. `JobLogReader` reads the active log and then
  // walks `maxFiles` further files back, so its reach is `maxFiles + 1` files —
  // and a floor one short takes the file the walk would have ended on.
  //
  // A laptop is what makes that ordinary rather than exotic: the listener opens
  // a new log every time it starts, so every sleep and wake rotates one without
  // running a single job, and twenty-five rotations go by long before twenty
  // jobs do. Here every job is in the oldest file and every file above it is a
  // rotation that did nothing, which is exactly that machine.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let stamp = "2026-08-05 20:36:14Z"
  let ancient = now.addingTimeInterval(-400 * day)
  for index in 1...(JobLogReader.maxFiles + 1) {
    let job =
      index == 1
      ? [startedJob("build", at: stamp), finishedJob("build", "Succeeded", at: stamp)]
      : []
    try sandbox.makeLog(
      String(format: "Runner_2026%04d-000000-utc.log", index),
      lines: listenerChatter(at: stamp) + job, modified: ancient)
  }
  // The megabytes a sweep is actually after, so that this one has something to
  // do and the assertion below is about what it left rather than about it
  // having declined to run.
  let worker = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log", bytes: 500_000, modified: ancient)

  var before = JobLogReader()
  #expect(before.read(diagnosticsIn: sandbox.diagnostics).records.map(\.name) == ["build"])

  let outcome = Housekeeper().blockingRotateDiagnostics(
    in: sandbox.runner, now: now, isStillSafe: { true })
  #expect(outcome == .done)
  #expect(!sandbox.exists(worker))

  var after = JobLogReader()
  // Nothing older than a week survived except the listener logs, and the one
  // job on this machine is still in the menu.
  #expect(after.read(diagnosticsIn: sandbox.diagnostics).records.map(\.name) == ["build"])
}

@Test func aSweepThatReachesTheListenerLogsCostsOnlyTheOldestJobs() throws {
  // What it looks like when the floor does bite. Keeping one listener log
  // leaves the menu the jobs in that log and no others — which is a shorter
  // history, and never a wrong one or an empty one.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let stamp = "2026-08-05 20:36:14Z"
  for index in 1...3 {
    try sandbox.makeLog(
      String(format: "Runner_2026080%d-000000-utc.log", index),
      lines: listenerChatter(at: stamp) + [
        startedJob("build-\(index)", at: stamp),
        finishedJob("build-\(index)", "Succeeded", at: stamp),
      ],
      modified: now.addingTimeInterval(-400 * day))
  }

  Housekeeper().blockingRotateDiagnostics(
    in: sandbox.runner,
    retention: DiagnosticsRetention(keepFor: 7 * day, listenerLogsKept: 1), now: now,
    isStillSafe: { true })

  var cold = JobLogReader()
  #expect(cold.read(diagnosticsIn: sandbox.diagnostics).records.map(\.name) == ["build-3"])
}
