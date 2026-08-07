import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let promptMoment = Date(timeIntervalSince1970: 1_785_962_174)

@MainActor
final class FakeServiceAlertPresentation: ServiceAlertPresentation {
  private(set) var dismissals = 0

  func dismiss() { dismissals += 1 }
}

@MainActor
final class FakeServiceAlertPresenter: ServiceAlertPresenting {
  private(set) var prompts: [ServiceActionPrompt] = []
  private(set) var presentations: [FakeServiceAlertPresentation] = []
  private var completions: [@MainActor (Bool) -> Void] = []
  var canPresent = true

  func present(
    _ prompt: ServiceActionPrompt,
    completion: @escaping @MainActor (Bool) -> Void
  ) -> (any ServiceAlertPresentation)? {
    guard canPresent else { return nil }
    let presentation = FakeServiceAlertPresentation()
    prompts.append(prompt)
    presentations.append(presentation)
    completions.append(completion)
    return presentation
  }

  func finish(_ accepted: Bool, presentation index: Int = 0) {
    completions[index](accepted)
  }
}

@MainActor
private final class ServiceAlertResultProbe {
  var answer: ServiceActionConfirmationResult?
}

private enum ServiceAlertTestFailure: Error {
  case presentationNeverStarted
}

@MainActor
private func waitForServiceAlert(
  _ condition: @escaping @MainActor () -> Bool
) async throws {
  for _ in 0..<200 {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw ServiceAlertTestFailure.presentationNeverStarted
}

private func promptSnapshot(
  display: DisplayState = .resolved(.busy),
  runner: DiscoveredRunner? = nil,
  runningJob: JobRecord? = JobRecord(name: "testflight", startedAt: promptMoment),
  readAt: Date = promptMoment,
  stateReadAt: Date? = nil,
  version: RunnerVersion? = nil,
  operation: ServiceOperation? = nil
) -> RunnerSnapshot {
  let runner =
    runner
    ?? DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac",
      directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "widget"))
  let jobs = runningJob.map { JobHistory(records: [$0], running: $0) } ?? .empty
  return RunnerSnapshot(
    runner: runner, display: display, jobs: jobs, readAt: readAt,
    stateReadAt: stateReadAt, version: version, operation: operation)
}

@Test func busyStopConfirmationNamesTheRunnerScopeAndCurrentJob() throws {
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))

  #expect(prompt.action == .stop)
  #expect(prompt.runnerID == "actions.runner.acme-widget.build-mac")
  #expect(prompt.display == .resolved(.busy))
  #expect(prompt.runningJob?.name == "testflight")
  #expect(prompt.runningJob?.startedAt == promptMoment)
  #expect(prompt.title == "Stop build-mac?")
  #expect(
    prompt.message
      == "build-mac in acme/widget is running “testflight”. "
      + "Stopping it interrupts this job.")
  #expect(prompt.confirm == "Stop")
  #expect(prompt.cancel == "Cancel")
}

@Test func busyRestartConfirmationNamesBothConsequences() throws {
  let prompt = try #require(
    ServiceActionPrompt(action: .restart, snapshot: promptSnapshot(), bundles: []))

  #expect(prompt.title == "Restart build-mac?")
  #expect(
    prompt.message
      == "build-mac in acme/widget is running “testflight”. "
      + "Restarting interrupts this job. If Start fails after Stop, the runner can "
      + "remain stopped.")
  #expect(prompt.confirm == "Restart")
  #expect(prompt.cancel == "Cancel")
}

@Test func everyUncertainDisplayWarnsAboutPossibleWorkWithoutInventingAJob()
  throws
{
  let displays: [DisplayState] = [
    .resolved(.disconnected),
    .resolved(.unknown(.cliUnavailable)),
    .resolved(.unknown(.notAuthenticated)),
    .resolved(.unknown(.noAnswer)),
    .resolved(.unknown(.serviceStateUnreadable)),
    .starting,
  ]
  for display in displays {
    let snapshot = promptSnapshot(display: display)
    let stop = try #require(
      ServiceActionPrompt(action: .stop, snapshot: snapshot, bundles: []))
    let restart = try #require(
      ServiceActionPrompt(action: .restart, snapshot: snapshot, bundles: []))

    #expect(
      stop.message
        == "build-mac in acme/widget may have work in progress. "
        + "Stopping it can interrupt that work.")
    #expect(
      restart.message
        == "build-mac in acme/widget may have work in progress. "
        + "Restarting can interrupt that work. If Start fails after Stop, the runner "
        + "can remain stopped.")
    #expect(!stop.message.contains("testflight"))
    #expect(!restart.message.contains("testflight"))
  }
}

@Test func safeServiceActionsDoNotProduceAConfirmationPrompt() {
  let idle = promptSnapshot(display: .resolved(.idle), runningJob: nil)
  let stopped = promptSnapshot(display: .resolved(.stopped), runningJob: nil)

  #expect(ServiceActionPrompt(action: .stop, snapshot: idle, bundles: []) == nil)
  #expect(ServiceActionPrompt(action: .restart, snapshot: idle, bundles: []) == nil)
  #expect(ServiceActionPrompt(action: .start, snapshot: stopped, bundles: []) == nil)
}

@Test func promptFingerprintAllowsUnrelatedSnapshotRefreshMetadata() throws {
  let original = promptSnapshot()
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: original, bundles: []))
  let refreshed = promptSnapshot(
    readAt: promptMoment.addingTimeInterval(30),
    stateReadAt: promptMoment.addingTimeInterval(31),
    version: RunnerVersion(9, 9, 9),
    operation: ServiceOperation(
      action: .restart, phase: .requestAccepted,
      changedAt: promptMoment.addingTimeInterval(32)))

  #expect(prompt.stillMatches(refreshed))
}

