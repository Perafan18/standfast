import Foundation

/// Where a runner is registered. Determines both the API path used to ask
/// about it and the settings page a user gets sent to.
public enum RunnerScope: Equatable, Sendable {
  case repository(owner: String, name: String)
  case organization(String)
  case enterprise(String)
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
    }
  }

  public var displayName: String {
    switch self {
    case .repository(let owner, let name): "\(owner)/\(name)"
    case .organization(let org): org
    case .enterprise(let slug): slug
    }
  }
}
