import Foundation

/// Asks GitHub with this app's own token, and falls back to `gh` only when
/// there is no token to ask with.
///
/// The fallback is narrow on purpose. Exactly one failure is worth retrying
/// elsewhere — nothing has been configured yet, which is the state every
/// existing user is in and which must not turn their menu blank on the day
/// this ships. Every other failure is an answer:
///
/// - A refused token means a credential the user deliberately set up is wrong.
///   Quietly succeeding through `gh` would hide that forever, and the app would
///   drift back to depending on a tool it was built to stop depending on.
/// - A rate limit is the same account and the same budget on both paths, so
///   asking twice spends a second request to be told the same thing.
public struct TokenFirstGitHubClient:
  GitHubClient, RunnerReleaseChecking, QueuedWorkReading
{
  private let token: any GitHubClient & RunnerReleaseChecking & QueuedWorkReading
  private let cli: any GitHubClient & RunnerReleaseChecking & QueuedWorkReading

  public init(
    token: any GitHubClient & RunnerReleaseChecking & QueuedWorkReading,
    cli: any GitHubClient & RunnerReleaseChecking & QueuedWorkReading
  ) {
    self.token = token
    self.cli = cli
  }

  /// The one the app runs on.
  ///
  /// Shared rather than built per call site, and the reason is the conditional
  /// request cache inside `GitHubAPIClient`: a client rebuilt for every
  /// question knows no tags, so every request is unconditional and the rate
  /// limit comes back — silently, because unconditional requests are still
  /// correct answers.
  ///
  /// The token is re-read from the Keychain on every request rather than held.
  /// That is a syscall per runner per fifteen seconds, which is nothing, and it
  /// buys the thing that matters: a token pasted into Settings is in use by the
  /// next refresh, with no wiring between the two and no relaunch.
  public static let standard = TokenFirstGitHubClient(
    token: GitHubAPIClient(token: KeychainTokenStore(), http: URLSessionHTTPClient()),
    cli: GHCommandLineClient())

  public func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    try preferringToken {
      try token.blockingRunnerStatus(id: id, scope: scope)
    } otherwise: {
      try cli.blockingRunnerStatus(id: id, scope: scope)
    }
  }

  public func blockingLatestRunnerRelease() throws -> RunnerVersion {
    try preferringToken {
      try token.blockingLatestRunnerRelease()
    } otherwise: {
      try cli.blockingLatestRunnerRelease()
    }
  }

  /// No fallback, deliberately. `gh` could reach the same endpoints, but a
  /// fleet on that path never learns a runner's labels, so a queue read there
  /// could not be attributed to any runner — a list of jobs nobody can say are
  /// waiting for *this* machine is not an answer to the question being asked.
  public func blockingQueuedWork(in scope: RunnerScope) throws -> QueuedWork {
    try token.blockingQueuedWork(in: scope)
  }

  private func preferringToken<Answer>(
    _ withToken: () throws -> Answer, otherwise withCLI: () throws -> Answer
  ) throws -> Answer {
    do {
      return try withToken()
    } catch GitHubError.noToken {
      return try withCLI()
    }
  }
}
