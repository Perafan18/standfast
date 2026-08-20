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
  /// One resolved state with separate stamps for its two sequential sources.
  /// `readAt` is immediately after launchd answered and remains the ordering
  /// evidence for stopped state and service-action ownership. `stateReadAt` is
  /// when the source that completed the verdict answered — the same instant for
  /// a local unknown/stopped result, and immediately after GitHub otherwise.
  public struct Reading: Sendable {
    public let state: RunnerState
    /// No later than this, the machine had been read. An upper bound.
    public let readAt: Date
    /// No part of this reading happened before this. A lower bound, and the
    /// only one of the two that can prove a reading is *about* something that
    /// happened at a known instant. See INV-007.
    public let beganAt: Date
    public let stateReadAt: Date
    /// What GitHub says this runner is registered as, and empty when GitHub was
    /// not reached — or answered through a path that does not carry them.
    ///
    /// Carried here rather than fetched separately because it arrives with the
    /// status this resolver already asks for. Empty never means "matches
    /// everything": see `QueuedJob.waits(forRunnerLabelled:)`.
    public let labels: [String]

    public init(
      state: RunnerState, readAt: Date, beganAt: Date? = nil, stateReadAt: Date,
      labels: [String] = []
    ) {
      self.state = state
      self.readAt = readAt
      self.beganAt = beganAt ?? readAt
      self.stateReadAt = stateReadAt
      self.labels = labels
    }
  }

  /// Nil for "could not tell", which is not the same answer as false. See
  /// `LaunchctlProbe.blockingIsRunning(label:)`.
  private let isServiceRunning: @Sendable (DiscoveredRunner) -> Bool?
  private let github: any GitHubClient
  private let gitLab: GitLabAPIClient

  public init(
    isServiceRunning: @escaping @Sendable (DiscoveredRunner) -> Bool?,
    github: any GitHubClient,
    gitLab: GitLabAPIClient = GitLabAPIClient.standard
  ) {
    self.isServiceRunning = isServiceRunning
    self.github = github
    self.gitLab = gitLab
  }

  public init(
    probe: LaunchctlProbe = LaunchctlProbe(),
    listeners: ListenerProcessProbe = ListenerProcessProbe(),
    gitLabRunners: GitLabRunnerProcessProbe = GitLabRunnerProcessProbe(),
    github: any GitHubClient = TokenFirstGitHubClient.standard,
    gitLab: GitLabAPIClient = GitLabAPIClient.standard
  ) {
    self.init(
      isServiceRunning: { runner in
        switch runner.installation {
        case .launchAgent:
          probe.blockingIsRunning(label: runner.label)
        // No launchd job exists for one of these, and asking anyway would get
        // a confident "not running" for every hand-started runner on the
        // machine — each drawn as stopped, with its controls greyed out. What
        // it leaves instead is a process out of its own directory.
        case .manual:
          listeners.blockingIsRunning(inDirectory: runner.directory)
        // One machine-wide process serves every GitLab runner, so the local
        // half of the question is per machine and this probe takes no
        // argument.
        case .gitLabService:
          gitLabRunners.blockingIsRunning()
        }
      }, github: github, gitLab: gitLab)
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
    await reading(for: runner, clock: Date.init).state
  }

  /// Resolves and stamps the local probe independently for each runner.
  public func reading(
    for runner: DiscoveredRunner, clock: @escaping @Sendable () -> Date
  ) async -> Reading {
    await offCooperativePool { blockingReading(for: runner, clock: clock) }
  }

  /// Blocks the calling thread — first on `launchctl`, then on `gh` doing
  /// network I/O — for up to the command runner's timeout each time. Safe to
  /// call directly only from a thread that is yours to block, which rules out
  /// the main actor and the cooperative pool behind every `Task`. Prefer the
  /// `async` overload above, which makes the hop for you.
  public func blockingState(for runner: DiscoveredRunner) -> RunnerState {
    blockingReading(for: runner, clock: Date.init).state
  }

  func blockingReading(
    for runner: DiscoveredRunner, clock: @escaping @Sendable () -> Date
  ) -> Reading {
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
    // Both ends of the interval this reading covers, because two callers need
    // opposite bounds and one stamp cannot be both (INV-007).
    //
    //   * `beganAt` is a lower bound: no part of this reading happened before
    //     it. `SettlingWindow` needs that to refuse a reading which may predate
    //     the click that opened the window — a `launchctl` that started before
    //     the user pressed Restart and took seconds would otherwise come back
    //     looking newer than the click, be believed, and raise a warning
    //     triangle over a restart going perfectly well.
    //   * `readAt` is an upper bound: by then the machine had been read.
    //     Reconciling an expected stop needs that, because a probe deliberately
    //     held until after Stop completed is genuinely post-click evidence, and
    //     dating it from before the scan would misfile it as stale and announce
    //     a runner that stopped "by itself".
    let beganAt = clock()
    let running = isServiceRunning(runner)
    let readAt = clock()
    guard let running else {
      return Reading(
        state: .unknown(.serviceStateUnreadable), readAt: readAt, beganAt: beganAt,
        stateReadAt: readAt)
    }
    guard running else {
      return Reading(state: .stopped, readAt: readAt, beganAt: beganAt, stateReadAt: readAt)
    }

    do {
      // Which provider gets the question is the scope's decision, made here
      // rather than behind the client protocol: sending a GitLab runner to the
      // GitHub client would ask the wrong API with the wrong token and, on
      // failure, hand the user the wrong instruction.
      let remote: RemoteStatus
      if case .gitLab(let host) = runner.scope {
        remote = try gitLab.blockingRunnerStatus(id: runner.agentId, instanceHost: host)
      } else {
        remote = try github.blockingRunnerStatus(id: runner.agentId, scope: runner.scope)
      }
      let stateReadAt = clock()
      // Connection before occupation, and the order is load-bearing: GitHub
      // describes a machine that died mid-job as offline with the job still
      // assigned to it. Calling that "busy" would suggest work is progressing
      // when nothing is; what needs fixing is the connection.
      if !remote.online {
        // Labels still travel: a disconnected runner is exactly the one whose
        // queued work is worth naming, because nothing is going to take it.
        return Reading(
          state: .disconnected, readAt: readAt, beganAt: beganAt,
          stateReadAt: stateReadAt, labels: remote.labels)
      }
      return Reading(
        state: remote.busy ? .busy : .idle, readAt: readAt, beganAt: beganAt,
        stateReadAt: stateReadAt, labels: remote.labels)
    } catch let failure as GitHubError {
      return Reading(
        state: .unknown(UnknownReason(failure)), readAt: readAt, beganAt: beganAt,
        stateReadAt: clock())
    } catch let failure as GitLabError {
      return Reading(
        state: .unknown(UnknownReason(failure)), readAt: readAt, beganAt: beganAt,
        stateReadAt: clock())
    } catch {
      // Another client behind the same protocol may throw something else; it
      // still has not answered.
      return Reading(
        state: .unknown(.noAnswer), readAt: readAt, beganAt: beganAt,
        stateReadAt: clock())
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
