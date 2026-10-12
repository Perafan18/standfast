import Foundation
import RunnerKit
import Testing

@testable import Standfast

// Compared against the L10n constants: the host may speak Spanish, and what is
// pinned here is which words reach which place. The exact copy is in L10nTests.

private let overviewNow = Date(timeIntervalSince1970: 1_785_962_174)

private func overviewCard(
  _ name: String, _ display: DisplayState,
  scope: RunnerScope = .repository(owner: "acme", name: "widget"),
  installation: RunnerInstallation = .launchAgent
) -> RunnerCardPresentation {
  let snapshot = RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: scope, installation: installation),
    display: display, readAt: overviewNow)
  return RunnerCardPresentation.building(
    snapshot, measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
    maintenanceNotice: nil, now: overviewNow)
}

/// One top-level declaration of `source`, from its opening line to the brace
/// that closes it, so a check about one view cannot pass on another's line.
private func declaration(_ opening: String, in source: String) -> String {
  guard let start = source.range(of: opening) else { return "" }
  let rest = source[start.lowerBound...]
  guard let end = rest.range(of: "\n}\n") else { return String(rest) }
  return String(rest[..<end.upperBound])
}

/// Whether `pieces` appear in `text` in this order, none overlapping.
private func reads(_ text: String, inOrder pieces: [String]) -> Bool {
  var rest = text[...]
  for piece in pieces {
    guard let found = rest.range(of: piece) else { return false }
    rest = rest[found.upperBound...]
  }
  return true
}

// MARK: - What the rows say

@Test func anOverviewRowSpeaksEachReadingAfterItsLayersName() {
  // On screen the column says which layer a reading is. VoiceOver hears no
  // column, and "Running, Offline" leaves the listener guessing which half of
  // the runner is down.
  let disconnected = overviewCard("deploy-mac", .resolved(.disconnected)).layers
  #expect(
    reads(
      disconnected.accessibilityValue,
      inOrder: [
        L10n.controlCenterThisMac, L10n.layerLocalRunning, L10n.gitHub,
        L10n.layerRemoteOffline,
      ]))

  let gitLab = overviewCard(
    "gl-docs", .resolved(.stopped),
    scope: .gitLab(instance: GitLabInstance(url: "https://gitlab.example.com")!),
    installation: .gitLabService
  ).layers
  #expect(
    reads(
      gitLab.accessibilityValue,
      inOrder: [
        L10n.controlCenterThisMac, L10n.layerLocalNotRunning, L10n.gitLab,
        L10n.layerRemoteNotAskedStopped,
      ]))

  let slot = overviewCard(
    "slot-1", .resolved(.idle), scope: .organization("acme"), installation: .managedFleet
  ).layers
  #expect(
    reads(
      slot.accessibilityValue,
      inOrder: [
        L10n.controlCenterFleetSupervisor, L10n.layerLocalRunning, L10n.gitHub,
        L10n.layerRemoteOnline,
      ]))
}

@Test func theDiscoveryNoticeNamesWhatCouldNotBeReadAndKeepsEveryPath() {
  let directory = ControlCenterNoticePresentation.launchAgentsUnavailable(
    directory: "~/Library/LaunchAgents")
  let files = ControlCenterNoticePresentation.unreadableRunners(paths: [
    "~/Library/LaunchAgents/actions.runner.a.plist",
    "~/Library/LaunchAgents/actions.runner.b.plist",
  ])

  // Headings, not the menu's lead-ins: here the paths sit behind a button,
  // and a colon would point at nothing.
  #expect(directory.title == L10n.launchAgentsUnreadableTitle)
  #expect(files.title == L10n.someRunnersUnreadableTitle)
  // Every path, in order, none folded into "and more": the popover is where
  // somebody goes to find the file, and the quick menu already summarises.
  let everyPath = [
    "~/Library/LaunchAgents/actions.runner.a.plist",
    "~/Library/LaunchAgents/actions.runner.b.plist",
  ]
  #expect(files.detailLines == everyPath)
  #expect(directory.detailLines == ["~/Library/LaunchAgents"])
  // The words the empty state uses for the same failure, so a fleet that
  // shrinks to nothing does not rename what went wrong.
  let emptied = [
    ControlCenterEmptyPresentation.launchAgentsUnavailable(directory: "/x").title,
    ControlCenterEmptyPresentation.unreadableRunners(paths: ["/x"]).title,
  ]
  #expect(emptied == [directory.title, files.title])
}

// MARK: - How the view is put together

@Test func theOverviewListsWhatTheHeaderCountsAndRanksNothingItself() {
  // The header's count and the list under it come from one value. A filter
  // by tone listed runners stopped on purpose, which the header does not
  // count, and left out a failed order, which it does.
  let source = standfastSource("ControlCenterView.swift")

  #expect(source.contains("let attention = presentation.runnersNeedingAttention"))
  #expect(source.contains("ForEach(attention)"))
  #expect(source.contains("ForEach(presentation.runnersByAttention)"))
  #expect(!source.contains("attentionRank"))
  #expect(!source.contains(".sorted"))
}

