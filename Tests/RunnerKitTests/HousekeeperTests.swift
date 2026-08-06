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

@Test func anOutsideTrashSymlinkIsRefusedBeforeItsContentsAreSwept() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)
  let foreign = try sandbox.makeOutsideFolder("keep", kilobytes: 4)
  let trash = sandbox.work.appendingPathComponent(Housekeeper.trashFolder)
  try FileManager.default.createSymbolicLink(at: trash, withDestinationURL: sandbox.outside)

  #expect(throws: HousekeepingFailure(directory: trash)) {
    try Housekeeper().blockingClean(
      .toolCache, in: sandbox.runner, isStillSafe: { true })
  }

  #expect(sandbox.exists(foreign.appendingPathComponent("payload")))
  #expect(sandbox.exists(sandbox.work.appendingPathComponent("_tool/payload")))
}

@Test func anInternalTrashSymlinkDoesNotMakeAnotherRunnerFolderOurs() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)
  let foreign = try sandbox.makeWorkFolder("foreign/keep", kilobytes: 4)
  let trash = sandbox.work.appendingPathComponent(Housekeeper.trashFolder)
  try FileManager.default.createSymbolicLink(
    at: trash, withDestinationURL: sandbox.work.appendingPathComponent("foreign"))

  #expect(throws: HousekeepingFailure(directory: trash)) {
    try Housekeeper().blockingClean(
      .toolCache, in: sandbox.runner, isStillSafe: { true })
  }

  #expect(sandbox.exists(foreign.appendingPathComponent("payload")))
  #expect(sandbox.exists(sandbox.work.appendingPathComponent("_tool/payload")))
}

@Test func aGraveIsSweptEvenWhenThereIsNothingLeftToClean() throws {
  // The state the test above cannot reach, and the one that does not heal
  // itself. Being killed between the rename and the delete leaves no `_tool`
  // either — but the next build puts one back, and the cleanup after that
  // sweeps the grave. A delete that *failed* has nothing coming to repopulate
  // anything: `_tool` is gone for good, so every later call would find nothing
  // to clean and return before it ever swept. The four gigabytes then read as
  // "Other runner files" in the breakdown with no button in the menu that can
  // reach them.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("\(Housekeeper.trashFolder)/leftover", kilobytes: 4)

  let outcome = try Housekeeper().blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { true })

  #expect(outcome == .nothingToDo)
  #expect(sandbox.names(in: sandbox.work).isEmpty)
}

@Test func aDeleteThatFailedHalfwayLeavesBytesTheNextOneCanStillReach() throws {
  // End to end, because the two halves of it are in different places: the
  // rename works, the delete behind it does not — which is what a file a `sudo`
  // step left root-owned in `_tool` does to `removeItem` — and what is left has
  // to be reachable by the next press of the same button.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 8)

  #expect(throws: (any Error).self) {
    try Housekeeper(files: MovingButNotDeletingOperations()).blockingClean(
      .toolCache, in: sandbox.runner, isStillSafe: { true })
  }
  #expect(sandbox.names(in: sandbox.work) == [Housekeeper.trashFolder])

  try Housekeeper().blockingClean(.toolCache, in: sandbox.runner, isStillSafe: { true })
  #expect(sandbox.names(in: sandbox.work).isEmpty)
}

/// Renames for real and refuses to delete, which is what a directory holding a
/// file this app cannot unlink looks like from here.
private struct MovingButNotDeletingOperations: DestructiveFileOperations {
  struct Refusal: Error {}
  /// Set to have the rename fail too, which is the earlier of the two places a
  /// clean can stop and names a different directory.
  var refusingMove = false

  func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  func move(_ url: URL, to destination: URL) throws {
    if refusingMove { throw Refusal() }
    try FileManager.default.moveItem(at: url, to: destination)
  }
  func remove(_ url: URL) throws { throw Refusal() }
}

