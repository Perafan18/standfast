import Foundation
import RunnerKit
import Testing

@testable import Standfast

// Compared against the L10n constants: the host may speak Spanish, and what is
// pinned here is which words reach which line. The exact copy is in L10nTests.

private let commandsNow = Date(timeIntervalSince1970: 1_785_962_174)

private let diag = URL(fileURLWithPath: "/tmp/build-mac/_diag")

private func commandCard(
  _ display: DisplayState, installation: RunnerInstallation = .launchAgent,
  scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  logs: URL? = nil, jobs: JobHistory = .empty, readAt: Date = commandsNow,
  isServiceActionReserved: Bool = false
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    RunnerSnapshot(
      runner: DiscoveredRunner(
        label: "actions.runner.acme-widget.build-mac",
        directory: URL(fileURLWithPath: "/tmp/build-mac"), agentId: 7,
        agentName: "build-mac", scope: scope, installation: installation),
      display: display, containedDiagnosticsDirectory: logs, jobs: jobs, readAt: readAt,
      isServiceActionReserved: isServiceActionReserved),
    measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: commandsNow)
}

private func target(_ card: RunnerCardPresentation) -> RunnerCommandTarget {
  RunnerCommandTarget(card)
}

// MARK: - What each menu offers

@Test func theRunnerMenuGreysWhatTheToolbarGreysAndNamesItTheSame() {
  let card = commandCard(.resolved(.stopped))
  let lines = RunnerCommandTarget.menuActions(for: target(card))

  #expect(lines.map(\.kind) == [.start, .stop, .restart, .openOnGitHub])
  // The toolbar's own words and enablement, line for line: a menu that
  // disagreed with the button beside it would be the one somebody believed.
  #expect(lines.map(\.label) == card.actions.map(\.label))
  #expect(lines.map(\.isEnabled) == [true, false, false, true])
  #expect(lines.last?.label == L10n.viewRuns())
}

@Test func withNothingSelectedTheRunnerMenuKeepsEveryLineAndGreysThemAll() {
  // The Overview, another window, or no Control Center at all. A menu whose
  // lines come and go with the selection cannot be learnt.
  let lines = RunnerCommandTarget.menuActions(for: nil)

  #expect(lines.map(\.kind) == [.start, .stop, .restart, .openOnGitHub])
  #expect(lines.allSatisfy { !$0.isEnabled })
  #expect(
    lines.map(\.label)
      == [L10n.serviceStart, L10n.serviceStop, L10n.serviceRestart, L10n.openInBrowser])
  // Which host the destination opens is the runner's to say; a Mac with only
  // GitLab runners must not be offered GitHub.
  let destination = lines.last?.label ?? ""
  #expect(!destination.contains("GitHub") && !destination.contains("GitLab"))
}

@Test func aContextMenuOffersOnlyWhatCanBeDoneNow() {
  // A running runner: no Start, which would do nothing.
  #expect(
    target(commandCard(.resolved(.idle))).availableActions.map(\.kind)
      == [.stop, .restart, .openOnGitHub])
  #expect(
    target(commandCard(.resolved(.stopped))).availableActions.map(\.kind)
      == [.start, .openOnGitHub])
  // Mid-order, every service verb waits; the destination never does.
  #expect(
    target(commandCard(.resolved(.idle), isServiceActionReserved: true))
      .availableActions.map(\.kind) == [.openOnGitHub])
  // A runner no service runs has its destination and nothing else.
  #expect(
    target(commandCard(.resolved(.idle), installation: .manual))
      .availableActions.map(\.kind) == [.openOnGitHub])
}

@Test func onlyARunnerWithALogFolderOfItsOwnOffersToShowIt() {
  #expect(target(commandCard(.resolved(.idle), logs: diag)).canShowLogs)
  #expect(
    target(commandCard(.resolved(.idle), installation: .manual, logs: diag)).canShowLogs)
  // Not yet written, or symlinked out of the runner: the scan proved none.
  #expect(!target(commandCard(.resolved(.idle))).canShowLogs)
  // gitlab-runner keeps no `_diag`, and a fleet slot's are its supervisor's.
  let gitLab = RunnerScope.gitLab(
    instance: GitLabInstance(url: "https://gitlab.example.com")!)
  #expect(
    !target(
      commandCard(.resolved(.idle), installation: .gitLabService, scope: gitLab, logs: diag)
    ).canShowLogs)
  #expect(
    !target(commandCard(.resolved(.idle), installation: .managedFleet, logs: diag))
      .canShowLogs)
}

