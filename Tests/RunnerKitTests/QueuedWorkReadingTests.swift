import Foundation
import Testing

@testable import RunnerKit

private let repository = RunnerScope.repository(owner: "acme", name: "widget")
private let runsURL = URL(
  string: "https://api.github.com/repos/acme/widget/actions/runs?status=queued&per_page=10")!

private func jobsURL(_ run: Int) -> URL {
  URL(
    string: "https://api.github.com/repos/acme/widget/actions/runs/\(run)/jobs?per_page=50")!
}

private func runs(_ ids: [Int], total: Int? = nil) -> String {
  let list = ids.map { #"{"id":\#($0)}"# }.joined(separator: ",")
  return #"{"total_count":\#(total ?? ids.count),"workflow_runs":[\#(list)]}"#
}

private func jobs(_ entries: String...) -> String {
  #"{"jobs":[\#(entries.joined(separator: ","))]}"#
}

private func queuedJob(
  _ id: Int, name: String = "build", labels: [String] = ["self-hosted"],
  status: String = "queued"
) -> String {
  let labelList = labels.map { "\"\($0)\"" }.joined(separator: ",")
  return #"{"id":\#(id),"name":"\#(name)","status":"\#(status)","#
    + #""workflow_name":"CI","labels":[\#(labelList)],"#
    + #""created_at":"2026-08-19T10:00:00Z","html_url":"https://x/\#(id)"}"#
}

private func read(
  _ http: FakeHTTPClient, scope: RunnerScope = repository
) throws
  -> QueuedWork
{
  try GitHubAPIClient(token: FakeTokenStore("ghp_x"), http: http)
    .blockingQueuedWork(in: scope)
}

// MARK: - Finding the work

@Test func asksOnlyForRunsGitHubHasNotStartedYet() throws {
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([]))]
  ])

  #expect(try read(http).jobs.isEmpty)
  #expect(http.requests.map(\.url) == [runsURL])
}

@Test func readsTheJobsOfEveryQueuedRun() throws {
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7, 9]))],
    jobsURL(7): [.ok(jobs(queuedJob(70, name: "build")))],
    jobsURL(9): [.ok(jobs(queuedJob(90, name: "test")))],
  ])

  #expect(try read(http).jobs.map(\.name) == ["build", "test"])
}

@Test func keepsOnlyTheJobsThatAreActuallyWaiting() throws {
  // A queued run can already have jobs running: a matrix hands some out and
  // holds the rest. Counting those as waiting would tell the operator work is
  // stuck when it is being done.
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7]))],
    jobsURL(7): [
      .ok(
        jobs(
          queuedJob(70, name: "waiting"),
          queuedJob(71, name: "running", status: "in_progress"),
          queuedJob(72, name: "done", status: "completed")))
    ],
  ])

  #expect(try read(http).jobs.map(\.name) == ["waiting"])
}

@Test func carriesWhatEachJobAskedFor() throws {
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7]))],
    jobsURL(7): [.ok(jobs(queuedJob(70, labels: ["self-hosted", "macOS"])))],
  ])

  let job = try #require(try read(http).jobs.first)
  #expect(job.labels == ["self-hosted", "macOS"])
  #expect(job.workflowName == "CI")
  #expect(job.url == URL(string: "https://x/70"))
  #expect(job.queuedAt == Date(timeIntervalSince1970: 1_787_133_600))
}

// MARK: - Being honest about the bound

@Test func saysWhenItLookedAtFewerRunsThanGitHubHad() throws {
  // A cap that reports a count as if it were the whole answer is a silent
  // truncation, and this app's own contributing rules forbid one. Better to
  // say "at least 3" than to say "3" and be wrong.
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7], total: 40))],
    jobsURL(7): [.ok(jobs(queuedJob(70)))],
  ])

  #expect(try read(http).isPartial)
}

@Test func aCompleteAnswerDoesNotClaimToBePartial() throws {
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7]))],
    jobsURL(7): [.ok(jobs(queuedJob(70)))],
  ])

  #expect(!(try read(http).isPartial))
}

@Test func aRunWhoseJobsCannotBeReadIsNotSilentlyCountedAsZero() throws {
  // Undercounting is the failure that matters here: "nothing is waiting" over
  // a queue nobody could read is the app sounding confident where it knows
  // least.
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7]))],
    jobsURL(7): [.status(500)],
  ])

  #expect(throws: GitHubError.noAnswer) { try read(http) }
}

// MARK: - Where GitHub has no answer to give

@Test func anOrganisationRunnerCannotBeAskedThisAtAll() throws {
  // There is no org-wide or enterprise-wide endpoint for queued work: the
  // question only exists per repository. Returning an empty list would say
  // "nothing is waiting", which is a claim this app cannot support.
  let http = FakeHTTPClient()

  #expect(throws: GitHubError.notAvailableForScope) {
    try read(http, scope: .organization("acme"))
  }
  #expect(throws: GitHubError.notAvailableForScope) {
    try read(http, scope: .enterprise("acme"))
  }
  #expect(http.requests.isEmpty)
}

// MARK: - Not paying for the queue twice

@Test func anUnchangedQueueCostsOneRequestInsteadOfOnePerRun() throws {
  // The listing is asked once per non-busy runner per refresh. Reading it
  // costs one request plus one per queued run, so the case that has to be
  // cheap is the common one: nothing changed since fifteen seconds ago.
  let http = FakeHTTPClient([
    runsURL: [.ok(runs([7, 9]), etag: #""q1""#), .status(304)],
    jobsURL(7): [.ok(jobs(queuedJob(70, name: "build")))],
    jobsURL(9): [.ok(jobs(queuedJob(90, name: "test")))],
  ])
  let client = GitHubAPIClient(token: FakeTokenStore("ghp_x"), http: http)

  let first = try client.blockingQueuedWork(in: repository)
  let second = try client.blockingQueuedWork(in: repository)

  #expect(first == second)
  #expect(second.jobs.map(\.name) == ["build", "test"])
  // Three requests for the first reading, one for the second — and the second
  // one is a 304, which GitHub does not charge for at all.
  #expect(http.requests.count == 4)
  #expect(http.requests[3].headers["If-None-Match"] == #""q1""#)
}

@Test func aQueueNeverSuccessfullyReadCannotBeAnsweredFromCache() throws {
  let http = FakeHTTPClient([runsURL: [.status(304)]])

  #expect(throws: GitHubError.noAnswer) { try read(http) }
}