@Test func aTrashLeftBehindIsNotMistakenForARepositoryCheckout() throws {
  // The leading dot is load-bearing, not decoration. `_work` carries no
  // manifest, so the breakdown reads each directory's purpose off its name:
  // anything that starts with an underscore or a dot is the runner's own, and
  // what is left is named after a repository. A trash folder without the dot
  // would be reported to the user as gigabytes of *repository checkout* — the
  // one line in that submenu that says "do not delete this".
  #expect(Housekeeper.trashFolder.hasPrefix("."))
  #expect(DiskEntryKind(folderName: Housekeeper.trashFolder) == .other)
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

@Test func anOutsideWorkFolderSymlinkIsRefusedBeforeAnyMutation() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("placeholder")
  try sandbox.makeOutsideFolder("_tool", kilobytes: 4)
  try sandbox.replaceWorkDirectoryWithOutsideSymlink()
  let files = RecordingFileOperations()

  #expect(throws: HousekeepingFailure(directory: sandbox.work)) {
    try Housekeeper(files: files).blockingClean(
      .toolCache, in: sandbox.runner, isStillSafe: { true })
  }

  #expect(files.calls.isEmpty)
  #expect(sandbox.exists(sandbox.outside.appendingPathComponent("_tool/payload")))
}

@Test func aRunnerThatPickedUpWorkKeepsItsCache() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 4)
  // With a grave in it, so the sweep above the check is actually under these
  // assertions. Without one the trash branch never runs and they pass over a
  // path nothing exercised.
  try sandbox.makeWorkFolder("\(Housekeeper.trashFolder)/leftover", kilobytes: 4)

  let files = RecordingFileOperations()
  let outcome = try Housekeeper(files: files).blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { false })

  #expect(outcome == .refused)
  // Nothing of the runner's was moved, and nothing of the runner's was removed.
  // The grave is this app's own and is swept whatever the answer — it holds
  // only what an earlier run of this left behind, at a path the runner cannot
  // be using, and sweeping it is the one thing that ever will.
  #expect(!files.calls.contains { $0.hasPrefix("move") })
  #expect(!files.calls.contains { $0.contains("_tool") })
  #expect(sandbox.names(in: sandbox.work).contains("_tool"))
}

@Test func aRefusalLeavesNoEmptyGraveBehindIt() throws {
  // `.refused` is reported to the user as "nothing was deleted", and the menu
  // is redrawn from a fresh measurement underneath it. A trash folder left
  // sitting there turns that sentence into a lie and shows up in the breakdown
  // as "Other runner files" — this app's own litter, reported to the user as
  // the runner's.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 4)

  let outcome = try Housekeeper().blockingClean(
    .toolCache, in: sandbox.runner, isStillSafe: { false })

  #expect(outcome == .refused)
  #expect(sandbox.names(in: sandbox.work) == ["_tool"])
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

@Test func aFailedWriteSaysWhichDirectoryTheUserHasToFix() throws {
  // The menu prints this path and the user goes and looks at it, so it has to
  // be a directory that is still there. Which one that is depends on how far
  // the operation got — and after the rename it is emphatically not the one
  // they were asked about, because that one has just been moved away.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 1)
  let trash = sandbox.work.appendingPathComponent(Housekeeper.trashFolder)

  // Nothing can be written at all: what failed is making the trash, and what
  // the user has to fix is `_work`.
  let refusing = RecordingFileOperations()
  refusing.failing = true
  #expect(blamedDirectory(Housekeeper(files: refusing), sandbox) == sandbox.work.path)

  // The rename itself failed, so the cache is where it always was.
  #expect(
    blamedDirectory(
      Housekeeper(files: MovingButNotDeletingOperations(refusingMove: true)), sandbox)
      == sandbox.work.appendingPathComponent("_tool").path)

  // And the delete behind a rename that worked: `_tool` is gone, and the bytes
  // the user is looking for are in the grave.
  #expect(
    blamedDirectory(Housekeeper(files: MovingButNotDeletingOperations()), sandbox)
      == trash.path)
}

/// The directory a clean blamed, as a path — compared as text because a `URL`
/// built over a directory that exists picks up a trailing slash and one built
/// over the same name before it exists does not.
private func blamedDirectory(
  _ keeper: Housekeeper, _ sandbox: RunnerDirectorySandbox
) -> String? {
  do {
    try keeper.blockingClean(.toolCache, in: sandbox.runner, isStillSafe: { true })
    return nil
  } catch let failure as HousekeepingFailure {
    return failure.directory.path
  } catch {
    return nil
  }
}

// MARK: - Rotation

@Test func anOutsideDiagnosticsSymlinkIsRefusedBeforeAFileIsRemoved() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let foreignLog = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log",
    modified: now.addingTimeInterval(-30 * 24 * 3600), in: sandbox.outside)
  try FileManager.default.createSymbolicLink(
    at: sandbox.diagnostics, withDestinationURL: sandbox.outside)

  #expect(throws: HousekeepingFailure(directory: sandbox.diagnostics)) {
    try Housekeeper().blockingRotateDiagnostics(
      in: sandbox.runner, now: now, isStillSafe: { true })
  }

  #expect(sandbox.exists(foreignLog))
}

