import Foundation

/// Combines the two things worth knowing about a runner into one answer.
///
/// They are deliberately separate sources. `launchctl` says whether the local
/// process is alive; the GitHub API says whether GitHub considers the runner
/// online and whether it is working. They disagree more often than you would
/// expect — a runner whose token has expired keeps its process happily running
/// while GitHub has written it off — and showing only the local view would
/// report "fine" for a runner that will never receive another job.
///
/// Stateless and per-runner: one resolver serves every runner on the machine.
public struct RunnerStateResolver: Sendable {
  /// Nil for "could not tell", which is not the same answer as false. See
  /// `LaunchctlProbe.blockingIsRunning(label:)`.
  private let isServiceRunning: @Sendable (DiscoveredRunner) -> Bool?
  private let github: any GitHubClient

  public init(
    isServiceRunning: @escaping @Sendable (DiscoveredRunner) -> Bool?,
    github: any GitHubClient
  ) {
    self.isServiceRunning = isServiceRunning
    self.github = github
  }

  public init(
    probe: LaunchctlProbe = LaunchctlProbe(),
    github: any GitHubClient = GHCommandLineClient()
  ) {
    self.init(
      isServiceRunning: { probe.blockingIsRunning(label: $0.label) }, github: github)
  }

  /// Resolves one runner's state without tying up a thread the runtime needs.
  ///
  /// This is the entry point to use. `blockingState(for:)` parks a whole thread
  /// inside `waitUntilExit()` — twice per call, for as long as the command
  /// timeout allows. Swift's cooperative pool has only as many threads as the
  /// machine has cores, and *both* `Task {}` and `Task.detached {}` run there,
  /// so a task group resolving N runners with the network hanging would stall
  /// N of those threads at once and starve everything else in the app,
  /// including the UI. `offCooperativePool` moves the blocking to a pool that
  /// is allowed to grow instead.
  public func state(for runner: DiscoveredRunner) async -> RunnerState {
    await offCooperativePool { blockingState(for: runner) }
  }

  /// Blocks the calling thread — first on `launchctl`, then on `gh` doing
  /// network I/O — for up to the command runner's timeout each time. Safe to
  /// call directly only from a thread that is yours to block, which rules out
  /// the main actor and the cooperative pool behind every `Task`. Prefer the
  /// `async` overload above, which makes the hop for you.
  public func blockingState(for runner: DiscoveredRunner) -> RunnerState {
    // Asked first, and allowed to settle it alone. A stopped service is the
    // one thing known for certain: GitHub keeps calling a just-stopped runner
    // online for a few seconds, so trusting it here would show "idle" right
    // after the user clicked Stop. And since no answer could change this
    // verdict, asking would spend an API call per stopped runner per refresh —
    // all day, on a result thrown away.
    //
    // A probe that could not tell settles nothing, and it is not allowed to
    // masquerade as either answer. Claiming `.stopped` greys out Stop and
    // Restart on a runner that may well be up; asking GitHub instead would put
    // the whole verdict on the source that cannot separate "stopped" from
    // "disconnected" — that separation is the only thing the local probe is
    // here for. Saying so is the honest report, and the menu has a line for it.
    guard let running = isServiceRunning(runner) else {
      return .unknown(.serviceStateUnreadable)
    }
    guard running else { return .stopped }

    do {
      let remote = try github.blockingRunnerStatus(
        id: runner.agentId, scope: runner.scope)
      // Connection before occupation, and the order is load-bearing: GitHub
      // describes a machine that died mid-job as offline with the job still
      // assigned to it. Calling that "busy" would suggest work is progressing
      // when nothing is; what needs fixing is the connection.
      if !remote.online { return .disconnected }
      return remote.busy ? .busy : .idle
    } catch let failure as GitHubError {
      return .unknown(UnknownReason(failure))
    } catch {
      // Another client behind the same protocol may throw something else; it
      // still has not answered.
      return .unknown(.noAnswer)
    }
  }

  /// The same verdict, with nothing taken from launchd on trust — for the one
  /// caller that is about to delete four gigabytes.
  ///
  /// `blockingState(for:)` lets the local probe settle `.stopped` alone, and
  /// for the menu that is right, for the two reasons written above it. For a
  /// deletion it is wrong, and `RunnerState.stopped`'s own wording says why:
  /// "the LaunchAgent is not running" is a statement about launchd, not about
  /// the runner process. `svc.sh stop; ./run.sh` is GitHub's documented
  /// interactive mode and the ordinary way to debug a failing job — the plist
  /// stays on disk, so this app still lists the runner, `launchctl list` no
  /// longer names it, and there is a build in flight behind a verdict of
  /// `.stopped`. Deleting `_actions` under it is the worse half: the runner
  /// resolves each `uses:` step out of `_work/_actions` as it reaches it, so
  /// the rename breaks the next step rather than costing a cache miss.
  ///
  /// So GitHub is asked first here, and `.stopped` comes back only when both
  /// sources agree there is nothing running. The extra API call is spent once
  /// per click rather than once per runner per refresh, which is the whole of
  /// why the other one does it the other way round.
  public func blockingConfirmedState(for runner: DiscoveredRunner) -> RunnerState {
    let remote: RemoteStatus
    do {
      remote = try github.blockingRunnerStatus(id: runner.agentId, scope: runner.scope)
    } catch let failure as GitHubError {
      return .unknown(UnknownReason(failure))
    } catch {
      return .unknown(.noAnswer)
    }

    // A busy assignment means the runner may still be executing a job even if
    // its connection has gone away. That alone refuses destructive work, so
    // launchctl has no bearing on the verdict and must not be consulted.
    if remote.busy { return .busy }

    guard remote.online else {
      // Offline on its own is the shape of a runner grinding through a build
      // behind a dead connection, so the local probe has to agree there is no
      // process — and it has to say so. "I could not tell" is not a licence to
      // delete anything. That GitHub answered at all is what makes this sound:
      // a runner working through a job on a reachable network is online, so
      // offline plus no local process leaves nothing that could be building.
      guard let running = isServiceRunning(runner) else {
        return .unknown(.serviceStateUnreadable)
      }
      return running ? .disconnected : .stopped
    }
    return .idle
  }
}
