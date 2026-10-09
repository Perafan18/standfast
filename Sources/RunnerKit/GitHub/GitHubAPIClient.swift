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
  private let queues = QueueCache()

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

  /// The last queue this client read, and the tag the *listing* came with.
  ///
  /// Keyed on the listing alone, not on the per-run job reads, because the
  /// listing is what changes: a run leaves `status=queued` the moment any of
  /// its jobs is handed out, so a byte-identical listing is strong evidence
  /// that no job under it has moved either. The failure this trades against is
  /// brief and self-correcting — the next change to any run rewrites the tag.
  private final class QueueCache: @unchecked Sendable {
    struct Entry {
      let etag: String
      let work: QueuedWork
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
    let stored: String?
    do {
      stored = try tokens.token()
    } catch {
      // Not "no token": something is stored, and the fallback to `gh` that
      // `noToken` triggers would quietly ignore it.
      throw GitHubError.tokenUnreadable
    }
    guard let token = stored else { throw GitHubError.noToken }
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
    struct Label: Decodable { let name: String }

    let status: String
    let busy: Bool
    /// Optional, so a payload without them still yields a status. Labels feed a
    /// feature; status is the fact the menu leads with, and losing the second
    /// because the first is absent would be a bad trade.
    let labels: [Label]?
  }

  /// Both questions go through the same token and the same hourly budget, so
  /// both have to be able to name the same failures. Only one of them being
  /// able to was an accident of which was written first.
  private func rejecting(_ response: HTTPResponse) throws {
    // A rejected token has a fix a person can act on. "Could not tell" does
    // not, and collapsing the two leaves the user with nothing to try.
    guard response.statusCode != Self.unauthorized else {
      throw GitHubError.tokenRefused
    }
    // Running out of budget is not silence; the fix is time. A primary limit is
    // 403 at zero remaining, a secondary one 429, or 403 with `retry-after` or
    // a message naming it. Any other 403 is a token lacking scope, which
    // waiting never repairs.
    if response.statusCode == Self.tooManyRequests
      || (response.statusCode == Self.forbidden
        && (response.header("x-ratelimit-remaining") == "0"
          || response.header("retry-after") != nil
          || Self.namesSecondaryLimit(response.body)))
    {
      throw GitHubError.rateLimited
    }
  }

  private struct ErrorPayload: Decodable {
    let message: String
  }

  /// GitHub sends `retry-after` with a secondary limit only "if present", and
  /// otherwise says so in the message alone, which is what Octokit reads too.
  private static func namesSecondaryLimit(_ body: Data) -> Bool {
    guard let payload = try? JSONDecoder().decode(ErrorPayload.self, from: body) else {
      return false
    }
    return payload.message.range(of: "secondary rate limit", options: .caseInsensitive)
      != nil
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
    let labels = (payload.labels ?? []).map(\.name)
    switch payload.status {
    case "online": return RemoteStatus(online: true, busy: payload.busy, labels: labels)
    case "offline": return RemoteStatus(online: false, busy: payload.busy, labels: labels)
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

extension GitHubAPIClient: QueuedWorkReading {
  /// How many queued runs one reading will look at.
  ///
  /// Each one costs a second request to read its jobs, so this number is what
  /// the feature costs: ten runs is eleven requests. When GitHub has more, the
  /// answer says so rather than presenting a capped count as a total.
  public static let queuedRunsInspected = 10
  static let jobsPerRun = 50

  private struct RunsPayload: Decodable {
    struct Run: Decodable { let id: Int }

    let totalCount: Int
    let workflowRuns: [Run]
  }

  private struct JobsPayload: Decodable {
    struct Job: Decodable {
      let id: Int
      let name: String
      let status: String
      let workflowName: String?
      let labels: [String]?
      let createdAt: Date?
      let htmlUrl: URL?
    }

    let jobs: [Job]
    /// Every job in the run, not only this page. Optional so a payload without
    /// it still reads; nil is taken as "the page is all of it".
    let totalCount: Int?
  }

  public func blockingQueuedWork(in scope: RunnerScope) throws -> QueuedWork {
    guard let runsPath = scope.queuedRunsAPIPath else {
      throw GitHubError.notAvailableForScope
    }

    let listingURL = url(
      runsPath,
      query: [
        // Runs GitHub accepted and has not started. A run already in
        // progress can still hold queued jobs — a matrix that handed some
        // out and is holding the rest — and those are not counted. That is
        // the bound this filter buys, and it is the difference between
        // eleven requests a reading and one per run in the repository.
        ("status", "queued"), ("per_page", "\(Self.queuedRunsInspected)"),
      ])
    let remembered = queues.entry(for: listingURL)
    let response = try get(listingURL, ifNoneMatch: remembered?.etag)
    if response.statusCode == Self.notModified {
      guard let remembered else { throw GitHubError.noAnswer }
      return remembered.work
    }
    let listing: RunsPayload = try decoded(from: response)

    var waiting: [QueuedJob] = []
    var pageCutOffJobs = false
    for run in listing.workflowRuns {
      let payload: JobsPayload = try decoded(
        from: get(
          url("\(runsPath)/\(run.id)/jobs", query: [("per_page", "\(Self.jobsPerRun)")]),
          ifNoneMatch: nil))
      waiting += payload.jobs.filter { $0.status == "queued" }.map(Self.queued)
      pageCutOffJobs =
        pageCutOffJobs || (payload.totalCount ?? payload.jobs.count) > payload.jobs.count
    }

    let work = QueuedWork(
      jobs: waiting,
      isPartial: listing.totalCount > listing.workflowRuns.count || pageCutOffJobs)
    if let etag = response.header("Etag") {
      queues.remember(listingURL, QueueCache.Entry(etag: etag, work: work))
    }
    return work
  }

  private static func queued(_ job: JobsPayload.Job) -> QueuedJob {
    QueuedJob(
      id: job.id, name: job.name, workflowName: job.workflowName ?? "",
      labels: job.labels ?? [], queuedAt: job.createdAt, url: job.htmlUrl)
  }

  private func url(_ path: String, query: [(String, String)]) -> URL {
    var components = URLComponents(
      url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    components.queryItems = query.map(URLQueryItem.init)
    return components.url!
  }

  /// Reads a body, or refuses. Every failure GitHub can name — a rejected
  /// token, an exhausted budget — is named before the body is looked at.
  ///
  /// Deliberately never "zero jobs waiting": a run whose jobs could not be read
  /// makes every count below it an undercount, and "nothing is waiting" over a
  /// queue nobody could read is this app sounding most confident where it knows
  /// least.
  private func decoded<Payload: Decodable>(
    from response: HTTPResponse
  ) throws
    -> Payload
  {
    try rejecting(response)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    guard response.statusCode == 200,
      let payload = try? decoder.decode(Payload.self, from: response.body)
    else { throw GitHubError.noAnswer }
    return payload
  }
}
