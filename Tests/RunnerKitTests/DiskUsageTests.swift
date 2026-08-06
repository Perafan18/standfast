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
      sandbox.diagnostics.path,
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

// MARK: - What comes back

@Test func theBreakdownSaysWhatEachDirectoryIsFor() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  for folder in ["_tool", "_actions", "_temp", "_PipelineMapping", "nest-rules-app"] {
    try sandbox.makeWorkFolder(folder)
  }

  let work = sandbox.work
  let runner = FakeCommandRunner([
    [
      "/usr/bin/du", "-sk", work.appendingPathComponent("_PipelineMapping").path,
      work.appendingPathComponent("_actions").path,
      work.appendingPathComponent("_temp").path,
      work.appendingPathComponent("_tool").path,
      work.appendingPathComponent("nest-rules-app").path,
    ]:
      duLine(4, work.appendingPathComponent("_PipelineMapping"))
      + duLine(16_200, work.appendingPathComponent("_actions"))
      + duLine(0, work.appendingPathComponent("_temp"))
      + duLine(4_229_008, work.appendingPathComponent("_tool"))
      + duLine(420_724, work.appendingPathComponent("nest-rules-app"))
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
