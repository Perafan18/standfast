import Foundation
import Testing

@testable import RunnerKit

private let scope = RunnerScope.repository(owner: "acme", name: "widget")
private let runnerURL = URL(
  string: "https://api.github.com/repos/acme/widget/actions/runners/21")!

private func idleRunner(busy: Bool = false, status: String = "online") -> String {
  #"{"id":21,"name":"mac-mini","os":"macos","status":"\#(status)","busy":\#(busy)}"#
}

private func client(
  _ http: FakeHTTPClient, token: String? = "ghp_secret"
) -> GitHubAPIClient {
  GitHubAPIClient(token: FakeTokenStore(token), http: http)
}

private func ask(
  _ http: FakeHTTPClient, token: String? = "ghp_secret"
) throws
  -> RemoteStatus
{
  try client(http, token: token).blockingRunnerStatus(id: 21, scope: scope)
}

// MARK: - Asking

@Test func asksTheRunnerEndpointForTheIdItWasGiven() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner(busy: true))]])

  #expect(try ask(http) == RemoteStatus(online: true, busy: true))
  #expect(http.requests.map(\.url) == [runnerURL])
}

@Test func sendsTheHeadersGitHubRequiresOfAnApiClient() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner())]])
  _ = try ask(http)

  let headers = http.requests[0].headers
  // Bearer, not `token`: the older scheme still works for classic PATs and
  // fails for fine-grained ones, which is what GitHub issues today.
  #expect(headers["Authorization"] == "Bearer ghp_secret")
  #expect(headers["Accept"] == "application/vnd.github+json")
  // Pinned, because GitHub changes behaviour by version and an unpinned client
  // is one that breaks on a date nobody chose.
  #expect(headers["X-GitHub-Api-Version"] == "2022-11-28")
  // Required by GitHub: requests without one are refused outright.
  #expect(headers["User-Agent"] == GitHubAPIClient.userAgent)
}

@Test func readsBothFieldsIndependently() throws {
  // Offline-and-busy is what a machine that died mid-job looks like, and
  // `RemoteStatus` deliberately allows it. A client that inferred one field
  // from the other would erase that state before anyone could see it.
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner(busy: true, status: "offline"))]])

  #expect(try ask(http) == RemoteStatus(online: false, busy: true))
}

// MARK: - When there is no answer

@Test func refusesToGuessAtAStatusWordItDoesNotKnow() throws {
  // The same rule the `gh` client follows, and for the same reason: calling an
  // unknown status online hides a runner that will never be sent work, and
  // calling it offline raises an alarm about a healthy one.
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner(status: "quiescing"))]])

  #expect(throws: GitHubError.noAnswer) { try ask(http) }
}

@Test func aRejectedTokenIsNotTheSameAsNoAnswer() throws {
  // 401 has a fix a person can act on — paste a new token — and "could not
  // tell" does not. A menu bar app that collapses them leaves the user with
  // nothing to try.
  let http = FakeHTTPClient([runnerURL: [.status(401)]])

  #expect(throws: GitHubError.notAuthenticated) { try ask(http) }
}

@Test func aRunnerGitHubDoesNotKnowIsNoAnswer() throws {
  let http = FakeHTTPClient([runnerURL: [.status(404)]])

  #expect(throws: GitHubError.noAnswer) { try ask(http) }
}

@Test func noNetworkIsNoAnswer() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner())]])
  http.offline = true

  #expect(throws: GitHubError.noAnswer) { try ask(http) }
}

@Test func withNoTokenStoredItSaysSoRatherThanAsking() throws {
  // Distinct from a rejected token: nothing has been tried, and the fix is to
  // add one. It is also what lets the composing client fall back to `gh`
  // instead of reporting a failure the user cannot act on.
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner())]])

  #expect(throws: GitHubError.noToken) { try ask(http, token: nil) }
  #expect(http.requests.isEmpty)
}

// MARK: - Not spending the rate limit on questions already answered

@Test func theFirstQuestionAboutARunnerIsUnconditional() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(idleRunner(), etag: #""abc""#)]])
  _ = try ask(http)

  #expect(http.requests[0].headers["If-None-Match"] == nil)
}

