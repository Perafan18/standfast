import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let runner = DiscoveredRunner(
  label: "actions.runner.acme-widget.build-mac",
  directory: URL(fileURLWithPath: "/Users/ci/actions-runner"),
  agentId: 21, agentName: "build-mac",
  scope: .repository(owner: "acme", name: "widget"),
  workFolder: "_work")

private func job(_ id: Int) -> QueuedJob {
  QueuedJob(
    id: id, name: "build", workflowName: "CI", labels: ["self-hosted"],
    queuedAt: nil, url: nil)
}

private func card(
  display: DisplayState, queued: QueuedWorkKnowledge, labels: [String] = ["self-hosted"]
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    RunnerSnapshot(runner: runner, display: display, labels: labels, queued: queued),
    measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: Date(timeIntervalSince1970: 0), fleetSize: 1)
}

@Test func aDisconnectedRunnerSaysHowMuchWorkIsPilingUpForIt() {
  // The sentence this feature exists to make possible. "Disconnected" says
  // what broke; "and two jobs are waiting for it" says what it is costing.
  let presentation = card(
    display: .resolved(.disconnected),
    queued: .work(QueuedWork(jobs: [job(1), job(2)], isPartial: false)))

  #expect(presentation.queued?.line == L10n.queueWaiting(2))
  #expect(presentation.queued?.tone == .attention)
}

@Test func aHealthyIdleRunnerWithAnEmptyQueueAddsNoLineAtAll() {
  let presentation = card(
    display: .resolved(.idle), queued: .work(QueuedWork(jobs: [], isPartial: false)))

  #expect(presentation.queued == nil)
}

@Test func theQueueLineSurvivesFolding() {
  // Folding hides controls, navigation and history. What is waiting for a
  // runner is the reason somebody would unfold it, so it belongs with identity
  // and state rather than behind them.
  let presentation = card(
    display: .resolved(.disconnected),
    queued: .work(QueuedWork(jobs: [job(1)], isPartial: false)))

  #expect(presentation.queued != nil)
  #expect(presentation.startsCollapsed == false)
}
