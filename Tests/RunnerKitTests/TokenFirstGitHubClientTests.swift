import Foundation
import Testing

@testable import RunnerKit

private let scope = RunnerScope.repository(owner: "acme", name: "widget")

/// Records whether it was asked, and answers however the test says.
private final class SpyClient: GitHubClient, RunnerReleaseChecking, @unchecked Sendable {
  private let lock = NSLock()
  private var asked = 0
  private let answer: Result<RemoteStatus, GitHubError>
  private let release: Result<RunnerVersion, GitHubError>

  init(
    _ answer: Result<RemoteStatus, GitHubError>,
    release: Result<RunnerVersion, GitHubError> = .success(RunnerVersion(2, 0, 0))
  ) {
    self.answer = answer
    self.release = release
  }

  var timesAsked: Int {
    lock.lock()
    defer { lock.unlock() }
    return asked
  }

  func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    lock.lock()
    asked += 1
    lock.unlock()
    return try answer.get()
  }

  func blockingLatestRunnerRelease() throws -> RunnerVersion {
    lock.lock()
    asked += 1
    lock.unlock()
    return try release.get()
  }
}

private func ask(_ subject: TokenFirstGitHubClient) throws -> RemoteStatus {
  try subject.blockingRunnerStatus(id: 21, scope: scope)
}

private let working = RemoteStatus(online: true, busy: false)
private let stale = RemoteStatus(online: false, busy: false)

@Test func aStoredTokenIsUsedAndTheCliIsNeverSpawned() throws {
  let token = SpyClient(.success(working))
  let cli = SpyClient(.success(stale))

  #expect(try ask(TokenFirstGitHubClient(token: token, cli: cli)) == working)
  // The point of the whole feature: a user with a token does not need `gh`
  // installed, authenticated, or present at all.
  #expect(cli.timesAsked == 0)
}

@Test func withNoTokenStoredItFallsBackToTheCli() throws {
  // Every existing user is in this state, and the day this ships must not be
  // the day their menu goes blank.
  let token = SpyClient(.failure(.noToken))
  let cli = SpyClient(.success(working))

  #expect(try ask(TokenFirstGitHubClient(token: token, cli: cli)) == working)
}

@Test func aTokenThatGitHubRefusedIsReportedRatherThanPaperedOver() throws {
  let token = SpyClient(.failure(.notAuthenticated))
  let cli = SpyClient(.success(working))

  // Falling back here would keep the menu working and hide the fact that a
  // credential the user deliberately configured is wrong. They would never
  // learn, and the app would quietly depend on `gh` again.
  #expect(throws: GitHubError.notAuthenticated) {
    try ask(TokenFirstGitHubClient(token: token, cli: cli))
  }
  #expect(cli.timesAsked == 0)
}

@Test func runningOutOfBudgetIsReportedRatherThanRetriedElsewhere() throws {
  // `gh` uses the same account and the same limit. Asking it after a rate
  // limit spends another request to be told the same thing.
  let token = SpyClient(.failure(.rateLimited))
  let cli = SpyClient(.success(working))

  #expect(throws: GitHubError.rateLimited) {
    try ask(TokenFirstGitHubClient(token: token, cli: cli))
  }
  #expect(cli.timesAsked == 0)
}

@Test func theReleaseQuestionFollowsTheSameRule() throws {
  let token = SpyClient(.success(working), release: .failure(.noToken))
  let cli = SpyClient(.success(working), release: .success(RunnerVersion(2, 330, 0)))

  #expect(
    try TokenFirstGitHubClient(token: token, cli: cli).blockingLatestRunnerRelease()
      == RunnerVersion(2, 330, 0))
}
