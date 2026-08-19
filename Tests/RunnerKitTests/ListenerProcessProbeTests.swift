import Foundation
import Testing

@testable import RunnerKit

private let directory = URL(fileURLWithPath: "/Users/ci/actions-runner-standfast")
private let psCommand = ["/bin/ps", "-Awwo", "command="]

private func probe(_ output: String, exitCode: Int32 = 0) -> ListenerProcessProbe {
  let fake = FakeCommandRunner([psCommand: output])
  fake.exitCodes[psCommand] = exitCode
  return ListenerProcessProbe(commandRunner: fake)
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

  // The worker is a job, not the listener, and `run.sh` is the shell that
  // starts one. Neither answers "is this runner connected to GitHub".
  #expect(probe(noise).blockingIsRunning(inDirectory: directory) == false)
}

@Test func aProcessListingThatFailedSaysNothingRatherThanNo() {
  // The same rule `LaunchctlProbe` follows, for the same reason: folding "could
  // not ask" into "not running" draws a live runner as stopped, with its
  // controls greyed out.
  #expect(probe("", exitCode: 1).blockingIsRunning(inDirectory: directory) == nil)
}

@Test func aListingThatWouldNotLaunchSaysNothingEither() {
  let fake = FakeCommandRunner()
  fake.failingExecutables = ["/bin/ps"]

  #expect(
    ListenerProcessProbe(commandRunner: fake)
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
