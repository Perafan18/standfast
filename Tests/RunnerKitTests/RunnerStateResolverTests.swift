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
  ).blockingState(for: runner)
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

@Test func aRunnerThatWentOfflineMidJobLeadsWithTheDisconnection() {
  // GitHub reports a Mac that died with a job assigned as offline and busy at
  // once, so the two flags do have to be ranked. The connection is what needs
  // fixing; "busy" would suggest work is progressing when nothing is.
  #expect(
    resolve(localRunning: true, remote: .success(RemoteStatus(online: false, busy: true)))
      == .disconnected)
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
  ).blockingState(for: runner)

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
    isServiceRunning: {
      seen.labels.append($0.label)
      return true
    },
    github: StubGitHub(result: .success(online), asked: StubGitHub.Recorder())
  ).blockingState(for: runner)

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
  ).blockingState(for: runner)

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
  ).blockingState(for: runner)

  #expect(state == .unknown(.noAnswer))
}

// MARK: - The async facade

/// The label of the dispatch queue the calling thread is running on.
///
/// The only signal that separates Swift's cooperative pool from
/// `DispatchQueue.global()`: the former labels itself
/// `com.apple.root.default-qos.cooperative`, the latter drops the suffix.
/// `Thread.isMainThread` cannot tell them apart — it is false for both, because
/// a nonisolated `async` function called from the main actor already hops off
/// the main thread and onto the cooperative pool, which is precisely the pool
/// that must not be blocked.
private func currentQueueLabel() -> String {
  String(cString: __dispatch_queue_get_label(nil))
}

@Test @MainActor func theAsyncFacadeKeepsItsBlockingOffTheCooperativePool() async {
  // The reason this overload exists. `blockingState(for:)` parks a whole
  // thread inside waitUntilExit, twice per call, for up to the command
  // timeout. The cooperative pool has one thread per core and runs every
  // `Task {}` and `Task.detached {}`, so resolving several runners there with
  // the network hanging would stall the pool and everything queued behind it.
  final class Where: @unchecked Sendable {
    var queue: String?
    var onMainThread: Bool?
  }
  let ran = Where()
  let resolver = RunnerStateResolver(
    isServiceRunning: { _ in
      ran.queue = currentQueueLabel()
      ran.onMainThread = Thread.isMainThread
      return true
    },
    github: StubGitHub(result: .success(online), asked: StubGitHub.Recorder()))

  let state = await resolver.state(for: runner)

  #expect(state == .idle)
  #expect(ran.onMainThread == false)
  #expect(ran.queue?.hasSuffix(".cooperative") == false)
}

@Test func theAsyncFacadeAndTheBlockingCallAgreeOnEveryOutcome() async {
  // The hop must not quietly change any answer.
  let cases: [(Bool, Result<RemoteStatus, GitHubError>)] = [
    (true, .success(online)),
    (true, .success(RemoteStatus(online: true, busy: true))),
    (true, .success(RemoteStatus(online: false, busy: false))),
    (false, .success(online)),
    (true, .failure(.cliUnavailable)),
    (true, .failure(.notAuthenticated)),
    (true, .failure(.noAnswer)),
    (false, .failure(.noAnswer)),
  ]
  for (localRunning, remote) in cases {
    let resolver = RunnerStateResolver(
      isServiceRunning: { _ in localRunning },
      github: StubGitHub(result: remote, asked: StubGitHub.Recorder()))
    #expect(await resolver.state(for: runner) == resolver.blockingState(for: runner))
  }
}

@Test func doesNotAskGitHubAboutARunnerThatIsNotEvenRunning() {
  // Nothing GitHub could say changes the answer, and this runs on a timer:
  // paying for an API call per stopped runner, every refresh, all day, buys
  // a result that is thrown away.
  let recorder = StubGitHub.Recorder()
  let state = RunnerStateResolver(
    isServiceRunning: { _ in false },
    github: StubGitHub(result: .success(online), asked: recorder)
  ).blockingState(for: runner)

  #expect(state == .stopped)
  #expect(recorder.questions.isEmpty)
}
