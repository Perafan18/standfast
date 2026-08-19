import Foundation

/// Asks GitHub directly, with a token this app owns.
///
/// The reason it exists: `GHCommandLineClient` borrows whatever credentials
/// `gh` already has, which means the app's ability to answer at all depends on
/// a command-line tool being installed, authenticated, and well-behaved.
/// Someone who does not live in a terminal has no reason to install `gh` to use
/// a menu bar app, and a dependency on an external process is not an honest
/// base for a claim about remote state.
public struct GitHubAPIClient: GitHubClient {
  /// GitHub refuses requests without one.
  public static let userAgent = "Standfast"
  /// Pinned rather than left to default. GitHub changes behaviour by version,
  /// and an unpinned client is one that breaks on a date nobody chose.
  public static let apiVersion = "2022-11-28"
  public static let defaultBaseURL = URL(string: "https://api.github.com")!

  private static let notModified = 304
  private static let unauthorized = 401
  private static let forbidden = 403
  private static let tooManyRequests = 429

  private let tokens: any GitHubTokenStoring
  private let http: any HTTPPerforming
  private let baseURL: URL
  private let cache = StatusCache()

  /// The last answer GitHub gave about each runner, and the tag it came with.
  ///
  /// A reference rather than state on the struct, so copies of the client share
  /// one cache — the same reason `GHCommandLineClient` remembers where `gh`
  /// was found. Losing it costs correctness nothing: an unremembered tag makes
  /// the next request unconditional, which is simply the first request again.
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

  public init(
    token tokens: any GitHubTokenStoring,
    http: any HTTPPerforming,
    baseURL: URL = GitHubAPIClient.defaultBaseURL
  ) {
    self.tokens = tokens
    self.http = http
    self.baseURL = baseURL
  }

  public func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    let url = baseURL.appendingPathComponent(scope.runnerAPIPath(id: id))
    let remembered = cache.entry(for: url)
    let response = try get(url, ifNoneMatch: remembered?.etag)

    // Not modified, and no body to read. GitHub does not charge this against
    // the rate limit, which is what makes a fifteen-second poll affordable on
    // a personal token: at one call per runner per tick, an app watching a
    // handful of runners would otherwise spend the hourly budget re-asking a
    // question whose answer had not changed.
    if response.statusCode == Self.notModified {
      // A 304 for something never successfully read is GitHub answering a
      // question it was not asked. There is nothing to return but silence.
      guard let remembered else { throw GitHubError.noAnswer }
      return remembered.status
    }

    let status = try status(from: response)
    if let etag = response.header("Etag") {
      cache.remember(url, StatusCache.Entry(etag: etag, status: status))
    }
    return status
  }

  private func get(_ url: URL, ifNoneMatch etag: String?) throws -> HTTPResponse {
    guard let token = try tokens.token() else { throw GitHubError.noToken }
    var headers = [
      // Bearer rather than the older `token` scheme: that one still works
      // for classic PATs and fails for the fine-grained tokens GitHub issues
      // today.
      "Authorization": "Bearer \(token)",
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": Self.apiVersion,
      "User-Agent": Self.userAgent,
    ]
    if let etag { headers["If-None-Match"] = etag }
    do {
      return try http.blockingGet(url, headers: headers)
    } catch is HTTPError {
      // No network, no DNS, no TLS. Nothing the user can fix from here, and
      // nothing this app can claim about the runner.
      throw GitHubError.noAnswer
    }
  }

  private struct RunnerPayload: Decodable {
    let status: String
    let busy: Bool
  }

  /// Both questions go through the same token and the same hourly budget, so
  /// both have to be able to name the same failures. Only one of them being
  /// able to was an accident of which was written first.
  private func rejecting(_ response: HTTPResponse) throws {
    // A rejected token has a fix a person can act on. "Could not tell" does
    // not, and collapsing the two leaves the user with nothing to try.
    guard response.statusCode != Self.unauthorized else {
      throw GitHubError.notAuthenticated
    }
    // Running out of budget is not silence, and the difference matters: the fix
    // is time, or fewer runners. GitHub says it two ways — 429 for a secondary
    // limit, and 403 with the remaining count at zero for the primary one. A
    // 403 with budget left is something else entirely: a token whose scopes do
    // not cover this endpoint, which no amount of waiting repairs.
    if response.statusCode == Self.tooManyRequests
      || (response.statusCode == Self.forbidden
        && response.header("x-ratelimit-remaining") == "0")
    {
      throw GitHubError.rateLimited
    }
  }

  private func status(from response: HTTPResponse) throws -> RemoteStatus {
    try rejecting(response)
    guard response.statusCode == 200,
      let payload = try? JSONDecoder().decode(RunnerPayload.self, from: response.body)
    else { throw GitHubError.noAnswer }
    // Checked against both spellings rather than read as "online, or else
    // offline". Treating an unrecognised status as online hides a runner that
    // will never be sent work; treating it as offline raises the alarm about a
    // healthy one. "Could not tell" is the only honest third answer.
    switch payload.status {
    case "online": return RemoteStatus(online: true, busy: payload.busy)
    case "offline": return RemoteStatus(online: false, busy: payload.busy)
    default: throw GitHubError.noAnswer
    }
  }
}

extension GitHubAPIClient: RunnerReleaseChecking {
  /// Where the newest published runner is announced.
  ///
  /// Deliberately not cached by tag the way runner status is. It is asked
  /// rarely — nothing calls it on the refresh loop — so the conditional
  /// request would save a budget that this question never threatens, and a
  /// shared cache between two questions this different is a way for one to
  /// answer for the other.
  public static let latestReleasePath = "repos/actions/runner/releases/latest"

  private struct ReleasePayload: Decodable {
    let tagName: String
  }

  public func blockingLatestRunnerRelease() throws -> RunnerVersion {
    let response = try get(
      baseURL.appendingPathComponent(Self.latestReleasePath), ifNoneMatch: nil)
    try rejecting(response)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard response.statusCode == 200,
      let payload = try? decoder.decode(ReleasePayload.self, from: response.body),
      let version = RunnerVersion(payload.tagName)
    else { throw GitHubError.noAnswer }
    return version
  }
}
