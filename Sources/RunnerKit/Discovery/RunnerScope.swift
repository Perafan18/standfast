import Foundation

/// Where a runner is registered. Determines both the API path used to ask
/// about it and the settings page a user gets sent to.
public enum RunnerScope: Equatable, Sendable {
  case repository(owner: String, name: String)
  case organization(String)
  case enterprise(String)
  /// A GitLab instance. Deliberately no project/group split: `config.toml`
  /// does not say which a runner is — only the API does, with a token — and
  /// inventing one here would be a guess wearing a type. The instance alone is
  /// enough to ask `GET /api/v4/runners/{id}` and to open it in a browser.
  case gitLab(instance: GitLabInstance)
}

extension RunnerScope {
  /// Derived from `.runner`'s `gitHubUrl`, which is unambiguous — unlike the
  /// LaunchAgent label, where `owner-repo-with-dashes` cannot be split back.
  public init?(gitHubURL: String) {
    // Scheme and host are what separate a URL from a string that merely
    // happens to contain a slash: "n/a" and an SSH remote both split into two
    // components and would otherwise pass for a repository.
    guard let url = URL(string: gitHubURL), url.scheme != nil,
      let host = url.host, !host.isEmpty
    else { return nil }
    let parts = url.path.split(separator: "/").map(String.init)
    switch parts.count {
    case 2 where parts[0] == "enterprises": self = .enterprise(parts[1])
    case 2: self = .repository(owner: parts[0], name: parts[1])
    case 1: self = .organization(parts[0])
    default: return nil
    }
  }

  public func runnerAPIPath(id: Int) -> String {
    switch self {
    case .repository(let owner, let name): "repos/\(owner)/\(name)/actions/runners/\(id)"
    case .organization(let org): "orgs/\(org)/actions/runners/\(id)"
    case .enterprise(let slug): "enterprises/\(slug)/actions/runners/\(id)"
    // Never asked of the GitHub client. The resolver routes a GitLab runner to
    // the GitLab client before any path is built, and if that routing ever
    // broke, a fatalError here would take the whole fleet down over one
    // runner. An impossible path fails as one unresolvable runner instead.
    case .gitLab(let instance): "unreachable/gitlab/\(instance.name)/runners/\(id)"
    }
  }

  /// Where queued work for this scope can be listed, and **nil where GitHub
  /// has no such endpoint**.
  ///
  /// The question only exists per repository. There is no org-wide or
  /// enterprise-wide listing of queued work, so a runner registered at those
  /// levels cannot be told what is waiting for it — and this returns nil so
  /// that fact travels, rather than an empty list that would read as "nothing
  /// is waiting".
  public var queuedRunsAPIPath: String? {
    switch self {
    case .repository(let owner, let name): "repos/\(owner)/\(name)/actions/runs"
    case .organization, .enterprise, .gitLab: nil
    }
  }

  public var settingsURL: URL {
    switch self {
    case .repository(let owner, let name):
      URL(string: "https://github.com/\(owner)/\(name)/settings/actions/runners")!
    case .organization(let org):
      URL(string: "https://github.com/organizations/\(org)/settings/actions/runners")!
    case .enterprise(let slug):
      URL(string: "https://github.com/enterprises/\(slug)/settings/actions/runners")!
    // The instance itself. Which project or group this runner belongs to is
    // exactly what `config.toml` does not say, so any deeper page would be a
    // guess dressed as a link.
    case .gitLab(let instance):
      instance.baseURL
    }
  }

  /// The repository-wide workflow runs page, where GitHub has one honest
  /// destination spanning every workflow this runner may execute.
  ///
  /// Organization and enterprise runners serve many repositories and GitHub
  /// provides no equivalent single runs page for that whole scope. Returning
  /// nil keeps callers from presenting their runner-registration page as job
  /// history.
  public var workflowRunsURL: URL? {
    guard case .repository(let owner, let name) = self else { return nil }
    return URL(string: "https://github.com/\(owner)/\(name)/actions")!
  }

  /// The most useful page GitHub actually provides for this scope.
  public var preferredGitHubURL: URL { workflowRunsURL ?? settingsURL }

  public var displayName: String {
    switch self {
    case .repository(let owner, let name): "\(owner)/\(name)"
    case .organization(let org): org
    case .enterprise(let slug): slug
    case .gitLab(let instance): instance.name
    }
  }
}
