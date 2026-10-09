import Foundation
import Testing

@testable import RunnerKit

private let runnerURL = URL(string: "https://gitlab.example.com/api/v4/runners/91")!
private let instance = GitLabInstance(url: "https://gitlab.example.com/")!

private func answer(
  status: String = "online", jobStatus: String = "idle", tags: [String] = ["macos"],
  paused: Bool = false
) -> String {
  let tagList = tags.map { "\"\($0)\"" }.joined(separator: ",")
  return #"{"id":91,"description":"mac","status":"\#(status)","#
    + #""paused":\#(paused),"tag_list":[\#(tagList)],"#
    + #""job_execution_status":"\#(jobStatus)"}"#
}

private func ask(
  _ http: FakeHTTPClient, token: String? = "glpat-x"
) throws -> RemoteStatus {
  try GitLabAPIClient(tokens: { _ in FakeTokenStore(token) }, http: http)
    .blockingRunnerStatus(id: 91, instance: instance)
}

@Test func asksTheInstanceTheRunnerReportsTo() throws {
  // The host comes from the runner's own config.toml, so a self-managed
  // instance costs nothing extra — the URL was never hardcoded.
  let http = FakeHTTPClient([runnerURL: [.ok(answer())]])

  #expect(try ask(http) == RemoteStatus(online: true, busy: false, labels: ["macos"]))
  #expect(http.requests.map(\.url) == [runnerURL])
}

@Test func authenticatesTheWayGitLabExpects() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(answer())]])
  _ = try ask(http)

  // PRIVATE-TOKEN is the header GitLab documents for personal access tokens.
  // Bearer also works for OAuth tokens, but a PAT is what the Settings field
  // asks for, so the documented header for exactly that is the one sent.
  #expect(http.requests[0].headers["PRIVATE-TOKEN"] == "glpat-x")
  #expect(http.requests[0].headers["Authorization"] == nil)
}

@Test func aRunnerDoingAJobIsBusy() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(answer(jobStatus: "active"))]])

  #expect(try ask(http).busy)
}

@Test func staleAndNeverContactedAreBothOffline() throws {
  // GitLab has two words for "not connected for a while" and this app has one
  // question: will this machine be handed work? Neither answers yes.
  for status in ["offline", "stale", "never_contacted"] {
    let http = FakeHTTPClient([runnerURL: [.ok(answer(status: status))]])
    #expect(try ask(http).online == false, "\(status) should read as offline")
  }
}

@Test func aPausedRunnerIsAnsweredAsPaused() throws {
  // Paused in GitLab's UI for maintenance, a runner is handed no jobs. GitLab
  // said so plainly: "not answering" would send somebody to check the network
  // and the token, and "offline" would announce a deliberate pause as a runner
  // GitLab cannot see.
  let http = FakeHTTPClient([runnerURL: [.ok(answer(status: "paused"))]])

  #expect(throws: GitLabError.paused) { _ = try ask(http) }
}

@Test func thePausedFlagOutranksAnOnlineStatus() throws {
  // A release that reports contact apart from pausing says `online` for a
  // paused runner, and the flag is still the one that decides about work.
  let http = FakeHTTPClient([runnerURL: [.ok(answer(status: "online", paused: true))]])

  #expect(throws: GitLabError.paused) { _ = try ask(http) }
}

@Test func aPausedRunnerThatLostContactIsStillOffline() throws {
  // Connection before the pause: GitLab cannot see it, which stays true and
  // stays the fault once somebody resumes it.
  for status in ["offline", "stale", "never_contacted"] {
    let http = FakeHTTPClient([runnerURL: [.ok(answer(status: status, paused: true))]])
    #expect(try ask(http).online == false, "\(status)")
  }
}

@Test func aPausedAnswerGitLabRepeatsWithA304IsStillPaused() throws {
  // The tag GitLab sent with "paused" comes back as a 304 for as long as the
  // runner stays paused. Answered from nothing, that 304 reads as GitLab not
  // answering at all.
  let http = FakeHTTPClient([
    runnerURL: [.ok(answer(status: "online", paused: true), etag: #""p1""#), .status(304)]
  ])
  let client = GitLabAPIClient(tokens: { _ in FakeTokenStore("glpat-x") }, http: http)

  #expect(throws: GitLabError.paused) {
    _ = try client.blockingRunnerStatus(id: 91, instance: instance)
  }
  #expect(throws: GitLabError.paused) {
    _ = try client.blockingRunnerStatus(id: 91, instance: instance)
  }
  #expect(http.requests[1].headers["If-None-Match"] == #""p1""#)
}

@Test func aStatusWordThisVersionHasNotMetIsNotGuessedAt() throws {
  let http = FakeHTTPClient([runnerURL: [.ok(answer(status: "quiescing"))]])

  #expect(throws: GitLabError.noAnswer) { _ = try ask(http) }
}

@Test func gitLabFailuresAreNamedInGitLabsOwnTerms() throws {
  // Not GitHubError, on purpose: these reach the menu as instructions, and
  // "run gh auth login" is the wrong advice for a GitLab token.
  #expect(throws: GitLabError.noToken) {
    _ = try ask(FakeHTTPClient([runnerURL: [.ok(answer())]]), token: nil)
  }
  #expect(throws: GitLabError.notAuthenticated) {
    _ = try ask(FakeHTTPClient([runnerURL: [.status(401)]]))
  }
  #expect(throws: GitLabError.rateLimited) {
    _ = try ask(FakeHTTPClient([runnerURL: [.status(429)]]))
  }
  #expect(throws: GitLabError.noAnswer) {
    _ = try ask(FakeHTTPClient([runnerURL: [.status(404)]]))
  }
}

