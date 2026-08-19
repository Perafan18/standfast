import Foundation
import Testing

@testable import RunnerKit

/// The real GitHub, behind a flag.
///
/// Everything else in this suite proves the client behaves correctly against
/// answers a test wrote. Nothing there can catch the client being *wrong about
/// GitHub*: a header GitHub now requires, a field renamed, an Etag that never
/// arrives, a 304 that never comes back. Those only fail against the real
/// thing, and they fail silently — as a rate limit weeks later, or a menu that
/// says "could not tell" forever.
///
/// Not in CI: it needs a credential, it spends rate limit, and it fails when
/// GitHub is down, which is not a fact about this code. Run it by hand:
///
/// ```sh
/// STANDFAST_GITHUB_TOKEN="$(gh auth token)" swift test --filter LiveGitHub
/// ```
///
/// The token is read from the environment and never from the Keychain, so
/// running this cannot touch what the app itself stores.
private let liveToken = ProcessInfo.processInfo.environment["STANDFAST_GITHUB_TOKEN"]

/// The public endpoint, deliberately. It needs no scope beyond being a valid
/// token, so this runs with whatever credential the person has — and it is the
/// one question whose answer this app already knows how to parse.
@Test(.enabled(if: liveToken != nil))
func theRealGitHubAnswersTheQuestionThisClientAsks() throws {
  let client = GitHubAPIClient(
    token: FakeTokenStore(liveToken), http: URLSessionHTTPClient())

  let version = try client.blockingLatestRunnerRelease()

  // Whatever the newest runner is, it is at least the 2.x line that has been
  // shipping for years. A zero here means the tag parsed into nothing.
  #expect(version.major >= 2)
}

@Test(.enabled(if: liveToken != nil))
func theRealGitHubSendsATagAndHonoursItComingBack() throws {
  // The assumption the entire rate-limit strategy rests on, checked against
  // the only thing that can confirm it. If GitHub stopped sending an Etag, or
  // stopped answering 304 to a matching If-None-Match, the app would keep
  // working and quietly spend its hourly budget until it ran out.
  let http = URLSessionHTTPClient()
  let url = GitHubAPIClient.defaultBaseURL
    .appendingPathComponent(GitHubAPIClient.latestReleasePath)
  let headers = [
    "Authorization": "Bearer \(liveToken!)",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": GitHubAPIClient.apiVersion,
    "User-Agent": GitHubAPIClient.userAgent,
  ]

  let first = try http.blockingGet(url, headers: headers)
  #expect(first.statusCode == 200)
  let tag = try #require(first.header("Etag"))

  var conditional = headers
  conditional["If-None-Match"] = tag
  let second = try http.blockingGet(url, headers: conditional)

  #expect(second.statusCode == 304)
  // And the part that makes it worth doing: GitHub does not charge a 304
  // against the budget. If this ever stops being true the strategy is only
  // saving bandwidth, not requests, and the polling interval has to change.
  let remaining = try #require(second.header("x-ratelimit-remaining"))
  let spent = try #require(first.header("x-ratelimit-remaining"))
  #expect(remaining == spent)
}