@Test func overviewRowsLineUpWithoutGridRowsInsideButtons() {
  // A `GridRow` inside a `Button` is no longer its grid's child, so its
  // columns drift from row to row. Each row is a stack with fixed columns.
  let source = standfastSource("ControlCenterView.swift")

  #expect(!source.contains("GridRow"))
  #expect(source.contains(".frame(width: localColumnWidth, alignment: .leading)"))
  #expect(source.contains(".frame(width: remoteColumnWidth, alignment: .leading)"))
  #expect(source.contains(".buttonStyle(.plain)"))
  #expect(source.contains(".accessibilityValue(card.layers.accessibilityValue)"))
}

@Test func overviewRowsStackTheirReadingsWhereTheColumnsDoNotFit() {
  // About 325 points of fixed columns, and the detail can be 360 wide: the
  // window at its least width with the sidebar at its widest. Without a
  // fallback the name wraps a few letters a line, then the row overflows.
  let source = standfastSource("ControlCenterView.swift")

  #expect(source.contains("ViewThatFits(in: .horizontal)"))
  // One ideal width for every name, so a section stacks all its rows or
  // none, rather than the long names alone.
  #expect(
    source.contains(
      ".frame(idealWidth: nameColumnWidth, maxWidth: .infinity, alignment: .leading)"))
}

@Test func anOverviewRowSaysWhereItsRunnerIsRegistered() {
  // The scope is printed under the name. A label of the name alone left two
  // runners of one name, in two repositories, sounding the same.
  let row = declaration(
    "private struct OverviewRunnerRow: View {",
    in: standfastSource("ControlCenterView.swift"))

  // The registered name, not the title, which carries the scope already
  // where names are shared.
  #expect(row.contains(".accessibilityLabel(L10n.runnerInScope(card.name, card.scope))"))
  #expect(!row.contains(".accessibilityLabel(card.title)"))
}

@Test func noticesKeepTheirWordsPrimaryAndThePathsWholeAndSelectable() {
  // The header's attention line and discovery's notice. Orange words measured
  // 1.04:1 in dark mode; the triangle carries the colour now, and the words
  // stay primary beside it.
  let source = standfastSource("ControlCenterView.swift")
  let multicolour = source.components(separatedBy: ".symbolRenderingMode(.multicolor)")

  #expect(multicolour.count - 1 == 2)
  #expect(source.contains(".popover(isPresented: $showsPaths)"))
  #expect(source.contains(".textSelection(.enabled)"))
  #expect(source.contains(".monospaced()"))
}

@Test func aLongListOfPathsScrollsRatherThanRunOffTheScreen() {
  // Discovery reports every file it could not read, and the popover and the
  // empty state both show them all.
  let source = standfastSource("ControlCenterView.swift")

  // The popover is as tall as its paths, up to a cap, and scrolls past it.
  let notice = declaration("private struct DiscoveryNoticeRow: View {", in: source)
  #expect(notice.contains("ScrollView {\n            PathList(paths: notice.detailLines)"))
  #expect(notice.contains(".frame(maxHeight: popoverMaximumHeight)"))
  #expect(notice.contains(".fixedSize(horizontal: false, vertical: true)"))
  // The empty state does not hand its description the room that is left, so
  // a list that does not fit scrolls the whole view, icon and title with it.
  let empty = declaration("struct ControlCenterEmptyView: View {", in: source)
  #expect(empty.contains("ViewThatFits(in: .vertical) {"))
  #expect(empty.contains("ScrollView { unavailable }"))
  // Selectable wherever it is shown.
  #expect(
    declaration("private struct PathList: View {", in: source).contains(
      ".textSelection(.enabled)"))
}

@Test func theMacsHeatIsOneElementWhereverItIsShown() {
  // On the Overview, and over the runner whose job it slows.
  for name in ["ControlCenterView.swift", "RunnerCardView.swift"] {
    #expect(
      standfastSource(name).contains(
        ".accessibilityIdentifier(ControlCenterAccessibility.thermal)"),
      "\(name)")
  }
}

@Test func theEmptyStatesAreTheSystemsOwnAndStillOfferAWayOut() {
  let source = standfastSource("ControlCenterView.swift")

  #expect(source.contains("ContentUnavailableView {"))
  #expect(source.contains("ProgressView {"))
  #expect(
    source.contains(".accessibilityIdentifier(ControlCenterAccessibility.installGuide)"))
  // Named for where it goes: Settings opens on General, and a button promising
  // to add a runner folder would leave somebody hunting for the tab that does.
  let settingsLink = "SettingsLink {\n          Text(L10n.settings)"
  #expect(source.contains(settingsLink))
  #expect(!source.contains("L10n.settingsRunnersAdd"))
}