@Test func promptFingerprintRejectsRunnerDisplayScopeAndJobIdentityChanges() throws {
  let original = promptSnapshot()
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: original, bundles: []))
  let renamed = DiscoveredRunner(
    label: original.runner.label, directory: original.runner.directory,
    agentId: original.runner.agentId, agentName: "release-mac",
    scope: original.runner.scope)
  let movedScope = DiscoveredRunner(
    label: original.runner.label, directory: original.runner.directory,
    agentId: original.runner.agentId, agentName: original.runner.agentName,
    scope: .enterprise("acme"))

  #expect(!prompt.stillMatches(promptSnapshot(display: .resolved(.idle))))
  #expect(!prompt.stillMatches(promptSnapshot(runner: renamed)))
  #expect(!prompt.stillMatches(promptSnapshot(runner: movedScope)))
  #expect(
    !prompt.stillMatches(
      promptSnapshot(
        runningJob: JobRecord(name: "deploy", startedAt: promptMoment))))
  #expect(
    !prompt.stillMatches(
      promptSnapshot(
        runningJob: JobRecord(
          name: "testflight", startedAt: promptMoment.addingTimeInterval(1)))))
  #expect(!prompt.stillMatches(promptSnapshot(runningJob: nil)))
}

@Test func serviceAlertKeysMakeEscapeCancelAndReturnConfirmNothing() {
  #expect(ServiceConfirmationKeys.cancel == "\u{1B}")
  #expect(ServiceConfirmationKeys.confirm == "")
}

@Test @MainActor
func serviceAlertConfirmationSuspendsAndLetsMainActorRefreshWhileOpen() async throws {
  let presenter = FakeServiceAlertPresenter()
  let confirmation = ServiceAlertConfirmation(presenter: presenter)
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))
  let result = ServiceAlertResultProbe()

  let task = Task { @MainActor in
    let answer = await confirmation.confirm(prompt)
    result.answer = answer
    return answer
  }
  try await waitForServiceAlert { presenter.prompts.count == 1 }

  var refreshes = 0
  await Task { @MainActor in refreshes += 1 }.value

  #expect(refreshes == 1)
  #expect(result.answer == nil)
  presenter.finish(true)
  #expect(await task.value == .accepted)
}

@Test @MainActor func serviceAlertConfirmationReturnsTheSheetAnswer() async throws {
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))

  for answer in [true, false] {
    let presenter = FakeServiceAlertPresenter()
    let confirmation = ServiceAlertConfirmation(presenter: presenter)
    let task = Task { @MainActor in await confirmation.confirm(prompt) }
    try await waitForServiceAlert { presenter.prompts.count == 1 }

    presenter.finish(answer)

    #expect(await task.value == (answer ? .accepted : .cancelled))
  }
}

@Test @MainActor func aMissingAlertParentFailsClosed() async throws {
  let presenter = FakeServiceAlertPresenter()
  presenter.canPresent = false
  let confirmation = ServiceAlertConfirmation(presenter: presenter)
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))

  #expect(await confirmation.confirm(prompt) == .unavailable)
  #expect(presenter.presentations.isEmpty)
}

@Test @MainActor func cancellationBeforeConfirmationStartsNeverPresents() async throws {
  let presenter = FakeServiceAlertPresenter()
  let confirmation = ServiceAlertConfirmation(presenter: presenter)
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))

  // This test retains the MainActor until cancellation, so the task body
  // deterministically observes cancellation before it can call the presenter.
  let task = Task { @MainActor in await confirmation.confirm(prompt) }
  task.cancel()

  #expect(await task.value == .cancelled)
  #expect(presenter.prompts.isEmpty)
}

@Test @MainActor func cancellationWhileTheSheetIsVisibleDismissesAndReturnsFalse()
  async throws
{
  let presenter = FakeServiceAlertPresenter()
  let confirmation = ServiceAlertConfirmation(presenter: presenter)
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))
  let task = Task { @MainActor in await confirmation.confirm(prompt) }
  try await waitForServiceAlert { presenter.prompts.count == 1 }

  task.cancel()
  // Leave the task a bounded opportunity to run its cancellation handler, but
  // finish the fake afterwards so a cancellation-unaware mutation cannot hang
  // the suite and instead fails on both observable outcomes below.
  try await Task.sleep(for: .milliseconds(10))
  let dismissalsBeforeCompletion = presenter.presentations[0].dismissals
  presenter.finish(true)

  #expect(dismissalsBeforeCompletion == 1)
  #expect(await task.value == .cancelled)
  #expect(presenter.presentations[0].dismissals == 1)
}

@Test @MainActor func sheetCompletionWinningTheCancellationRaceResumesOnce()
  async throws
{
  let presenter = FakeServiceAlertPresenter()
  let confirmation = ServiceAlertConfirmation(presenter: presenter)
  let prompt = try #require(
    ServiceActionPrompt(action: .stop, snapshot: promptSnapshot(), bundles: []))
  let task = Task { @MainActor in await confirmation.confirm(prompt) }
  try await waitForServiceAlert { presenter.prompts.count == 1 }

  presenter.finish(true)
  task.cancel()
  presenter.finish(false)

  #expect(await task.value == .accepted)
  #expect(presenter.presentations[0].dismissals == 0)
}
