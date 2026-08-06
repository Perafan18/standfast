import Foundation
import Testing

@testable import RunnerKit

/// One `du` answer, in the format the real one prints: block count, a tab, the
/// path exactly as it was passed in.
private func duLine(_ kilobytes: Int, _ url: URL) -> String {
  "\(kilobytes)\t\(url.path)\n"
}

// MARK: - What is asked of du

@Test func everyDirectoryIsMeasuredInOneCall() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool")
  try sandbox.makeWorkFolder("_actions")
  try sandbox.makeLog("Runner_20260805-000000-utc.log", modified: Date())
  let diagnostics = sandbox.diagnostics.resolvingSymlinksInPath()

  let runner = FakeCommandRunner()
  _ = DiskUsage(commandRunner: runner).blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())

  // One process, not one per directory. `du` only counts a hard link once
  // within a single invocation, so this is correctness and not only cost.
  #expect(runner.invocations.count == 1)
  let invocation = try #require(runner.invocations.first)
  #expect(invocation.executable == "/usr/bin/du")
  // Pinned as literals rather than built from `DiskUsage.arguments`, which
  // would make this test agree with whatever the constant says. `-s` is what
  // gives one line per argument and `-k` is what fixes the unit against a
  // `BLOCKSIZE` in the environment; losing either changes every number here.
  #expect(invocation.arguments.first == "-sk")
  #expect(
    Set(invocation.arguments.dropFirst()) == [
      sandbox.work.appendingPathComponent("_actions").path,
      sandbox.work.appendingPathComponent("_tool").path,
      diagnostics.path,
    ])
}

@Test func duIsNeverRunWithNoPathsAtAll() throws {
  // A runner that has never taken a job has neither directory. `du` with no
  // arguments is not a no-op: it measures the working directory it was launched
  // in, which for a menu bar app is wherever Finder started it — so this would
  // report somebody's home directory as their runner's disk use.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }

  let runner = FakeCommandRunner()
  let report = DiskUsage(commandRunner: runner).blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())

  #expect(runner.invocations.isEmpty)
  #expect(report == .empty)
}

@Test func duIsNotRunWhenTheWorkFolderWasReplacedByAnOutsideSymlink() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("placeholder")
  try sandbox.makeOutsideFolder("_tool", kilobytes: 4)
  try sandbox.replaceWorkDirectoryWithOutsideSymlink()
  let runner = FakeCommandRunner()

  let report = DiskUsage(commandRunner: runner).blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())

  #expect(report == nil)
  #expect(runner.invocations.isEmpty)
}

@Test func anOutsideDiagnosticsSymlinkIsNotMeasuredOrPlanned() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let foreignLog = try sandbox.makeLog(
    "Worker_20260101-000000-utc.log",
    modified: Date().addingTimeInterval(-30 * 24 * 3600), in: sandbox.outside)
  try FileManager.default.createSymbolicLink(
    at: sandbox.diagnostics, withDestinationURL: sandbox.outside)
  let runner = FakeCommandRunner()

  let report = DiskUsage(commandRunner: runner).blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())

  #expect(report == nil)
  #expect(runner.invocations.isEmpty)
  #expect(sandbox.exists(foreignLog))
}

@Test func aDiagnosticsListingFailureMakesTheMeasurementUnavailable() throws {
  // `_diag` exists, so `du` can still size this regular file; the failure is
  // specifically that it cannot be enumerated as the directory a rotation
  // plan requires. Returning a report with an empty plan would present that as
  // a successful measurement and hide the read failure.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try Data("not a directory".utf8).write(to: sandbox.diagnostics)

  let report = DiskUsage().blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())

  #expect(report == nil)
}

@Test func aWorkListingFailureMakesTheMeasurementUnavailable() throws {
  // A regular file at `_work` is a deterministic directory-listing failure.
  // Folding it into `[]` reports a successful zero-byte measurement, which is
  // indistinguishable from a runner that genuinely has never taken a job.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try Data("not a directory".utf8).write(to: sandbox.work)
  let runner = FakeCommandRunner()

  let report = DiskUsage(commandRunner: runner).blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())

  #expect(report == nil)
  #expect(runner.invocations.isEmpty)
}