@Test func aKeychainThatWouldNotAnswerIsNotAMissingToken() throws {
  // "Add a GitLab token in Settings" to someone who already did is wrong
  // advice; the Keychain is what refused.
  let store = FakeTokenStore("glpat-x")
  store.failsToRead = true
  let http = FakeHTTPClient([runnerURL: [.ok(answer())]])

  #expect(throws: GitLabError.tokenUnreadable) {
    _ = try GitLabAPIClient(tokens: { _ in store }, http: http)
      .blockingRunnerStatus(id: 91, instance: instance)
  }
  #expect(http.requests.isEmpty)
}

@Test func anUnchangedAnswerIsNotReParsedWhenGitLabHonoursTheTag() throws {
  // GitLab sends ETags on GET endpoints and honours If-None-Match. Unlike
  // GitHub, its docs make no promise about 304s and the rate limit, so the
  // comments claim bandwidth only — but the cache is the same machinery.
  let http = FakeHTTPClient([
    runnerURL: [.ok(answer(jobStatus: "active"), etag: #""r1""#), .status(304)]
  ])
  let client = GitLabAPIClient(tokens: { _ in FakeTokenStore("glpat-x") }, http: http)

  let first = try client.blockingRunnerStatus(id: 91, instance: instance)
  let second = try client.blockingRunnerStatus(id: 91, instance: instance)

  #expect(first == second)
  #expect(http.requests[1].headers["If-None-Match"] == #""r1""#)
}

@Test func aTokenOnlyEverGoesToTheInstanceItWasStoredFor() throws {
  // config.toml can name gitlab.com and a client's own server side by side. A
  // token issued by one is a working credential the other could keep.
  let elsewhere = try #require(GitLabInstance(url: "https://gitlab.com"))
  let http = FakeHTTPClient([runnerURL: [.ok(answer())]])
  let client = GitLabAPIClient(
    tokens: { $0 == elsewhere ? FakeTokenStore("glpat-com") : FakeTokenStore(nil) },
    http: http)

  #expect(throws: GitLabError.noToken) {
    _ = try client.blockingRunnerStatus(id: 91, instance: instance)
  }
  #expect(http.requests.isEmpty)
}

@Test func eachInstanceKeepsItsTokenUnderItsOwnKeychainAccount() throws {
  // Literal, not built from the function: an account name that changes
  // strands every token already stored under the old one.
  let corp = try #require(GitLabInstance(url: "https://gitlab.corp.example:8443/"))

  #expect(
    GitLabAPIClient.keychainAccount(for: instance) == "gitlab-token@gitlab.example.com")
  #expect(
    GitLabAPIClient.keychainAccount(for: corp) == "gitlab-token@gitlab.corp.example:8443")
}

@Test func eachInstanceIsAskedAtItsOwnSchemePortAndPath() throws {
  // Literal URLs: an instance served from :8443 under /gitlab, or over http,
  // is a different server once any one of those is rebuilt from text.
  let corp = try #require(GitLabInstance(url: "https://gitlab.corp.example:8443/gitlab/"))
  let url = try #require(
    URL(string: "https://gitlab.corp.example:8443/gitlab/api/v4/runners/91"))
  let http = FakeHTTPClient([url: [.ok(answer())]])
  let client = GitLabAPIClient(tokens: { _ in FakeTokenStore("glpat-x") }, http: http)

  #expect(try client.blockingRunnerStatus(id: 91, instance: corp).online)
  #expect(http.requests.map(\.url) == [url])

  // An http instance keeps its own address too, even though it is not asked:
  // its identity, its card and its link must not collapse onto https.
  let plain = try #require(GitLabInstance(url: "http://10.0.0.5:8080"))
  #expect(plain.runnerURL(id: 91) == URL(string: "http://10.0.0.5:8080/api/v4/runners/91"))
  #expect(!plain.isServedOverHTTPS)
}

@Test func aTokenIsNeverSentToAnInstanceServedOverPlainHTTP() throws {
  // config.toml may name an http:// instance, and gitlab-runner itself will
  // talk to it. A personal access token is not the runner's token, though: it
  // can act as the user across the whole instance, and over http anyone on the
  // path reads it. Standfast does not ask such an instance at all.
  let plain = try #require(GitLabInstance(url: "http://gitlab.lan:8080"))
  // A store that refuses to be read, so any other answer means the Keychain
  // was asked first: a dialog for an instance that will never get the token.
  let store = FakeTokenStore("glpat-x")
  store.failsToRead = true
  let http = FakeHTTPClient([plain.runnerURL(id: 91): [.ok(answer())]])

  #expect(throws: GitLabError.insecureInstance) {
    _ = try GitLabAPIClient(tokens: { _ in store }, http: http)
      .blockingRunnerStatus(id: 91, instance: plain)
  }
  #expect(http.requests.isEmpty)

  // And with a token the Keychain would hand over: still nothing on the wire.
  let readable = FakeTokenStore("glpat-x")
  #expect(throws: GitLabError.insecureInstance) {
    _ = try GitLabAPIClient(tokens: { _ in readable }, http: http)
      .blockingRunnerStatus(id: 91, instance: plain)
  }
  #expect(http.requests.isEmpty)
}
