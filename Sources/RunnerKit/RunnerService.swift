import Foundation

/// Why the state could not be determined. Kept as data rather than a string so
/// the UI can suggest the right fix instead of shrugging: each case has a
/// different next step, and "unknown" on its own has none.
public enum UnknownReason: Equatable, Sendable {
  /// No `gh` on PATH and none at the usual install prefixes.
  case cliUnavailable
  /// `gh` is installed but holds no credentials.
  case notAuthenticated
  /// `gh` ran, was authenticated, and still said nothing usable: no network, a
  /// token without the scope for this endpoint, a runner GitHub has forgotten.
  case noAnswer
}

extension UnknownReason {
  init(_ error: GitHubError) {
    switch error {
    case .cliUnavailable: self = .cliUnavailable
    case .notAuthenticated: self = .notAuthenticated
    case .noAnswer: self = .noAnswer
    }
  }
}

public enum RunnerState: Equatable, Sendable {
  /// Registered, connected, waiting for work.
  case idle
  /// Executing a job right now.
  case busy
  /// Running locally but GitHub does not see it. Worth its own case: "the
  /// process is up" and "GitHub will send it work" are different claims, and
  /// only the second one matters.
  case disconnected
  /// The LaunchAgent is not running.
  case stopped
  case unknown(UnknownReason)
}

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

  /// Does network I/O on the calling thread. Call it off the main actor.
  public func state(for runner: DiscoveredRunner) -> RunnerState {
    // Asked first, and allowed to settle it alone. A stopped service is the
    // one thing known for certain: GitHub keeps calling a just-stopped runner
    // online for a few seconds, so trusting it here would show "idle" right
    // after the user clicked Stop. And since no answer could change this
    // verdict, asking would spend an API call per stopped runner per refresh —
    // all day, on a result thrown away.
    guard isServiceRunning(runner) else { return .stopped }

    do {
      let remote = try github.runnerStatus(id: runner.agentId, scope: runner.scope)
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