// MARK: - What comes back

@Test func theBreakdownSaysWhatEachDirectoryIsFor() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  for folder in ["_tool", "_actions", "_temp", "_PipelineMapping", "nest-rules-app"] {
    try sandbox.makeWorkFolder(folder)
  }
  try sandbox.makeLog("Runner_20260805-000000-utc.log", modified: Date())

  let work = sandbox.work
  let diagnostics = sandbox.diagnostics.resolvingSymlinksInPath()
  let runner = FakeCommandRunner([
    [
      "/usr/bin/du", "-sk", work.appendingPathComponent("_PipelineMapping").path,
      work.appendingPathComponent("_actions").path,
      work.appendingPathComponent("_temp").path,
      work.appendingPathComponent("_tool").path,
      work.appendingPathComponent("nest-rules-app").path,
      diagnostics.path,
    ]:
      duLine(4, work.appendingPathComponent("_PipelineMapping"))
      + duLine(16_200, work.appendingPathComponent("_actions"))
      + duLine(0, work.appendingPathComponent("_temp"))
      + duLine(4_229_008, work.appendingPathComponent("_tool"))
      + duLine(420_724, work.appendingPathComponent("nest-rules-app"))
      + duLine(9_048, diagnostics)
  ])
  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))

  #expect(report.bytes(of: .toolCache) == 4_229_008 * 1024)
  #expect(report.bytes(of: .actionCache) == 16_200 * 1024)
  #expect(report.bytes(of: .temporary) == 0)
  #expect(report.bytes(of: .other) == 4 * 1024)
  // The repository working copy. It is the one directory here that is not a
  // cache, and nothing in `CleanupTarget` can name it.
  #expect(report.bytes(of: .checkout) == 420_724 * 1024)
  #expect(!CleanupTarget.allCases.map(\.kind).contains(.checkout))
  // And `_diag`, which is not under `_work` and so gets no entry of its own —
  // the submenu's "Logs" row is read straight off this field, and it is the one
  // number here nothing else would notice going to zero.
  #expect(report.logBytes == 9_048 * 1024)
}

@Test func twoCheckoutsAreOneRowAndTheirSizesAddUp() throws {
  // What `bytes(of:)` exists for. `_work` holds one working copy per repository
  // a runner builds and the submenu has no room for a row each — so a Mac
  // building two of them would be told the cost of whichever came first, under
  // the one heading in that menu that says "do not delete this".
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  for folder in ["nest-rules-app", "widget"] { try sandbox.makeWorkFolder(folder) }

  let work = sandbox.work
  let runner = FakeCommandRunner([
    [
      "/usr/bin/du", "-sk", work.appendingPathComponent("nest-rules-app").path,
      work.appendingPathComponent("widget").path,
    ]:
      duLine(420_724, work.appendingPathComponent("nest-rules-app"))
      + duLine(102_400, work.appendingPathComponent("widget"))
  ])
  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))

  #expect(report.bytes(of: .checkout) == (420_724 + 102_400) * 1024)
}

@Test func pendingCacheGravesKeepTheirKindsAndAddUp() throws {
  // A failed recursive delete leaves the cache behind Standfast's atomic
  // rename. The original `_tool` or `_actions` name is gone, but the next
  // measurement still has to offer the matching recovery action. Two tool
  // graves exercise aggregation rather than a single lucky entry.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let trash = sandbox.work.appendingPathComponent(Housekeeper.trashFolder)
  let firstTool = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/standfast-v1.toolCache.00000000-0000-0000-0000-000000000001"
  )
  let secondTool = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/standfast-v1.toolCache.00000000-0000-0000-0000-000000000002"
  )
  let action = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/standfast-v1.actionCache.00000000-0000-0000-0000-000000000003"
  )
  let runner = FakeCommandRunner([
    ["/usr/bin/du", "-sk", action.path, firstTool.path, secondTool.path]:
      duLine(3, action) + duLine(5, firstTool) + duLine(7, secondTool)
  ])

  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))

  #expect(report.bytes(of: .toolCache) == 12 * 1024)
  #expect(report.bytes(of: .actionCache) == 3 * 1024)
  #expect(report.bytes(of: .other) == 0)
  #expect(!runner.invocations[0].arguments.contains(trash.path))
}

