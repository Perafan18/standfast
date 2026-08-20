import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let byHand = URL(fileURLWithPath: "/Users/ci/by-hand")

private func manualSnapshot(_ display: DisplayState = .resolved(.idle)) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: DiscoveredRunner.manualLabel(for: byHand), directory: byHand,
      agentId: 91, agentName: "by-hand",
      scope: .repository(owner: "acme", name: "widget"),
      installation: .manual),
    display: display)
}

private func servicedSnapshot(_ display: DisplayState = .resolved(.idle)) -> RunnerSnapshot
{
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.serviced",
      directory: URL(fileURLWithPath: "/Users/ci/serviced"),
      agentId: 7, agentName: "serviced",
      scope: .repository(owner: "acme", name: "widget")),
    display: display)
}

@Test func aHandStartedRunnerOffersNoServiceControls() {
  // `svc.sh` manages a LaunchAgent, and this runner has none. A Stop button
  // that cannot stop anything is worse than no button: it invites a click and
  // then explains a failure that was certain before it was pressed.
  let row = manualSnapshot(.resolved(.busy)).row

  for kind in [RunnerRow.Action.Kind.start, .stop, .restart] {
    #expect(row.action(kind)?.isEnabled == false, "\(kind) should be unavailable")
  }
}

@Test func aHandStartedRunnerStillOffersTheOneActionThatWorks() {
  // Opening it on GitHub needs nothing from this Mac, and a runner GitHub
  // cannot see is the one you most want to go and look at.
  #expect(
    manualSnapshot(.resolved(.disconnected)).row.action(.openOnGitHub)?.isEnabled == true)
}

@Test func aServicedRunnerKeepsItsControls() {
  let row = servicedSnapshot(.resolved(.busy)).row

  #expect(row.action(.stop)?.isEnabled == true)
  #expect(row.action(.restart)?.isEnabled == true)
}

@Test func theCardSaysWhyAHandStartedRunnerHasNoButtons() {
  // Greyed-out controls with no explanation are the app knowing something and
  // not saying it. Nothing registered this runner, so nothing here can stop
  // it, and that is a fact about how it was started rather than a fault.
  let card = RunnerCardPresentation.building(
    manualSnapshot(), measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 0), fleetSize: 1)

  #expect(card.serviceNote == L10n.runnerStartedByHand)
}

@Test func aServicedCardHasNothingToExplain() {
  let card = RunnerCardPresentation.building(
    servicedSnapshot(), measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 0), fleetSize: 1)

  #expect(card.serviceNote == nil)
}

// MARK: - GitLab runners

private func gitLabSnapshot(
  _ display: DisplayState = .resolved(.idle), labels: [String] = ["macos"],
  queued: QueuedWorkKnowledge = .notAsked
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "standfast.gitlab:gitlab.example.com:91",
      directory: URL(fileURLWithPath: "/Users/ci/.gitlab-runner"),
      agentId: 91, agentName: "mac-gitlab",
      scope: .gitLab(instanceHost: "gitlab.example.com"),
      installation: .gitLabService),
    display: display, labels: labels, queued: queued)
}

@Test func aGitLabRunnerOffersNoServiceControlsAndSaysItsOwnWhy() {
  // One machine-wide process serves every GitLab runner: stopping it stops all
  // of them, which is a terminal's decision, not one card's button. And the
  // note must be GitLab's own — "started by hand" would be a lie about a
  // runner that is running as a service.
  let card = RunnerCardPresentation.building(
    gitLabSnapshot(), measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 0), fleetSize: 1)

  #expect(card.serviceNote == L10n.runnerGitLabService)
  #expect(card.action(.start)?.isEnabled == false)
  #expect(card.action(.stop)?.isEnabled == false)
}

@Test func aGitLabRunnerIsNeverAskedAboutTheGitHubQueue() {
  // Its labels arrive — GitLab tags — so without this guard the model would
  // ask GitHub's queue endpoints about a GitLab runner and report the failure
  // in a sentence about organisations. GitLab's queue is a later feature;
  // silence is honest, a wrong sentence is not.
  let presentation = QueuedWorkPresentation.building(
    .notAsked, runnerLabelled: ["macos"], display: .resolved(.stopped))

  #expect(presentation == nil)
}
