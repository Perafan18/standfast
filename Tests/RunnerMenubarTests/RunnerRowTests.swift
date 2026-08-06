import Foundation
import RunnerKit
import Testing

@testable import RunnerMenubar

private func runner(
  name: String = "build-mac", agentName: String? = nil
) -> DiscoveredRunner {
  DiscoveredRunner(
    label: "actions.runner.acme-widget.\(name)",
    directory: URL(fileURLWithPath: "/tmp/\(name)"),
    agentId: 7, agentName: agentName ?? name,
    scope: .repository(owner: "acme", name: "widget"))
}

private func snapshot(
  _ display: DisplayState, name: String = "build-mac", agentName: String? = nil
) -> RunnerSnapshot {
  RunnerSnapshot(runner: runner(name: name, agentName: agentName), display: display)
}

// MARK: - The title

@Test func theTitleNamesTheRunnerAndItsState() {
  let row = snapshot(.resolved(.busy)).row
  #expect(row.title.contains("build-mac"))
  #expect(row.title.contains(L10n.stateBusy))
}

@Test func aRunnerWithNoNameOfItsOwnStillGetsARow() {
  // `.runner` does not always carry a name. Reading `agentName` renders a
  // blank row followed by four buttons belonging to nobody; `displayName`
  // falls back to the label without its `actions.runner.` prefix.
  let nameless = snapshot(.resolved(.idle), agentName: "")
  #expect(nameless.row.title.contains("acme-widget.build-mac"))
  #expect(!nameless.row.title.hasPrefix(" "))
  #expect(nameless.row.title != L10n.runnerRow("", L10n.stateIdle))
}

// MARK: - The actions

@Test func aRowOffersTheSameFourActionsInTheSameOrder() {
  #expect(snapshot(.resolved(.idle)).row.actions.map(\.kind) == [
    .start, .stop, .restart, .openOnGitHub,
  ])
}

@Test func everyActionCarriesItsOwnLabel() {
  let row = snapshot(.resolved(.idle)).row
  #expect(row.action(.start)?.label == L10n.start)
  #expect(row.action(.stop)?.label == L10n.stop)
  #expect(row.action(.restart)?.label == L10n.restart)
  #expect(row.action(.openOnGitHub)?.label == L10n.openOnGitHub)
  #expect(Set(row.actions.map(\.label)).count == 4)
}

@Test func everyActionIsGatedOnItsOwnRunnersState() {
  for state in [
    DisplayState.resolved(.idle), .resolved(.busy), .resolved(.disconnected),
    .resolved(.stopped), .resolved(.unknown(.noAnswer)), .starting,
  ] {
    let row = snapshot(state).row
    #expect(row.action(.start)?.isEnabled == state.canStart)
    #expect(row.action(.stop)?.isEnabled == state.canStop)
    #expect(row.action(.restart)?.isEnabled == state.canRestart)
    // Always: a runner GitHub cannot see is the one you most want to look at.
    #expect(row.action(.openOnGitHub)?.isEnabled == true)
  }
}

@Test func aStoppedRunnerCanBeStartedNoMatterWhatTheRestOfTheFleetIsDoing() {
  // The measured bug, in the shape it actually took: with one idle runner and
  // one stopped runner the fleet summary is `.idle` — correct for the icon —
  // and Start read off that summary left the stopped runner impossible to
  // start, forever. A row cannot see the fleet at all, and this is what says
  // so from the outside.
  let fleet = [
    snapshot(.resolved(.idle), name: "a"), snapshot(.resolved(.stopped), name: "b"),
  ]
  #expect(FleetSummary.summarising(fleet.map(\.display)) == .resolved(.idle))

  #expect(fleet[1].row.action(.start)?.isEnabled == true)
  #expect(fleet[0].row.action(.start)?.isEnabled == false)
  #expect(fleet[1].row.action(.stop)?.isEnabled == false)
  #expect(fleet[0].row.action(.stop)?.isEnabled == true)
}

@Test func startAndStopAreNeverEnabledTogether() {
  // They are separate booleans, and wiring one to the other reads as working
  // right up to the state where it does not.
  for state in [
    DisplayState.resolved(.idle), .resolved(.busy), .resolved(.disconnected),
    .resolved(.stopped), .resolved(.unknown(.cliUnavailable)), .starting,
  ] {
    let row = snapshot(state).row
    #expect(row.action(.start)?.isEnabled != row.action(.stop)?.isEnabled)
  }
}

// MARK: - The notice's lines

@Test func theNoRunnersNoticeIsOneLine() {
  #expect(FleetNotice.noRunnersInstalled.lines == [L10n.noRunnersFound])
}

@Test func theUnreadableNoticePrintsPathsAndNeverACount() {
  // A plist duplicated in Finder describes one runner and appears twice, so
  // any number here is one this app invented. The paths are also the only
  // thread the user has to pull on.
  let first = URL(fileURLWithPath: "/Users/someone/Library/LaunchAgents/a.plist")
  let second = URL(fileURLWithPath: "/Users/someone/Library/LaunchAgents/a copy.plist")
  let lines = FleetNotice.unreadable([first, second]).lines

  #expect(lines.count == 3)
  #expect(lines[0] == L10n.someRunnersUnreadable)
  #expect(lines.contains { $0.hasSuffix("Library/LaunchAgents/a.plist") })
  #expect(lines.contains { $0.hasSuffix("Library/LaunchAgents/a copy.plist") })
  #expect(!lines.contains { $0.contains("2") })
}

@Test func theUnreadableNoticeShowsWhereTheFileIsAndNotJustItsName() {
  // Going and looking at the file is the whole point of printing it, and the
  // file name alone does not say where it is.
  let deep = URL(fileURLWithPath: "/Volumes/Backup/LaunchAgents/actions.runner.a.b.plist")
  let lines = FleetNotice.unreadable([deep]).lines
  #expect(lines.last == "/Volumes/Backup/LaunchAgents/actions.runner.a.b.plist")
  #expect(lines.last != "actions.runner.a.b.plist")
}

@Test func aDirectoryFullOfBrokenPlistsDoesNotRunOffTheScreen() {
  let many = (0..<30).map {
    URL(fileURLWithPath: "/Users/someone/Library/LaunchAgents/r\($0).plist")
  }
  let lines = FleetNotice.unreadable(many).lines

  #expect(lines.count == FleetNotice.pathsShown + 2)
  // No number in the overflow line either: it would be a count of unreadable
  // runners by another name, and it would be wrong for the same reason.
  #expect(lines.last == L10n.moreUnreadable)
  #expect(!(lines.last ?? "").contains("20"))
}

@Test func aShortListIsNotTruncated() {
  let few = (0..<FleetNotice.pathsShown).map {
    URL(fileURLWithPath: "/tmp/r\($0).plist")
  }
  #expect(FleetNotice.unreadable(few).lines.count == FleetNotice.pathsShown + 1)
}