@Test func legacyAndMalformedGravesStayDistinctBesideTypedOnes() throws {
  // Version 0.4.0 named graves with a bare UUID, before the cache kind was
  // encoded. That history is recoverable only as generic Standfast leftovers;
  // guessing tool or actions would make a destructive promise without evidence.
  // A malformed neighbour is not legacy either and must remain Other.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let firstLegacy = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/AAAAAAAA-0000-0000-0000-000000000001")
  let secondLegacy = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/AAAAAAAA-0000-0000-0000-000000000003")
  let malformed = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/not-a-standfast-grave")
  let typed = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/standfast-v1.toolCache.AAAAAAAA-0000-0000-0000-000000000002"
  )
  let runner = FakeCommandRunner([
    [
      "/usr/bin/du", "-sk", firstLegacy.path, secondLegacy.path, malformed.path, typed.path,
    ]:
      duLine(4, firstLegacy) + duLine(6, secondLegacy) + duLine(2, malformed)
      + duLine(5, typed)
  ])

  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))

  #expect(report.bytes(of: .toolCache) == 5 * 1024)
  #expect(report.bytes(of: .actionCache) == 0)
  #expect(report.legacyTrashBytes == 10 * 1024)
  #expect(report.bytes(of: .other) == 2 * 1024)
  #expect(
    report.bytes(of: .toolCache) + report.legacyTrashBytes
      + report.bytes(of: .other) == 17 * 1024)
}

@Test func untrustedTrashNamesAndSymlinksCannotPoseAsCaches() throws {
  // Only the exact versioned name Housekeeper emits may recover a cache kind.
  // A plausible typo stays "Other", and a symlink with a perfect name must not
  // make its destination count as safe cache bytes.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let malformed = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/standfast-v1.toolCache.not-a-uuid")
  let wrongVersion = try sandbox.makeWorkFolder(
    "\(Housekeeper.trashFolder)/standfast-v2.actionCache.00000000-0000-0000-0000-000000000004"
  )
  let outside = try sandbox.makeOutsideFolder("foreign-tool", kilobytes: 8)
  let disguisedSymlink = sandbox.work.appendingPathComponent(
    "\(Housekeeper.trashFolder)/standfast-v1.toolCache.00000000-0000-0000-0000-000000000005"
  )
  try FileManager.default.createSymbolicLink(
    at: disguisedSymlink, withDestinationURL: outside)
  let runner = FakeCommandRunner([
    ["/usr/bin/du", "-sk", disguisedSymlink.path, malformed.path, wrongVersion.path]:
      duLine(1, disguisedSymlink) + duLine(2, malformed) + duLine(3, wrongVersion)
  ])

  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))

  #expect(report.bytes(of: .toolCache) == 0)
  #expect(report.bytes(of: .actionCache) == 0)
  #expect(report.bytes(of: .other) == 6 * 1024)
  #expect(!runner.invocations[0].arguments.contains(outside.path))
}

@Test func blocksAreNotBytes() throws {
  // `du -sk` counts 1024-byte blocks. Reporting the number it prints as bytes
  // would understate a four-gigabyte tool cache by a factor of a thousand, and
  // it would look entirely plausible on the way past.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let folder = try sandbox.makeWorkFolder("_tool")

  let runner = FakeCommandRunner([
    ["/usr/bin/du", "-sk", folder.path]: duLine(2, folder)
  ])
  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))
  #expect(report.bytes(of: .toolCache) == 2048)
}

