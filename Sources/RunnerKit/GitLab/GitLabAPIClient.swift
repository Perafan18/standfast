import Foundation

/// Why GitLab could not be asked. GitLab's own vocabulary, not `GitHubError`,
/// because these reach the menu as instructions and "run gh auth login" is the
/// wrong advice for a GitLab token.
public enum GitLabError: Error, Equatable {
  /// Nothing stored to ask with. The fix is a GitLab personal access token in
  /// Settings — and unlike GitHub there is no CLI to fall back to.
  case noToken
  /// A token was tried and refused.
  case notAuthenticated
  /// GitLab said too much has been asked; the fix is time.
  case rateLimited
  /// Asked and nothing usable came back.
  case noAnswer
}

/// Asks a GitLab instance about one of its runners.
///
/// The instance host travels with every question rather than living in the
/// client, because it comes from each runner's own `config.toml` — which is
/// how a self-managed instance costs nothing extra: the URL was never
/// hardcoded to gitlab.com.
public struct GitLabAPIClient: Sendable {
  /// The GitLab token's Keychain account, beside the GitHub one.
  public static let keychainAccount = "gitlab-token"
  public static let userAgent = "Standfast"

  private let tokens: any GitHubTokenStoring
  private let http: any HTTPPerforming
  private let cache = StatusCache()

  /// The one the app runs on. Shared for the same reason the GitHub client's
  /// is: the conditional-request cache lives on the instance.
  public static let standard = GitLabAPIClient(
    token: KeychainTokenStore(account: GitLabAPIClient.keychainAccount),
    http: URLSessionHTTPClient())

  public init(token tokens: any GitHubTokenStoring, http: any HTTPPerforming) {
    self.tokens = tokens
    self.http = http
  }

  /// The last answer per runner and the tag it came with. GitLab sends ETags
  /// and honours `If-None-Match`; unlike GitHub, its documentation makes no
  /// promise about 304s and the rate limit, so this claims saved bandwidth and
  /// re-parsing only.
  private final class StatusCache: @unchecked Sendable {
    struct Entry {
      let etag: String
      let status: RemoteStatus
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]

    func entry(for url: URL) -> Entry? {
      lock.lock()
      defer { lock.unlock() }
      return entries[url]
    }

    func remember(_ url: URL, _ entry: Entry) {
      lock.lock()
      defer { lock.unlock() }
      entries[url] = entry
    }
  }

  private struct RunnerPayload: Decodable {
    let status: String
    /// `idle` or `active`; absent on GitLab releases older than 16.x. Absent
    /// reads as not busy — the one guess in this file, and the conservative
    /// one: it can miss a busy badge, never invent one.
    let jobExecutionStatus: String?
    let tagList: [String]?
  }

  public func blockingRunnerStatus(id: Int, instanceHost: String) throws -> RemoteStatus {
    // A Keychain that would not answer and an empty one both end here: with no
    // GitLab token, "not asked" is the honest state, and there is no CLI to
    // fall back to the way the GitHub path has.
    guard let token = (try? tokens.token()) ?? nil else { throw GitLabError.noToken }
    guard let url = URL(string: "https://\(instanceHost)/api/v4/runners/\(id)") else {
      throw GitLabError.noAnswer
    }

    let remembered = cache.entry(for: url)
    var headers = [
      // PRIVATE-TOKEN is the header GitLab documents for personal access
      // tokens, which is exactly what the Settings field asks for.
      "PRIVATE-TOKEN": token,
      "User-Agent": Self.userAgent,
    ]
    if let etag = remembered?.etag { headers["If-None-Match"] = etag }

    let response: HTTPResponse
    do {
      response = try http.blockingGet(url, headers: headers)
    } catch is HTTPError {
      throw GitLabError.noAnswer
    }

    if response.statusCode == 304 {
      guard let remembered else { throw GitLabError.noAnswer }
      return remembered.status
    }
    guard response.statusCode != 401, response.statusCode != 403 else {
      throw GitLabError.notAuthenticated
    }
    guard response.statusCode != 429 else { throw GitLabError.rateLimited }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard response.statusCode == 200,
      let payload = try? decoder.decode(RunnerPayload.self, from: response.body)
    else { throw GitLabError.noAnswer }

    // GitLab has several words for "not connected"; this app has one question:
    // will this machine be handed work? Only "online" answers yes, and a word
    // this version has not met is not guessed at — the same rule the GitHub
    // client follows, for the same reason.
    let online: Bool
    switch payload.status {
    case "online": online = true
    case "offline", "stale", "never_contacted": online = false
    default: throw GitLabError.noAnswer
    }

    let status = RemoteStatus(
      online: online,
      busy: payload.jobExecutionStatus == "active",
      labels: payload.tagList ?? [])
    if let etag = response.header("Etag") {
      cache.remember(url, StatusCache.Entry(etag: etag, status: status))
    }
    return status
  }
}