@Test func theMenuBarIsNotRebuiltBecauseAJobRanOnAnotherFewSeconds() {
  // The card changes with every scan while a job runs, and the focused value
  // is compared to decide whether the menu bar's commands are rebuilt.
  let live = JobRecord(name: "testflight", startedAt: commandsNow.addingTimeInterval(-80))
  let jobs = JobHistory(records: [live], running: live)
  let earlier = commandCard(.resolved(.busy), jobs: jobs)
  let later = commandCard(.resolved(.busy), jobs: jobs, readAt: commandsNow + 15)

  #expect(earlier.progress != later.progress)
  #expect(target(earlier) == target(later))
  // And it does move when what can be done does.
  #expect(target(earlier) != target(commandCard(.resolved(.stopped))))
}

@Test func theNameCopiedIsTheOneTheSidebarShows() {
  let card = commandCard(.resolved(.idle))

  #expect(target(card).title == card.title)
  #expect(target(card).id == card.id)
}

// MARK: - How it is wired

@Test func theRunnerMenuIsTheToolbarsTwinAndLeavesCommandRToTheToolbar() {
  let app = standfastSource("App.swift")
  let commands = standfastSource("RunnerCommands.swift")
  let controlCenter = standfastSource("ControlCenterView.swift")

  #expect(app.contains(".commands { RunnerCommands(fleet: fleet) }"))
  #expect(commands.contains("CommandMenu(L10n.runnerMenu)"))
  #expect(commands.contains("@FocusedValue(\\.selectedRunner)"))
  #expect(
    controlCenter.contains(
      ".focusedSceneValue(\\.selectedRunner, selected.map(RunnerCommandTarget.init))"))
  // One ⌘R, on the toolbar's Refresh. The menu bar is not there without a Dock
  // tile, and a second binding would make which one answers the system's call.
  #expect(!commands.contains(".keyboardShortcut("))
  #expect(!app.contains(".keyboardShortcut("))
  #expect(controlCenter.components(separatedBy: ".keyboardShortcut(\"r\")").count - 1 == 1)
  #expect(commands.contains("Button(L10n.refreshNow) { fleet.refresh() }"))
}

@Test func everyRouteActsThroughTheModelThatRechecksIt() {
  // Through `perform`, as the toolbar goes, so a Stop that would interrupt a
  // job still asks first, and a stale menu cannot act on a runner that left.
  let commands = standfastSource("RunnerCommands.swift")

  #expect(
    commands.contains(
      "Button(action.label) { fleet.perform(action.kind, onRunnerID: target.id) }"))
  #expect(commands.contains("fleet.perform(action.kind, onRunnerID: runner.id)"))
  #expect(commands.contains("fleet.showLogs(onRunnerID: target.id)"))
  #expect(commands.contains("fleet.showLogs(onRunnerID: runner.id)"))
  #expect(
    standfastSource("ControlCenterView.swift").contains(
      "fleet.showLogs(onRunnerID: card.id)"))
  // Finder is reached through the model's seam alone, never from a view.
  for name in standfastSourceNames() where name != "URLOpener.swift" {
    #expect(!standfastSource(name).contains("activateFileViewerSelecting"), "\(name)")
  }
}

@Test func theSidebarsContextMenuActsOnTheRowClicked() {
  // A right-click does not move the selection, so the menu cannot read the
  // runner the detail shows.
  let source = standfastSource("ControlCenterView.swift")

  #expect(source.contains(".contextMenu(forSelectionType: ControlCenterSelection.self)"))
  #expect(
    source.contains("presentation.cards.first(where: { clicked == [.runner($0.id)] })"))
  #expect(
    source.contains("RunnerContextMenu(target: RunnerCommandTarget(card), fleet: fleet)"))
}

@Test func copyNameReplacesWhatWasOnThePasteboard() {
  // AppKit refuses a write to a pasteboard whose old contents were not
  // cleared first, and Copy name would copy nothing and say nothing.
  let source = standfastSource("RunnerCommands.swift")
  let cleared = source.range(of: "pasteboard.clearContents()")
  let written = source.range(of: "pasteboard.setString(name, forType: .string)")

  #expect(cleared != nil && written != nil)
  if let cleared, let written { #expect(cleared.upperBound <= written.lowerBound) }
  #expect(source.contains("Button(L10n.copyName) { copy(target.title) }"))
}

@Test func theDetailShowsTheLogFolderBesideMaintenanceOnlyWhereThereIsOne() {
  let source = standfastSource("RunnerCardView.swift")

  #expect(source.contains("if card.diagnosticsDirectory != nil {"))
  #expect(source.contains("Button(L10n.showLogsInFinder, action: showLogs)"))
  #expect(source.contains(".accessibilityIdentifier(identifiers.logs)"))
  // Named with its runner, as every maintenance action is.
  #expect(
    source.contains(
      ".accessibilityLabel(L10n.runnerInScope(L10n.showLogsInFinder, card.title))"))
}
