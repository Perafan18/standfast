import Foundation
import Testing

@testable import RunnerKit

// Everything here is pointed at a temporary tree. Nothing in this file may name
// a path a person owns, and the two tests that assert a refusal use a recording
// seam rather than the filesystem — "the directory is still there" is satisfied
// by a delete that failed as well as by one that never ran, and only one of
// those is this code working.

private let now = Date(timeIntervalSince1970: 1_785_962_174)

// MARK: - What is taken

@Test func deletingTheToolCacheTakesTheToolCacheAndNothingElse() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 8)
  try sandbox.makeWorkFolder("_actions", kilobytes: 1)
  try sandbox.makeWorkFolder("_temp")
  try sandbox.makeWorkFolder("nest-rules-app", kilobytes: 4)

  let outcome = try Housekeeper().blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { true })

  #expect(outcome == .done)
  // The repository checkout above all: it is the one directory here whose
  // contents are not a cache, and this app never offers to delete it.
  #expect(sandbox.names(in: sandbox.work) == ["_actions", "_temp", "nest-rules-app"])
}

@Test func theTrashIsNotLeftBehind() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_actions", kilobytes: 1)

  try Housekeeper().blockingClean(
    .actionCache, in: sandbox.runner, isStillSafe: { true })
  #expect(sandbox.names(in: sandbox.work).isEmpty)
}

@Test func aTrashLeftBehindByADeleteThatWasKilledIsSweptUp() throws {
  // The app can be quit — or crash — between the rename and the delete, and
  // what that leaves is four gigabytes in a hidden folder that nothing will
  // ever look at again. The next cleanup is the only thing that ever can.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)
  try sandbox.makeWorkFolder("\(Housekeeper.trashFolder)/leftover", kilobytes: 4)

  try Housekeeper().blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { true })
  #expect(sandbox.names(in: sandbox.work).isEmpty)
}

@Test func aCacheThatIsAlreadyGoneIsNotAFailureAndCostsNoProbe() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_actions")

  var probes = 0
  let outcome = try Housekeeper().blockingClean(.toolCache, in: sandbox.runner) {
    probes += 1
    return true
  }
  #expect(outcome == .nothingToDo)
  // The check is `launchctl` plus a call to GitHub. Spending one to find out
  // there was nothing to delete is a second or two of a menu going nowhere.
  #expect(probes == 0)
}

// MARK: - What is refused

@Test func aRunnerThatPickedUpWorkKeepsItsCache() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 4)

  let files = RecordingFileOperations()
  let outcome = try Housekeeper(files: files).blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { false })

  #expect(outcome == .refused)
  // Nothing was moved and nothing was removed. Creating the trash directory is
  // allowed to have happened — it is empty, it is preparation, and doing it
  // before the check is what makes the check the last thing before the rename.
  #expect(!files.calls.contains { $0.hasPrefix("move") })
  #expect(!files.calls.contains { $0.hasPrefix("remove") })
  #expect(sandbox.names(in: sandbox.work).contains("_tool"))
}

@Test func theCheckIsTheLastThingBeforeTheRename() throws {
  // The race this whole type is about. Between the check and the point of no
  // return there may be exactly one operation, and it has to be the rename:
  // anything else in there — creating a directory, listing one — is another
  // syscall's worth of window in which a job can start.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)

  let files = RecordingFileOperations()
  try Housekeeper(files: files).blockingClean(.toolCache, in: sandbox.runner) {
    files.note("checked")
    return true
  }

  let calls = files.calls
  let checked = try #require(calls.firstIndex(of: "checked"))
  #expect(calls[checked + 1] == "move _tool")
}

@Test func theCacheIsMovedAsideBeforeItIsTakenApart() throws {
  // Not deleted in place. `rm -rf` on four gigabytes takes seconds, and a job
  // that starts inside those seconds finds half a tool cache — a broken
  // toolchain and a failed build, where a missing one is only a slow build.
  // A rename is one atomic syscall and cannot be observed halfway.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)

  let files = RecordingFileOperations()
  try Housekeeper(files: files).blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { true })

  let moves = files.calls.filter { $0.hasPrefix("move") || $0.hasPrefix("remove") }
  // The removal names the grave the rename made, never `_tool` itself.
  #expect(moves.first == "move _tool")
  #expect(!moves.dropFirst().contains("remove _tool"))
}

@Test func aFilesystemThatSaysNoIsReportedRatherThanSwallowed() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)

  let files = RecordingFileOperations()
  files.failing = true
  #expect(throws: (any Error).self) {
    try Housekeeper(files: files).blockingClean(
      .toolCache, in: sandbox.runner, isStillSafe: { true })
  }
}

// MARK: - Rotation

@Test func rotationLeavesTheActiveLogAndTakesTheRest() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log", bytes: 4096,
    modified: now.addingTimeInterval(-30 * 24 * 3600))
  let active = try sandbox.makeLog("Runner_20260805-000000-utc.log", modified: now)

  let outcome = Housekeeper().blockingRotateDiagnostics(
    in: sandbox.runner, now: now, isStillSafe: { true })

  #expect(outcome == .done)
  #expect(!sandbox.exists(old))
  #expect(sandbox.exists(active))
}

@Test func rotationRefusesWhileTheRunnerIsWorkingToo() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log", modified: now.addingTimeInterval(-30 * 24 * 3600))

  let files = RecordingFileOperations()
  let outcome = Housekeeper(files: files).blockingRotateDiagnostics(
    in: sandbox.runner, now: now, isStillSafe: { false })

  #expect(outcome == .refused)
  #expect(files.calls.isEmpty)
  #expect(sandbox.exists(old))
}

@Test func aDiagWithNothingOldInItCostsNoProbeEither() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog("Runner_20260805-000000-utc.log", modified: now)

  var probes = 0
  let outcome = Housekeeper().blockingRotateDiagnostics(in: sandbox.runner, now: now) {
    probes += 1
    return true
  }
  #expect(outcome == .nothingToDo)
  #expect(probes == 0)
}

// MARK: - Who may be touched

@Test func onlyAnIdleOrStoppedRunnerMayBeTidiedUp() {
  #expect(RunnerState.idle.allowsHousekeeping)
  #expect(RunnerState.stopped.allowsHousekeeping)
  #expect(!RunnerState.busy.allowsHousekeeping)
  // The one that reads like "not working" and is not. GitHub describes a Mac
  // that dropped mid-job as offline with the job still assigned to it, which is
  // exactly a runner grinding through a build behind a dead connection.
  #expect(!RunnerState.disconnected.allowsHousekeeping)
  // And "I could not tell" is not a licence to delete four gigabytes.
  for reason in [
    UnknownReason.cliUnavailable, .notAuthenticated, .noAnswer, .serviceStateUnreadable,
  ] {
    #expect(!RunnerState.unknown(reason).allowsHousekeeping)
  }
}
