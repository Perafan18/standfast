import Foundation
import Testing

@testable import RunnerKit

private let directory = URL(fileURLWithPath: "/Users/ci/actions-runner-standfast")
// Spelled out rather than shared with the probe: the locale in front of `ps`
// and the user after it are part of what these tests pin, and a shared constant
// would follow a revert. A user id no account on a test machine has, so a probe
// that listed its own user instead of the one it was given finds nothing.
private let userID: uid_t = 2001
private let psCommand = [
  "/usr/bin/env", "LC_ALL=en_US.UTF-8", "/bin/ps", "-wwo", "command=", "-U", "2001",
]

private func probe(_ output: String, exitCode: Int32 = 0) -> ListenerProcessProbe {
  let fake = FakeCommandRunner([psCommand: output])
  fake.exitCodes[psCommand] = exitCode
  return ListenerProcessProbe(commandRunner: fake, userID: userID)
}

@Test func aListenerRunningOutOfThisDirectoryIsRunning() {
  // What `./run.sh` leaves in the process table: the runner's own binary,
  // launched by absolute path out of its own directory.
  let running = """
    /Users/ci/actions-runner-standfast/bin/Runner.Listener run --startuptype service
    /usr/sbin/cfprefsd agent
    """

  #expect(probe(running).blockingIsRunning(inDirectory: directory) == true)
}

@Test func aListenerFromAnotherRunnerIsNotThisOne() {
  // Several runners on one Mac is the case this app exists for, and their
  // command lines differ only by the directory in front.
  let elsewhere = """
    /Users/ci/actions-runner-other/bin/Runner.Listener run --startuptype service
    """

  #expect(probe(elsewhere).blockingIsRunning(inDirectory: directory) == false)
}

@Test func aRunnerInANeighbouringDirectoryIsNotThisOne() {
  // Several runners on one Mac, installed side by side, whose directory names
  // share a prefix.
  let neighbour = """
    /Users/ci/actions-runner-standfast-two/bin/Runner.Listener run
    """

  #expect(probe(neighbour).blockingIsRunning(inDirectory: directory) == false)
}

@Test func aBinaryWhoseNameMerelyStartsTheSameIsNotTheListener() {
  // The case the directory tests above do not reach, because there `hasPrefix`
  // already says no. Here it says yes: the command genuinely begins with the
  // listener's whole path and then keeps going. Only a boundary after it — a
  // space, or the end of the line — separates the runner's listener from
  // something somebody left beside it.
  let lookalikes = """
    /Users/ci/actions-runner-standfast/bin/Runner.ListenerOld run
    /Users/ci/actions-runner-standfast/bin/Runner.Listener.bak run
    """

  #expect(probe(lookalikes).blockingIsRunning(inDirectory: directory) == false)
}

@Test func somethingElseEntirelyIsNotAListener() {
  let noise = """
    /Users/ci/actions-runner-standfast/bin/Runner.Worker spawnedfrom 42
    /Users/ci/actions-runner-standfast/run.sh
    """

  // The worker is a job, not the listener. `run.sh` lives exactly as long as
  // its helper, which is the process that says a listener is coming back.
  #expect(probe(noise).blockingIsRunning(inDirectory: directory) == false)
}

// MARK: - Between two listeners

@Test func aRunnerRelaunchingItsListenerIsStillRunning() {
  // A listener that exits to update itself or to retry leaves its helper
  // waiting a few seconds, then `run.sh` starts the next one. A scan in that
  // gap must not draw a runner that never stopped as stopped.
  let relaunching = """
    /bin/bash /Users/ci/actions-runner-standfast/run-helper.sh
    /bin/bash ./run.sh
    """

  #expect(probe(relaunching).blockingIsRunning(inDirectory: directory) == true)
}

