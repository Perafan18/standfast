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
      scope: .gitLab(instance: GitLabInstance(url: "https://gitlab.example.com")!),
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

@Test func aGitLabRunnerOffersNoMaintenance() {
  // Its directory is `~/.gitlab-runner`, which has no `_work` or `_diag`, so a
  // measurement there reports an empty disk while the builds sit in
  // `builds_dir`, a folder this app never reads.
  let section = MaintenanceSection.building(
    gitLabSnapshot(), measurement: nil, latest: nil, isWorking: false, notice: nil,
    now: Date(timeIntervalSince1970: 0))

  #expect(section.offers.isEmpty)
  #expect(section.measured == L10n.diskGitLabService)
}

@Test func aGitLabRunnersLinkSaysItOpensGitLab() {
  // The link can only reach the instance's home page, so "View settings" and
  // "Open runner settings" promised a page nobody lands on.
  let card = RunnerCardPresentation.building(
    gitLabSnapshot(), measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 0), fleetSize: 1)

  guard case .instance(let url) = card.githubDestination else {
    Issue.record("A GitLab runner links to \(card.githubDestination)")
    return
  }
  #expect(url.host == "gitlab.example.com")
  #expect(card.action(.openOnGitHub)?.label == L10n.openGitLab)
  #expect(card.action(.openOnGitHub)?.accessibilityLabel == L10n.openGitLab)
}

@Test func aRunnerGitLabCannotSeeNamesGitLabWhereverItsStateIsRead() throws {
  // GitLab is what was asked, so a sentence naming GitHub sends somebody to
  // the wrong service to look.
  let snapshot = gitLabSnapshot(.resolved(.disconnected))
  let card = RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 0), fleetSize: 1)
  let menu = QuickMenuPresentation.building(
    snapshots: [snapshot],
    overview: .building(snapshots: [snapshot], notice: nil),
    thermalLines: [], readAt: nil, now: Date(timeIntervalSince1970: 0))
  guard case .runner(let echo) = menu.items.first else {
    Issue.record("The quick menu lost the runner: \(menu.items)")
    return
  }

  #expect(card.focus == .state(L10n.stateDisconnectedGitLab))
  for line in [card.state, snapshot.row.title, echo.longState] {
    #expect(line.contains(L10n.stateDisconnectedGitLab), "\(line)")
    #expect(!line.contains("GitHub"), "\(line)")
  }
}

@Test func aRunnerGitLabCannotSeeIsAnnouncedInGitLabsName() {
  // Both routes to the banner: found disconnected at the first scan (D-R19),
  // and falling off while the app watched. No grace: the wording is the
  // subject here, and FleetEventsTests owns the wait.
  var atLaunch = FleetWatcher(disconnectionGrace: 0)
  let found = atLaunch.events(in: [gitLabSnapshot(.resolved(.disconnected))])
  var watching = FleetWatcher(disconnectionGrace: 0)
  _ = watching.events(in: [gitLabSnapshot(.resolved(.idle))])
  let fell = watching.events(in: [gitLabSnapshot(.resolved(.disconnected))])

  let banner = [L10n.notificationDisconnectedGitLabBody("mac-gitlab")]
  #expect(found.map(\.body) == banner)
  #expect(fell.map(\.body) == banner)
}

@Test func aRunnerPausedInGitLabSaysPausedWhereverItsStateIsRead() throws {
  // Paused in GitLab to drain it. "GitLab cannot see it" would be false, and
  // "not answering" would send somebody to check a network that is fine.
  let snapshot = gitLabSnapshot(.resolved(.unknown(.gitLabPaused)))
  let card = RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 0), fleetSize: 1)
  let menu = QuickMenuPresentation.building(
    snapshots: [snapshot],
    overview: .building(snapshots: [snapshot], notice: nil),
    thermalLines: [], readAt: nil, now: Date(timeIntervalSince1970: 0))
  guard case .runner(let echo) = menu.items.first else {
    Issue.record("The quick menu lost the runner: \(menu.items)")
    return
  }

  #expect(snapshot.display.shortSummary == L10n.stateLayerGitLabPaused)
  #expect(card.state == L10n.stateUnknownGitLabPaused)
  for line in [card.state, snapshot.row.title, echo.longState] {
    #expect(line.contains(L10n.stateUnknownGitLabPaused), "\(line)")
    #expect(!line.contains(L10n.stateDisconnectedGitLab), "\(line)")
  }
}

@Test func aRunnerPausedInGitLabIsNeverAnnounced() {
  // The same two routes as the disconnection above, with no grace to hide
  // behind: a pause is GitLab's answer, not a runner it lost.
  var atLaunch = FleetWatcher(disconnectionGrace: 0)
  let found = atLaunch.events(in: [gitLabSnapshot(.resolved(.unknown(.gitLabPaused)))])
  var watching = FleetWatcher(disconnectionGrace: 0)
  _ = watching.events(in: [gitLabSnapshot(.resolved(.idle))])
  let paused = watching.events(in: [gitLabSnapshot(.resolved(.unknown(.gitLabPaused)))])

  #expect(found.isEmpty)
  #expect(paused.isEmpty)
}

@Test func anUnreadableProcessListIsNotBlamedOnLaunchctl() {
  // A GitLab or hand-started runner's local half comes from `ps`; only a
  // LaunchAgent is asked through `launchctl`.
  func state(of snapshot: RunnerSnapshot) -> String {
    RunnerCardPresentation.building(
      snapshot, measurement: nil, latestRelease: nil,
      isMaintenanceWorking: false, maintenanceNotice: nil,
      now: Date(timeIntervalSince1970: 0), fleetSize: 1
    ).state
  }
  let unreadable = DisplayState.resolved(.unknown(.serviceStateUnreadable))

  #expect(state(of: gitLabSnapshot(unreadable)) == L10n.stateUnknownNoLocalAnswerProcess)
  #expect(state(of: manualSnapshot(unreadable)) == L10n.stateUnknownNoLocalAnswerProcess)
  #expect(state(of: servicedSnapshot(unreadable)) == L10n.stateUnknownNoLocalAnswer)
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
