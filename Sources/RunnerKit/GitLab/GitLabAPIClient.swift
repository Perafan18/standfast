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
  /// The Keychain would not hand the stored token over. Not `noToken`: "add a
  /// token" is the wrong advice to someone who already did.
  case tokenUnreadable
  /// The instance is served over plain http, so it is not asked: a personal
  /// access token sent there can be read by anyone on the path.
  case insecureInstance
  /// GitLab answered, and the runner is paused there: no job is handed to it
  /// until somebody resumes it. Not "offline", which would announce a pause
  /// somebody made on purpose as a runner GitLab cannot see.
  case paused
}

/// Asks a GitLab instance about one of its runners.
///
/// The instance travels with every question rather than living in the
/// client, because it comes from each runner's own `config.toml` — which is
/// how a self-managed instance costs nothing extra: the URL was never
/// hardcoded to gitlab.com.
public struct GitLabAPIClient: Sendable {
  /// One Keychain account per instance, beside the GitHub one. A personal
  /// access token is issued by one instance, and any other it is shown to can
  /// keep it.
  public static func keychainAccount(for instance: GitLabInstance) -> String {
    "gitlab-token@" + instance.name
  }

  /// Where the token for one instance lives. Settings writes through the same
  /// function the client reads through, so the two cannot disagree.
  public static func tokenStore(for instance: GitLabInstance) -> KeychainTokenStore {
    KeychainTokenStore(account: keychainAccount(for: instance))
  }

  public static let userAgent = "Standfast"

  private let tokens: @Sendable (GitLabInstance) -> any GitHubTokenStoring
  private let http: any HTTPPerforming
  private let cache = StatusCache()

  /// The one the app runs on. Shared for the same reason the GitHub client's
  /// is: the conditional-request cache lives on the instance.
  public static let standard = GitLabAPIClient(
    tokens: { UnattendedTokenStore.gitLab(for: $0) }, http: URLSessionHTTPClient())

  public init(
    tokens: @escaping @Sendable (GitLabInstance) -> any GitHubTokenStoring,
    http: any HTTPPerforming
  ) {
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
      /// A failure only for `paused`, which GitLab answers with a tag like any
      /// other body: its 304 has to repeat it, not read as no answer.
      let answer: Result<RemoteStatus, GitLabError>
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
    /// Whether it was paused in GitLab. Read beside `status` because a release
    /// that reports contact on its own would call a paused runner online.
    let paused: Bool?
  }

  public func blockingRunnerStatus(
    id: Int, instance: GitLabInstance
  ) throws -> RemoteStatus {
    // Before the Keychain, so an instance that will not be asked raises no
    // dialog either. gitlab-runner may talk to it over http; its own token is
    // scoped to one runner, and the token stored here can act as the user.
    guard instance.isServedOverHTTPS else { throw GitLabError.insecureInstance }
    // A Keychain that would not answer is not an empty one: "add a GitLab
    // token" is the wrong advice when one is stored.
    let stored: String?
    do {
      stored = try tokens(instance).token()
    } catch {
      throw GitLabError.tokenUnreadable
    }
    guard let token = stored else { throw GitLabError.noToken }
    let url = instance.runnerURL(id: id)

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
      return try remembered.answer.get()
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

    // GitLab has several words for "not connected", and `paused` for a runner
    // set aside in its UI, either as the status or beside "online". Contact
    // decides first: a paused runner GitLab cannot see is still one it cannot
    // see. An unknown word is not guessed.
    let answer: Result<RemoteStatus, GitLabError>
    switch payload.status {
    case "online" where payload.paused == true, "paused":
      answer = .failure(.paused)
    case "online", "offline", "stale", "never_contacted":
      answer = .success(
        RemoteStatus(
          online: payload.status == "online",
          busy: payload.jobExecutionStatus == "active",
          labels: payload.tagList ?? []))
    default: throw GitLabError.noAnswer
    }

    if let etag = response.header("Etag") {
      cache.remember(url, StatusCache.Entry(etag: etag, answer: answer))
    }
    return try answer.get()
  }
}