@Test func theBiggestThingComesFirst() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  for folder in ["_actions", "_tool"] { try sandbox.makeWorkFolder(folder) }

  let work = sandbox.work
  let runner = FakeCommandRunner([
    [
      "/usr/bin/du", "-sk", work.appendingPathComponent("_actions").path,
      work.appendingPathComponent("_tool").path,
    ]:
      duLine(16_200, work.appendingPathComponent("_actions"))
      + duLine(4_229_008, work.appendingPathComponent("_tool"))
  ])
  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))
  // Not the order `du` printed them in, and not the order the directory listing
  // came back in: the largest is the only one worth reading first.
  #expect(report.entries.map(\.name) == ["_tool", "_actions"])
}

@Test func twoDirectoriesOfTheSameSizeAreOrderedByNameAndNotByLuck() {
  // `_work` on an idle runner has two or three empty directories in it, so ties
  // are the ordinary case rather than the exotic one. Without a tie-break the
  // order of the tied entries is whatever `sorted` happens to do with them, and
  // Swift does not promise that is stable — so `entries` would be a list that
  // could reshuffle between two identical readings.
  //
  // The comparator directly, not through `blockingReport`: the listing it is
  // given is already sorted by name, so through there the tie-break can never
  // be observed changing anything and a test that went that way would pass
  // whether it existed or not.
  let temp = DiskEntry(name: "_temp", kind: .temporary, bytes: 8192)
  let mapping = DiskEntry(name: "_PipelineMapping", kind: .other, bytes: 8192)
  #expect(DiskUsage.biggestFirst(mapping, temp))
  #expect(!DiskUsage.biggestFirst(temp, mapping))
  // And size still wins over the name, which is the whole ordering.
  let tool = DiskEntry(name: "_tool", kind: .toolCache, bytes: 4_331_016_192)
  #expect(DiskUsage.biggestFirst(tool, mapping))
}

@Test func aDuThatSaidNothingIsNotADiskWithNothingOnIt() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool")

  // No output at all is what a `du` that could not run looks like. Folding that
  // into a report of zero bytes would put "Tool cache — 0 bytes" over four
  // gigabytes, and the menu has a line for "could not measure".
  let report = DiskUsage(commandRunner: FakeCommandRunner()).blockingReport(
    for: sandbox.runner, retention: .standard, now: Date())
  #expect(report == nil)
}

@Test func aDirectoryDuCouldNotReadDoesNotLoseTheOnesItCould() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  for folder in ["_actions", "_tool"] { try sandbox.makeWorkFolder(folder) }

  let work = sandbox.work
  let command = [
    "/usr/bin/du", "-sk", work.appendingPathComponent("_actions").path,
    work.appendingPathComponent("_tool").path,
  ]
  let runner = FakeCommandRunner([
    command: duLine(4_229_008, work.appendingPathComponent("_tool"))
  ])
  // `du` exits non-zero when one argument was unreadable and still reports the
  // rest, which is ordinary on a machine with a runner working on it. Reading
  // the exit code as the verdict would throw away the four gigabytes it did
  // measure.
  runner.exitCodes[command] = 1

  let report = try #require(
    DiskUsage(commandRunner: runner).blockingReport(
      for: sandbox.runner, retention: .standard, now: Date()))
  #expect(report.bytes(of: .toolCache) == 4_229_008 * 1024)
  #expect(report.bytes(of: .actionCache) == 0)
}

// MARK: - Against the real du

@Test func theRealDuPrintsWhatTheParserReads() throws {
  // The one thing a fake cannot prove. Every test above agrees with a fixture
  // this file wrote, so a parser that expected spaces where `du` writes a tab
  // would pass all of them and report every runner as using nothing.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeWorkFolder("_tool", kilobytes: 512)
  try sandbox.makeWorkFolder("_actions")

  let report = try #require(
    DiskUsage().blockingReport(for: sandbox.runner, retention: .standard, now: Date()))
  // Not an exact figure: `du` counts allocated blocks, and how many of those a
  // half-megabyte file takes is the filesystem's business.
  #expect(report.bytes(of: .toolCache) >= 512 * 1024)
  #expect(report.bytes(of: .toolCache) < 2 * 512 * 1024)
  #expect(report.entries.map(\.name) == ["_tool", "_actions"])
}