@Test func theSecondQuestionCarriesTheTagTheFirstAnswerCameWith() throws {
  // This is the whole reason the app can ask every fifteen seconds. GitHub
  // does not charge a conditional request that it answers 304 against the
  // rate limit, and at one call per runner per fifteen seconds an app with a
  // handful of runners would otherwise spend a personal token's hourly budget
  // on questions whose answer never changed.
  let http = FakeHTTPClient([
    runnerURL: [.ok(idleRunner(), etag: #""abc""#), .status(304)]
  ])
  let subject = client(http)

  _ = try subject.blockingRunnerStatus(id: 21, scope: scope)
  _ = try subject.blockingRunnerStatus(id: 21, scope: scope)

  #expect(http.requests[1].headers["If-None-Match"] == #""abc""#)
}

@Test func copiesOfOneClientShareTheTagsTheyLearn() throws {
  // The client is a struct and is copied at its call sites. A cache that lived
  // on the value would reset with every copy, so every request would be
  // unconditional and the rate limit would come back — silently, because
  // unconditional requests are still correct.
  let http = FakeHTTPClient([
    runnerURL: [.ok(idleRunner(), etag: #""abc""#), .status(304)]
  ])
  let subject = client(http)
  let copy = subject

  _ = try subject.blockingRunnerStatus(id: 21, scope: scope)
  #expect(
    try copy.blockingRunnerStatus(id: 21, scope: scope)
      == RemoteStatus(online: true, busy: false))
  #expect(http.requests[1].headers["If-None-Match"] == #""abc""#)
}

@Test func anUnchangedAnswerIsTheAnswerItAlreadyHad() throws {
  let http = FakeHTTPClient([
    runnerURL: [.ok(idleRunner(busy: true), etag: #""abc""#), .status(304)]
  ])
  let subject = client(http)

  #expect(
    try subject.blockingRunnerStatus(id: 21, scope: scope)
      == RemoteStatus(online: true, busy: true))
  // 304 carries no body. Re-parsing would produce nothing; guessing would
  // produce a lie. The only correct answer is the one this client already had.
  #expect(
    try subject.blockingRunnerStatus(id: 21, scope: scope)
      == RemoteStatus(online: true, busy: true))
}

@Test func aTagIsReadWhateverCaseTheServerSpelledItIn() throws {
  // HTTP header names are case-insensitive and every layer spells this one
  // differently: `Etag`, `ETag`, `etag`. A lookup that matched only one would
  // silently never cache, and the failure would be a rate limit weeks later
  // rather than a red test now.
  let http = FakeHTTPClient([
    runnerURL: [
      HTTPResponse(
        statusCode: 200, body: Data(idleRunner().utf8), headers: ["ETag": #""z""#]),
      .status(304),
    ]
  ])
  let subject = client(http)

  _ = try subject.blockingRunnerStatus(id: 21, scope: scope)
  _ = try subject.blockingRunnerStatus(id: 21, scope: scope)
  #expect(http.requests[1].headers["If-None-Match"] == #""z""#)
}

@Test func aRunnerNeverSuccessfullyReadCannotBeAnsweredFromCache() throws {
  // A 304 for something this client never held is GitHub answering a question
  // it was not asked. There is nothing to return but "could not tell".
  let http = FakeHTTPClient([runnerURL: [.status(304)]])

  #expect(throws: GitHubError.noAnswer) { try ask(http) }
}

// MARK: - Running out of budget

@Test func anExhaustedRateLimitIsNotTheSameAsSilence() throws {
  // The fix is to wait, or to ask about fewer runners. "Could not tell" gives
  // the user neither, and this app has been burned before by a state it knew
  // and did not say.
  let http = FakeHTTPClient([
    runnerURL: [.status(403, headers: ["x-ratelimit-remaining": "0"])]
  ])

  #expect(throws: GitHubError.rateLimited) { try ask(http) }
}

@Test func aForbiddenAnswerWithBudgetLeftIsNoAnswer() throws {
  // 403 with requests remaining is a token whose scopes do not cover this
  // endpoint — a different problem, and not one waiting will fix.
  let http = FakeHTTPClient([
    runnerURL: [.status(403, headers: ["x-ratelimit-remaining": "4999"])]
  ])

  #expect(throws: GitHubError.noAnswer) { try ask(http) }
}

@Test func tooManyRequestsIsAlsoRateLimiting() throws {
  // GitHub answers secondary rate limits with 429 and no rate-limit header.
  let http = FakeHTTPClient([runnerURL: [.status(429)]])

  #expect(throws: GitHubError.rateLimited) { try ask(http) }
}

// MARK: - The published runner release

private let releaseURL = URL(
  string: "https://api.github.com/repos/actions/runner/releases/latest")!

@Test func readsThePublishedRunnerVersionFromItsTag() throws {
  let http = FakeHTTPClient([releaseURL: [.ok(#"{"tag_name":"v2.330.0"}"#)]])

  #expect(try client(http).blockingLatestRunnerRelease() == RunnerVersion(2, 330, 0))
}

@Test func aReleaseBodyWithoutAVersionInItIsNoAnswer() throws {
  // GitHub answers an API error with a JSON body and a non-200. Relying on the
  // body failing to parse would be relying on GitHub never naming a release
  // after one of its own error messages.
  let http = FakeHTTPClient([releaseURL: [.status(404)]])

  #expect(throws: GitHubError.noAnswer) { try client(http).blockingLatestRunnerRelease() }
}

@Test func theReleaseQuestionIsNeverAnsweredFromTheRunnerCache() throws {
  // Different question, different URL, and the release check runs at a
  // completely different rate. Sharing a cache between them would let a runner
  // status answer a version question, or the reverse.
  let http = FakeHTTPClient([
    runnerURL: [.ok(idleRunner(), etag: #""abc""#)],
    releaseURL: [.ok(#"{"tag_name":"v2.330.0"}"#)],
  ])
  let subject = client(http)

  _ = try subject.blockingRunnerStatus(id: 21, scope: scope)
  _ = try subject.blockingLatestRunnerRelease()

  #expect(http.requests[1].url == releaseURL)
  #expect(http.requests[1].headers["If-None-Match"] == nil)
}

@Test func theReleaseQuestionAlsoKnowsItRanOutOfBudget() throws {
  // Both questions go through the same token and the same budget, so both have
  // to be able to say so. Only one of them being able to was an accident of
  // which one was written first.
  let http = FakeHTTPClient([
    releaseURL: [.status(403, headers: ["x-ratelimit-remaining": "0"])]
  ])

  #expect(throws: GitHubError.rateLimited) {
    try client(http).blockingLatestRunnerRelease()
  }
}