@Test func diagnosticsSymlinkedWithinTheRunnerCanStillBeRotated() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let internalDiagnostics = sandbox.root.appendingPathComponent("diagnostics-store")
  let old = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log",
    modified: now.addingTimeInterval(-30 * 24 * 3600), in: internalDiagnostics)
  try FileManager.default.createSymbolicLink(
    at: sandbox.diagnostics, withDestinationURL: internalDiagnostics)

  let outcome = try Housekeeper().blockingRotateDiagnostics(
    in: sandbox.runner, now: now, isStillSafe: { true })

  #expect(outcome == .done)
  #expect(!sandbox.exists(old))
}

@Test func rotationLeavesTheActiveLogAndTakesTheRest() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log", bytes: 4096,
    modified: now.addingTimeInterval(-30 * 24 * 3600))
  let active = try sandbox.makeLog("Runner_20260805-000000-utc.log", modified: now)

  let outcome = try Housekeeper().blockingRotateDiagnostics(
    in: sandbox.runner, now: now, isStillSafe: { true })

  #expect(outcome == .done)
  #expect(!sandbox.exists(old))
  #expect(sandbox.exists(active))
}

@Test func aDiagnosticLogThatCannotBeRemovedReportsTheDiagnosticsDirectory() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog(
    "Worker_20260101-000000-utc.log",
    modified: now.addingTimeInterval(-30 * 24 * 3600))

  let files = RecordingFileOperations()
  files.failing = true

  #expect(throws: HousekeepingFailure(directory: sandbox.diagnostics)) {
    try Housekeeper(files: files).blockingRotateDiagnostics(
      in: sandbox.runner, now: now, isStillSafe: { true })
  }
}

@Test func aRotationFailureReportsWhenAnEarlierLogWasRemoved() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let first = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log",
    modified: now.addingTimeInterval(-40 * 24 * 3600))
  let second = try sandbox.makeLog(
    "Worker_20260201-000000-utc.log",
    modified: now.addingTimeInterval(-30 * 24 * 3600))

  do {
    _ = try Housekeeper(files: RemovingOneThenRefusingOperations())
      .blockingRotateDiagnostics(in: sandbox.runner, now: now, isStillSafe: { true })
    Issue.record("Expected the second unlink to fail")
  } catch let failure as HousekeepingFailure {
    #expect(failure.directory == sandbox.diagnostics)
    #expect(failure.didModify)
  }

  #expect(!sandbox.exists(first))
  #expect(sandbox.exists(second))
}

private final class RemovingOneThenRefusingOperations:
  DestructiveFileOperations, @unchecked Sendable
{
  private struct Refusal: Error {}
  private let lock = NSLock()
  private var removalCount = 0

  func createDirectory(at url: URL) throws {}
  func move(_ url: URL, to destination: URL) throws {}

  func remove(_ url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    guard removalCount == 0 else { throw Refusal() }
    removalCount += 1
    try FileManager.default.removeItem(at: url)
  }
}

@Test func aDiagnosticLogThatDisappearedBeforeUnlinkIsStillDone() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log",
    modified: now.addingTimeInterval(-30 * 24 * 3600))

  let outcome = try Housekeeper(files: RemovingThenMissingOperations())
    .blockingRotateDiagnostics(
      in: sandbox.runner, now: now, isStillSafe: { true })

  #expect(outcome == .done)
  #expect(!sandbox.exists(old))
}

private struct RemovingThenMissingOperations: DestructiveFileOperations {
  func createDirectory(at url: URL) throws {}
  func move(_ url: URL, to destination: URL) throws {}
  func remove(_ url: URL) throws {
    try FileManager.default.removeItem(at: url)
    // The second real removal supplies Foundation's bridged NSError, rather
    // than the Swift CocoaError value a test could manufacture directly.
    try FileManager.default.removeItem(at: url)
  }
}

@Test func rotationRefusesWhileTheRunnerIsWorkingToo() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let old = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log", modified: now.addingTimeInterval(-30 * 24 * 3600))

  let files = RecordingFileOperations()
  let outcome = try Housekeeper(files: files).blockingRotateDiagnostics(
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
  let outcome = try Housekeeper().blockingRotateDiagnostics(in: sandbox.runner, now: now) {
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
