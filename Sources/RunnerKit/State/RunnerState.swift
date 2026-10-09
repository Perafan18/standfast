import Foundation

/// Why the state could not be determined. Kept as data rather than a string so
/// the UI can suggest the right fix instead of shrugging: each case has a
/// different next step, and "unknown" on its own has none.
public enum UnknownReason: Equatable, Sendable {
  /// No `gh` on PATH and none at the usual install prefixes.
  case cliUnavailable
  /// `gh` is installed but holds no credentials.
  case notAuthenticated
  /// GitHub was asked, by the token or by `gh`, and said nothing usable: no
  /// network, a token without the scope for this endpoint, a runner GitHub has
  /// forgotten, or a status this version does not recognise.
  case noAnswer
  /// Nothing is stored for this app to ask GitHub with, and no `gh` answered
  /// either. Its own case because its instruction is the only one that points
  /// at this app's own Settings rather than at a terminal.
  case noToken
  /// GitHub answered, and what it said was that too much has been asked of
  /// it. Its own case because the fix is time, and every other reason here has
  /// a fix that is an action.
  case rateLimited
  /// The GitLab mirrors of the four reasons above. Separate cases rather than
  /// a provider parameter, because each reason *is* its instruction and the
  /// instructions differ: "add a GitLab token in Settings" is not "run gh auth
  /// login", and a runner whose fix points at the wrong provider is worse than
  /// one that says nothing.
  case gitLabNoToken
  case gitLabNotAuthenticated
  case gitLabRateLimited
  case gitLabSilent
  /// `launchctl` could not be asked whether the service is loaded: it would not
  /// launch, or it was still running when the timeout expired. Its own case
  /// because the other three all mean "the local half is fine and GitHub is
  /// not", and this one means the opposite — so the instruction differs too.
  case serviceStateUnreadable
  /// The fleet supervisor is running but has not attached an ephemeral runner
  /// registration to this stable slot yet.
  case managedFleetWaiting
  /// The supervisor snapshot is too old, or its remote observation could not
  /// answer. Standfast must not keep presenting its last state as current.
  case managedFleetStatusUnavailable
  /// GitHub refused the token stored in Settings. Not `notAuthenticated`: that
  /// instruction is `gh auth login`, and with a token stored `gh` is never
  /// asked, so only a new token fixes this.
  case tokenRefused
  /// A token is stored and the Keychain would not hand it over, so neither
  /// host was asked. One case per provider, like the GitLab mirrors above.
  case tokenUnreadable
  case gitLabTokenUnreadable
  /// The instance is served over plain http, and a token is only ever sent
  /// over https. A setting of the instance, not a failure of this scan.
  case gitLabInsecure
  /// GitLab answered that the runner is paused there. An answer rather than a
  /// failure to read, so it neither stales the freshness line nor posts a
  /// banner: a pause is how somebody drains a runner on purpose.
  case gitLabPaused
}

extension UnknownReason {
  init(_ error: GitHubError) {
    switch error {
    case .cliUnavailable: self = .cliUnavailable
    case .notAuthenticated: self = .notAuthenticated
    case .noAnswer: self = .noAnswer
    case .noToken: self = .noToken
    case .rateLimited: self = .rateLimited
    case .tokenRefused: self = .tokenRefused
    case .tokenUnreadable: self = .tokenUnreadable
    // Unreachable from a status call: no scope lacks an endpoint for reading
    // one runner, only for listing queued work. Mapped rather than crashed,
    // and mapped to the honest answer — if it ever did arrive here, this app
    // would not know the state.
    case .notAvailableForScope: self = .noAnswer
    }
  }

  init(_ error: GitLabError) {
    switch error {
    case .noToken: self = .gitLabNoToken
    case .notAuthenticated: self = .gitLabNotAuthenticated
    case .rateLimited: self = .gitLabRateLimited
    case .noAnswer: self = .gitLabSilent
    case .tokenUnreadable: self = .gitLabTokenUnreadable
    case .insecureInstance: self = .gitLabInsecure
    case .paused: self = .gitLabPaused
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
