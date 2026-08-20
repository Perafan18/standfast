import Foundation
import Testing

@testable import RunnerKit

private let runnerURL = URL(string: "https://gitlab.example.com/api/v4/runners/91")!

private func answer(
  status: String = "online", jobStatus: String = "idle", tags: [String] = ["macos"]
) -> String {
  let tagList = tags.map { "\"\($0)\"" }.joined(separator: ",")
  return #"{"id":91,"description":"mac","status":"\#(status)","#
    + #""paused":false,"tag_list":[\#(tagList)],"#
    + #""job_execution_status":"\#(jobStatus)"}"#
}

private func ask(
  _ http: FakeHTTPClient, token: String? = "glpat-x"
) throws -> RemoteStatus {
  try GitLabAPIClient(token: FakeTokenStore(token), http: http)
    .blockingRunnerStatus(id: 91, instanceHost: "gitlab.example.com")
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

@Test func anUnchangedAnswerIsNotReParsedWhenGitLabHonoursTheTag() throws {
  // GitLab sends ETags on GET endpoints and honours If-None-Match. Unlike
  // GitHub, its docs make no promise about 304s and the rate limit, so the
  // comments claim bandwidth only — but the cache is the same machinery.
  let http = FakeHTTPClient([
    runnerURL: [.ok(answer(jobStatus: "active"), etag: #""r1""#), .status(304)]
  ])
  let client = GitLabAPIClient(token: FakeTokenStore("glpat-x"), http: http)

  let first = try client.blockingRunnerStatus(id: 91, instanceHost: "gitlab.example.com")
  let second = try client.blockingRunnerStatus(id: 91, instanceHost: "gitlab.example.com")

  #expect(first == second)
  #expect(http.requests[1].headers["If-None-Match"] == #""r1""#)
}
