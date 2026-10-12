import Foundation
import RunnerKit
import Testing

@testable import Standfast

// SwiftUI shows no tree of the menu it builds, so what the view adds to the
// presentation's rows is pinned here, mostly from its source.

private let menuViewNow = Date(timeIntervalSince1970: 1_785_962_174)

private func menuViewSnapshot(_ name: String, _ display: DisplayState) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.acme-widget.\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
      agentName: name, scope: .repository(owner: "acme", name: "widget")),
    display: display, readAt: menuViewNow)
}

/// The rows a separator is drawn above, for the menu these snapshots emit.
@MainActor
private func rowsAfterASeparator(
  _ snapshots: [RunnerSnapshot], thermal: [String] = []
) -> [QuickMenuPresentation.Emission.Element] {
  let elements = QuickMenuPresentation.building(
    snapshots: snapshots, overview: .building(snapshots: snapshots, notice: nil),
    thermalLines: thermal, readAt: nil, now: menuViewNow
  ).emission.elements
  return elements.indices
    .filter { QuickMenuView.startsGroup(at: $0, in: elements) }
    .map { elements[$0] }
}

/// The text from `start` through `end`, or nothing when either is missing.
private func section(of source: String, from start: String, to end: String) -> Substring {
  guard let opened = source.range(of: start),
    let closed = source[opened.upperBound...].range(of: end)
  else { return "" }
  return source[opened.lowerBound..<closed.upperBound]
}

/// One `case` of the view's row switch, up to the next one.
private func rowCase(_ name: String) -> Substring {
  let rows = section(
    of: standfastSource("QuickMenuView.swift"), from: "private func row(",
    to: "private struct RunnerEchoMenu")
  guard let found = rows.range(of: "case .\(name):") else { return "" }
  let rest = rows[found.lowerBound...]
  return rest[..<(rest.dropFirst().range(of: "case .")?.lowerBound ?? rest.endIndex)]
}

private func occurrences(of needle: String, in source: String) -> Int {
  source.components(separatedBy: needle).count - 1
}

// MARK: - Separators

@Test @MainActor func aSeparatorFallsWhereOneKindOfRowGivesWayToAnother() {
  // Runners | thermal and freshness | Refresh, Open Standfast, Settings | Quit.
  #expect(
    rowsAfterASeparator(
      [
        menuViewSnapshot("build-mac", .resolved(.busy)),
        menuViewSnapshot("gl-docs", .resolved(.stopped)),
      ], thermal: ["This Mac is hot"])
      == [.text("This Mac is hot"), .refresh, .quit])
}

@Test @MainActor func aMenuWithNoRunnersDoesNotOpenOnASeparator() {
  #expect(rowsAfterASeparator([]) == [.refresh, .quit])
}

@Test func theSeparatorsAreTheViewsAndOnlyWhereTheGroupingAsks() {
  let source = standfastSource("QuickMenuView.swift")

  #expect(source.contains("if Self.startsGroup(at: index, in: elements) { Divider() }"))
  // Another, in a row or a submenu, would ignore the grouping.
  #expect(occurrences(of: "Divider()", in: source) == 1)
}

// MARK: - Icons

@Test func everyRunnerItemWearsItsStateSymbolAndNoOtherItemDoes() {
  let source = standfastSource("QuickMenuView.swift")
  let runnerLabel = section(
    of: source, from: "} label: {",
    to: ".accessibilityIdentifier(\"dev.standfast.quick-menu.runner\")")
  let operation = section(
    of: source, from: "Label(operation.title", to: "Text(operation.detail)")

  #expect(runnerLabel.contains("Label(runner.title, systemImage: runner.symbolName)"))
  #expect(runnerLabel.contains(".labelStyle(.titleAndIcon)"))
  // Icons go to a whole group or to none of it: not to the actions, and not to
  // the operation among the submenu's plain lines.
  #expect(occurrences(of: ".labelStyle(.titleAndIcon)", in: source) == 1)
  #expect(occurrences(of: "systemImage:", in: source) == 2)
  #expect(operation.contains(".labelStyle(.titleOnly)"))
}

@Test func theIconChangesNothingTheGateOrVoiceOverReads() {
  let source = standfastSource("QuickMenuView.swift")
  let runner = section(
    of: source, from: "} label: {", to: ".accessibilityValue(runner.longState)")

  #expect(runner.contains(".accessibilityIdentifier(\"dev.standfast.quick-menu.runner\")"))
  #expect(runner.contains(".accessibilityLabel(runner.title)"))
  // On the menu, not the label inside it, so the symbol adds nothing to them.
  #expect(runner.contains("}\n    .accessibilityIdentifier("))
  // The status lines and the four actions.
  #expect(occurrences(of: "\"dev.standfast.quick-menu.static\"", in: source) == 5)
}

// MARK: - Shortcuts and names

@Test func refreshSettingsAndQuitTakeTheirStandardKeys() {
  #expect(rowCase("refresh").contains(".keyboardShortcut(\"r\")"))
  #expect(rowCase("openSettings").contains(".keyboardShortcut(\",\")"))
  #expect(rowCase("quit").contains(".keyboardShortcut(\"q\")"))
  // Opening a window has no standard key to borrow.
  #expect(!rowCase("openControlCenter").contains(".keyboardShortcut("))
  #expect(
    occurrences(of: ".keyboardShortcut(", in: standfastSource("QuickMenuView.swift")) == 3)
}

@Test func theActionsKeepTheNamesTheGateFindsThemBy() throws {
  #expect(rowCase("refresh").contains("Button(L10n.refreshNow)"))
  #expect(rowCase("openControlCenter").contains("Button(L10n.controlCenter)"))
  #expect(rowCase("openSettings").contains("Button(L10n.settings)"))
  #expect(rowCase("quit").contains("Button(L10n.quit)"))

  // No ellipsis on the items that open a window: the strict gate finds each row
  // by its exact name, in both languages.
  for (language, names) in [
    ("en", ["Open Standfast", "Settings", "Quit"]),
    ("es", ["Abrir Standfast", "Ajustes", "Salir"]),
  ] {
    let path = try #require(
      L10n.resourceBundle?.path(
        forResource: "Localizable", ofType: "strings", inDirectory: nil,
        forLocalization: language))
    let catalogue = try #require(NSDictionary(contentsOfFile: path) as? [String: String])

    #expect(
      ["menu.controlCenter", "menu.settings", "menu.quit"].map { catalogue[$0] } == names,
      "\(language)")
  }
}
