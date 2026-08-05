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
  private let isServiceRunning: @Sendable (DiscoveredRunner) -> Bool
  private let github: any GitHubClient

  public init(
    isServiceRunning: @escaping @Sendable (DiscoveredRunner) -> Bool,
    github: any GitHubClient
  ) {
    self.isServiceRunning = isServiceRunning
    self.github = github
  }

  public init(
    probe: LaunchctlProbe = LaunchctlProbe(),
    github: any GitHubClient = GHCommandLineClient()
  ) {
    self.init(isServiceRunning: { probe.isRunning(label: $0.label) }, github: github)
  }

  /// Resolves one runner's state without tying up a thread the runtime needs.
  ///
  /// This is the entry point to use. `blockingState(for:)` parks a whole thread
  /// inside `waitUntilExit()` — twice per call, for as long as the command
  /// timeout allows. Swift's cooperative pool has only as many threads as the
  /// machine has cores, and *both* `Task {}` and `Task.detached {}` run there,
  /// so a task group resolving N runners with the network hanging would stall
  /// N of those threads at once and starve everything else in the app,
  /// including the UI. Dispatching to `DispatchQueue.global()` moves the
  /// blocking to a pool that is allowed to grow instead.
  public func state(for runner: DiscoveredRunner) async -> RunnerState {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: blockingState(for: runner))
      }
    }
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
    guard isServiceRunning(runner) else { return .stopped }

    do {
      let remote = try github.runnerStatus(id: runner.agentId, scope: runner.scope)
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
}