@Test func onlyThisRunnersOwnHelperRunningAsAProgramCounts() {
  // `run.sh` on its own is usually a relative path, naming no folder at all.
  let others = """
    /bin/bash /Users/ci/actions-runner-standfast-two/run-helper.sh
    /bin/bash /Users/ci/actions-runner-standfast/run-helper.sh.bak
    /usr/bin/vim /Users/ci/actions-runner-standfast/run-helper.sh
    /bin/bash ./run.sh
    """

  #expect(probe(others).blockingIsRunning(inDirectory: directory) == false)
}

@Test func aListenerInAFolderNamedOutsideASCIIIsFoundHoweverTheAppWasOpened() {
  // Opened from Finder or at login, the app has no locale, and a bare `ps`
  // escapes every byte outside ASCII. The fake answers the bare command in
  // that form, so only a probe that pins the locale finds this runner.
  let accented = URL(fileURLWithPath: "/Users/ci/Integración/actions-runner")
  let fake = FakeCommandRunner([
    ["/bin/ps", "-wwo", "command=", "-U", "2001"]:
      "/Users/ci/IntegraciM-CM-3n/actions-runner/bin/Runner.Listener run\n",
    psCommand: "/Users/ci/Integración/actions-runner/bin/Runner.Listener run\n",
  ])

  #expect(
    ListenerProcessProbe(commandRunner: fake, userID: userID)
      .blockingIsRunning(inDirectory: accented) == true)
}

@Test func anotherAccountsProcessIsNeverRead() {
  // Another account's command line is theirs to write, and a path in it may
  // sit on a share that no longer answers: resolving it would hold up the
  // scan for every runner. The fake answers the every-user listing with a
  // line that would match, so only a probe that lists this user alone misses
  // it.
  let fake = FakeCommandRunner([
    ["/usr/bin/env", "LC_ALL=en_US.UTF-8", "/bin/ps", "-Awwo", "command="]:
      "/Users/ci/actions-runner-standfast/bin/Runner.Listener run\n",
    psCommand: "/usr/sbin/cfprefsd agent\n",
  ])

  #expect(
    ListenerProcessProbe(commandRunner: fake, userID: userID)
      .blockingIsRunning(inDirectory: directory) == false)
  #expect(fake.invocations.map(\.arguments) == [Array(psCommand.dropFirst())])
}

// MARK: - One folder, several names

/// Real folders, because only the filesystem knows two names are one place.
/// They sit under the temporary directory, which lives in `/var`: a symlink to
/// `/private/var`, so every folder here has two spellings already.
private final class Folders {
  let base: URL

