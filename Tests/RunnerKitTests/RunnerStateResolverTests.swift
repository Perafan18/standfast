import Foundation
import Testing

@testable import RunnerKit

private let runner = DiscoveredRunner(
  label: "actions.runner.acme-widget.build-mac",
  directory: URL(fileURLWithPath: "/Users/ci/actions-runner"),
  agentId: 21, agentName: "build-mac",
  scope: .repository(owner: "acme", name: "widget"),
  workFolder: "_work")

private struct StubGitHub: GitHubClient {
  var result: Result<RemoteStatus, GitHubError>
  /// Records what it was asked about, so a resolver that made up its own id or
  /// scope cannot pass by returning the right state for the wrong runner.
  let asked: Recorder

  final class Recorder: @unchecked Sendable {
    private(set) var questions: [(id: Int, scope: RunnerScope)] = []
    func note(_ id: Int, _ scope: RunnerScope) { questions.append((id, scope)) }
  }

  func runnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    asked.note(id, scope)
    return try result.get()
  }
}

private func resolve(
  localRunning: Bool, remote: Result<RemoteStatus, GitHubError>
) -> RunnerState {
  RunnerStateResolver(
    isServiceRunning: { _ in localRunning },
    github: StubGitHub(result: remote, asked: StubGitHub.Recorder())
  ).state(for: runner)
}

private let online = RemoteStatus(online: true, busy: false)

// MARK: - Both sources agree

@Test func idleWhenOnlineAndNotBusy() {
  #expect(resolve(localRunning: true, remote: .success(online)) == .idle)
}

@Test func busyWhenGitHubSaysBusy() {
  #expect(
    resolve(localRunning: true, remote: .success(RemoteStatus(online: true, busy: true)))
      == .busy)
}

@Test func disconnectedWhenAliveLocallyButGitHubDoesNotSeeIt() {
  // The state that earns its own name: the process is up, so "stopped" would
  // be a lie, but no job will ever arrive. Different symptom, different fix.
  #expect(
    resolve(localRunning: true, remote: .success(RemoteStatus(online: false, busy: false)))
      == .disconnected)
}

// MARK: - The local probe wins when it says "stopped"

@Test func stoppedWinsOverEverythingElse() {
  // GitHub lags a few seconds behind a stop, so it will happily still call a
  // just-stopped runner online. The local probe is the one thing known for
  // certain, and a menu that showed "idle" right after the user clicked Stop
  // would look broken.
  #expect(resolve(localRunning: false, remote: .success(online)) == .stopped)
}

@Test func aStoppedRunnerThatGitHubStillCallsBusyIsStillStopped() {
  #expect(
    resolve(localRunning: false, remote: .success(RemoteStatus(online: true, busy: true)))
      == .stopped)
}

@Test func aStoppedServiceIsReportedEvenWithoutGitHub() {
  #expect(resolve(localRunning: false, remote: .failure(.noAnswer)) == .stopped)
}

@Test func aStoppedServiceIsReportedEvenWithoutGh() {
  #expect(resolve(localRunning: false, remote: .failure(.cliUnavailable)) == .stopped)
}

// MARK: - Unknown keeps the cause

@Test func unknownCarriesTheReasonWhenGhIsMissing() {
  #expect(
    resolve(localRunning: true, remote: .failure(.cliUnavailable))
      == .unknown(.cliUnavailable))
}

@Test func unknownCarriesTheReasonWhenGhHasNoCredentials() {
  #expect(
    resolve(localRunning: true, remote: .failure(.notAuthenticated))
      == .unknown(.notAuthenticated))
}

@Test func unknownCarriesTheReasonWhenGitHubStaysSilent() {
  #expect(resolve(localRunning: true, remote: .failure(.noAnswer)) == .unknown(.noAnswer))
}

// MARK: - Wiring

@Test func asksGitHubAboutThisRunnerRatherThanSomeOtherOne() {
  let recorder = StubGitHub.Recorder()
  _ = RunnerStateResolver(
    isServiceRunning: { _ in true },
    github: StubGitHub(result: .success(online), asked: recorder)
  ).state(for: runner)

  #expect(recorder.questions.count == 1)
  #expect(recorder.questions.first?.id == 21)
  #expect(recorder.questions.first?.scope == .repository(owner: "acme", name: "widget"))
}

@Test func probesTheLocalServiceUnderThisRunnersOwnLabel() {
  // One resolver serves every runner on the machine, so a label taken from
  // anywhere but the runner in hand would report one runner's state for all.
  final class Seen: @unchecked Sendable {
    var labels: [String] = []
  }
  let seen = Seen()
  _ = RunnerStateResolver(
    isServiceRunning: { seen.labels.append($0.label); return true },
    github: StubGitHub(result: .success(online), asked: StubGitHub.Recorder())
  ).state(for: runner)

  #expect(seen.labels == ["actions.runner.acme-widget.build-mac"])
}

@Test func theDefaultProbeAsksLaunchctlAboutThisRunnersOwnLabel() {
  // Covers the convenience initialiser, which is the one the app actually
  // uses. The closure-based tests above would all still pass if that
  // initialiser handed the probe the wrong label.
  let fake = FakeCommandRunner([
    ["/bin/launchctl", "list"]: "870\t0\tactions.runner.acme-widget.build-mac"
  ])
  let state = RunnerStateResolver(
    probe: LaunchctlProbe(commandRunner: fake),
    github: StubGitHub(result: .success(online), asked: StubGitHub.Recorder())
  ).state(for: runner)

  #expect(state == .idle)
}

private struct BrokenGitHub: GitHubClient {
  struct Unexpected: Error {}
  func runnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    throw Unexpected()
  }
}

@Test func aClientThatThrowsSomethingElseHasStillNotAnswered() {
  // `GitHubClient` is a protocol, and the token-in-Keychain client planned for
  // v1.0 will throw errors of its own. Falling through to "idle" would report
  // a healthy runner on the strength of an error nobody recognised.
  let state = RunnerStateResolver(
    isServiceRunning: { _ in true }, github: BrokenGitHub()
  ).state(for: runner)

  #expect(state == .unknown(.noAnswer))
}

@Test func doesNotAskGitHubAboutARunnerThatIsNotEvenRunning() {
  // Nothing GitHub could say changes the answer, and this runs on a timer:
  // paying for an API call per stopped runner, every refresh, all day, buys
  // a result that is thrown away.
  let recorder = StubGitHub.Recorder()
  let state = RunnerStateResolver(
    isServiceRunning: { _ in false },
    github: StubGitHub(result: .success(online), asked: recorder)
  ).state(for: runner)

  #expect(state == .stopped)
  #expect(recorder.questions.isEmpty)
}
