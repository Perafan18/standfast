import Foundation
import Testing

@testable import RunnerKit

private let now = Date(timeIntervalSince1970: 1_785_962_174)

// MARK: - The version itself

@Test func versionsCompareAsNumbersAndNotAsText() {
  // The whole reason this is not a `String`. As text `2.336.0` sorts before
  // `2.9.0`, so a runner three releases out of date would be reported as ahead
  // of the newest one — and the runner is long past the minor version where
  // that stops being hypothetical.
  #expect(RunnerVersion(2, 9, 0) < RunnerVersion(2, 336, 0))
  #expect(RunnerVersion(2, 336, 0) < RunnerVersion(2, 336, 1))
  #expect(RunnerVersion(2, 336, 1) < RunnerVersion(3, 0, 0))
  #expect(!(RunnerVersion(2, 336, 0) < RunnerVersion(2, 336, 0)))
}

@Test func theTagGitHubPublishesIsTheVersionTheRunnerPrints() {
  // Two spellings of one number, from the two halves of the same question:
  // `gh` answers `v2.336.0` and the listener writes `2.336.0`. Comparing them
  // as they arrive would report every runner as out of date, for ever.
  #expect(RunnerVersion("v2.336.0") == RunnerVersion("2.336.0"))
  #expect(RunnerVersion("2.336.0\n") == RunnerVersion(2, 336, 0))
  #expect(RunnerVersion("2.336.0")?.description == "2.336.0")
}

@Test func anythingThatIsNotThreeNumbersIsNotAVersion() {
  for text in ["", "2.336", "2.336.0.1", "latest", "v", "2.x.0"] {
    #expect(RunnerVersion(text) == nil)
  }
}

// MARK: - Reading it off the machine

/// The version as the app reads it: out of the log the job reader already has
/// open, rather than off a second listing of `_diag`.
///
/// Through that reader rather than around it, because which file is current is
/// its decision and the two disagreeing is exactly what would leave last
/// month's version in the menu after a self-update.
private func installedVersion(in sandbox: RunnerDirectorySandbox) -> RunnerVersion? {
  var reader = JobLogReader()
  _ = reader.read(diagnosticsIn: sandbox.diagnostics)
  return reader.activeLog.flatMap(RunnerVersionReader().blockingVersion)
}

@Test func theVersionComesOutOfTheListenerLog() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog(
    "Runner_20260805-000000-utc.log",
    lines: listenerChatter(at: "2026-08-05 20:36:14Z"), modified: now)

  #expect(
    installedVersion(in: sandbox)
      == RunnerVersion(2, 336, 0))
}

@Test func theNewestLogIsTheOneThatSaysWhichRunnerIsInstalled() throws {
  // A runner that updated itself yesterday left last week's version at the top
  // of last week's log, and every one before that. The newest by name is the
  // only one describing the runner that will take the next job.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog(
    "Runner_20260801-000000-utc.log",
    lines: ["[2026-08-01 00:00:00Z INFO Listener] Version: 2.300.0"], modified: now)
  try sandbox.makeLog(
    "Runner_20260805-000000-utc.log",
    lines: ["[2026-08-05 00:00:00Z INFO Listener] Version: 2.336.0"], modified: now)

  #expect(
    installedVersion(in: sandbox)
      == RunnerVersion(2, 336, 0))
}

@Test func aJobNamedAfterAVersionIsNotTheRunnersVersion() throws {
  // The listener echoes every job's name into the same log, after the same
  // bracket its own header uses — and a job called `Release Version: 9.9.9` is
  // an ordinary thing for a release workflow to be called. A match on
  // `Version: ` alone finds that line first and reports the workflow's number
  // as the runner's, which is wrong in a way nobody would ever question.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let stamp = "2026-08-05 00:00:00Z"
  try sandbox.makeLog(
    "Runner_20260805-000000-utc.log",
    lines: [
      startedJob("Release Version: 9.9.9", at: stamp),
      "[\(stamp) INFO Listener] Version: 2.336.0",
    ],
    modified: now)

  #expect(
    installedVersion(in: sandbox)
      == RunnerVersion(2, 336, 0))
}

@Test func theWordVersionOnItsOwnIsNotAVersion() throws {
  // Every listener log carries this line a few rows under the real one. A
  // looser match reads it as the version and comes back with nothing, on
  // exactly the runners that were started with arguments.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog(
    "Runner_20260805-000000-utc.log",
    lines: ["[2026-08-05 00:00:00Z INFO CommandSettings] Flag 'version': 'False'"],
    modified: now)

  #expect(installedVersion(in: sandbox) == nil)
}

@Test func theHeadReadIsWideEnoughForWhatAListenerActuallyWritesFirst() throws {
  // Every other fixture in this file puts the version in the first hundred
  // bytes, so a read window shrunk to almost nothing would pass all of them and
  // find nothing on a real machine. Measured on the runner this was built
  // against, the line sits 1088 bytes in — behind the proxy notice, six
  // well-known directories and the OS banner — and a Mac with a longer home
  // directory pushes every one of those out further.
  //
  // Four kilobytes of preamble here: comfortably past what was measured, and
  // still inside a window that has to stay a ceiling on a mistake rather than a
  // target.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  let stamp = "2026-08-05 00:00:00Z"
  let chatter = (0..<40).map {
    "[\(stamp) INFO HostContext] Well known directory 'Root\($0)': "
      + "'/Users/somebody-with-a-long-name/actions-runner-\($0)'"
  }
  #expect(chatter.joined(separator: "\n").count > 4096)
  try sandbox.makeLog(
    "Runner_20260805-000000-utc.log",
    lines: chatter + ["[\(stamp) INFO Listener] Version: 2.336.0"], modified: now)

  #expect(
    installedVersion(in: sandbox)
      == RunnerVersion(2, 336, 0))
}

@Test func aRunnerThatHasNeverWrittenALogHasNoVersionToReport() throws {
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  // Nil rather than a guess. The version is a nice-to-know beside a runner that
  // works, and inventing one would put a wrong number in the menu for ever.
  #expect(installedVersion(in: sandbox) == nil)
}

@Test func aWorkerLogIsNotWhereTheListenerVersionIsRead() throws {
  // Worker logs carry a `Version:` line of their own, are ten times the size,
  // and are the files a `_diag` sweep is aimed at. Reading one would make the
  // version disappear the first time somebody tidied up.
  let sandbox = try RunnerDirectorySandbox()
  defer { sandbox.cleanUp() }
  try sandbox.makeLog(
    "Worker_20260806-000000-utc.log",
    lines: ["[2026-08-06 00:00:00Z INFO Worker] Version: 2.400.0"], modified: now)
  try sandbox.makeLog(
    "Runner_20260805-000000-utc.log",
    lines: ["[2026-08-05 00:00:00Z INFO Listener] Version: 2.336.0"], modified: now)

  #expect(
    installedVersion(in: sandbox)
      == RunnerVersion(2, 336, 0))
}