  init() throws {
    base = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("listener-probe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
  }

  func make(_ relativePath: String) throws -> URL {
    let folder = base.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  func link(_ relativePath: String, to target: URL) throws -> URL {
    let link = base.appendingPathComponent(relativePath)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    return link
  }

  /// What `cd -P "$dir" && pwd` prints, which is how `run.sh` names itself.
  func physical(_ folder: URL) throws -> String {
    let resolved = try #require(realpath(folder.path, nil))
    defer { free(resolved) }
    return String(cString: resolved)
  }

  func cleanUp() { try? FileManager.default.removeItem(at: base) }
}

@Test func aRunnerUnderPrivateVarIsFoundByThePathItRunsFrom() throws {
  // Settings stores the standardized spelling, which drops `/private`; the
  // listener runs from the one `cd -P` printed, which keeps it.
  let folders = try Folders()
  defer { folders.cleanUp() }
  let stored = try folders.make("runner").standardizedFileURL
  let physical = try folders.physical(stored)
  try #require(physical != stored.path)

  let listing = "\(physical)/bin/Runner.Listener run\n"

  #expect(probe(listing).blockingIsRunning(inDirectory: stored) == true)
}

@Test func aRunnerReachedThroughASymlinkedFolderIsFoundByThePathItRunsFrom() throws {
  let folders = try Folders()
  defer { folders.cleanUp() }
  let real = try folders.make("volume/runners")
  let linked = try folders.link("runners", to: real)
  _ = try folders.make("volume/runners/actions-runner")
  // Settings keeps the link in the path, and `cd -P` resolves it away.
  let stored = linked.appendingPathComponent("actions-runner")

  let listing = "\(try folders.physical(stored))/bin/Runner.Listener run\n"

  #expect(probe(listing).blockingIsRunning(inDirectory: stored) == true)
}

@Test func aListenerLaunchedThroughALinkStillBelongsToTheFolderItLinksTo() throws {
  // The other way round: the folder stored by its physical path, a listener
  // started by a spelling that goes through a link. Comparing only the stored
  // side's names would miss it.
  let folders = try Folders()
  defer { folders.cleanUp() }
  let real = try folders.make("volume/actions-runner")
  let linked = try folders.link("actions-runner", to: real)
  let stored = URL(fileURLWithPath: try folders.physical(real))

  let listing = "\(linked.path)/bin/Runner.Listener run\n"

  #expect(probe(listing).blockingIsRunning(inDirectory: stored) == true)
}

@Test func aRelaunchingHelperIsFoundByThePathItRunsFrom() throws {
  // `run.sh` starts the helper from the same `cd -P` folder as the listener.
  let folders = try Folders()
  defer { folders.cleanUp() }
  let stored = try folders.make("runner").standardizedFileURL

  let listing = "/bin/bash \(try folders.physical(stored))/run-helper.sh\n"

  #expect(probe(listing).blockingIsRunning(inDirectory: stored) == true)
}

@Test func anotherFolderUnderItsOwnPhysicalPathIsStillNotThisRunner() throws {
  let folders = try Folders()
  defer { folders.cleanUp() }
  let stored = try folders.make("actions-runner")
  let neighbour = try folders.physical(try folders.make("actions-runner-two"))
  let physical = try folders.physical(stored)

  let listing = """
    \(neighbour)/bin/Runner.Listener run
    \(physical)/bin/Runner.ListenerOld run
    """

  #expect(probe(listing).blockingIsRunning(inDirectory: stored) == false)
}

@Test func aRelativeLaunchIsNotMistakenForAFolderNamedFromHere() throws {
  // Relative to a working directory this app cannot see. Resolved from the
  // app's own instead, it would name whichever folder that happens to be.
  let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

  #expect(
    probe("./bin/Runner.Listener run\n").blockingIsRunning(inDirectory: here) == false)
}

@Test func aProcessListingThatFailedSaysNothingRatherThanNo() {
  // The same rule `LaunchctlProbe` follows, for the same reason: folding "could
  // not ask" into "not running" draws a live runner as stopped, with its
  // controls greyed out.
  #expect(probe("", exitCode: 1).blockingIsRunning(inDirectory: directory) == nil)
}

@Test func aListingThatWouldNotLaunchSaysNothingEither() {
  let fake = FakeCommandRunner()
  fake.failingExecutables = ["/usr/bin/env"]

  #expect(
    ListenerProcessProbe(commandRunner: fake, userID: userID)
      .blockingIsRunning(inDirectory: directory) == nil)
}

/// The real process table, behind a flag.
///
/// Everything above proves the probe reads a listing a test wrote. Nothing
/// there can catch it being wrong about `ps` — a flag that stopped printing
/// the full command, a runner release that renamed its binary. Those only fail
/// against the real thing, and they fail silently: a runner that is plainly
/// running, drawn as stopped.
///
/// ```sh
/// STANDFAST_LISTENER_DIR=~/actions-runner-standfast swift test --filter LiveListener
/// ```
private let liveDirectory = ProcessInfo.processInfo.environment["STANDFAST_LISTENER_DIR"]

@Test(.enabled(if: liveDirectory != nil))
func theRealProcessTableShowsARunnerThatIsRunning() throws {
  let directory = URL(
    fileURLWithPath: NSString(string: liveDirectory!).expandingTildeInPath)

  #expect(ListenerProcessProbe().blockingIsRunning(inDirectory: directory) == true)
  // And a sibling that does not exist is not running, which is the half a
  // prefix match would get wrong on a real path.
  #expect(
    ListenerProcessProbe()
      .blockingIsRunning(
        inDirectory: directory.deletingLastPathComponent()
          .appendingPathComponent(directory.lastPathComponent + "-nope")) == false)
}
