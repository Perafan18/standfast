import AppKit
import SwiftUI

/// A bounded echo of the fleet. Every row comes from `QuickMenuPresentation`;
/// preferences and full operational controls live in their own scenes.
struct QuickMenuView: View {
  @ObservedObject var fleet: RunnerFleetModel
  @ObservedObject var thermal: ThermalMonitor
  let sceneActivation: SceneActivationCoordinator

  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    let thermalLines = ThermalNotice.lines(
      pressure: thermal.pressure, overrunning: fleet.isOverrunning)
    let presentation = fleet.quickMenuPresentation(thermalLines: thermalLines)
    let elements = presentation.emission.elements

    ForEach(elements.indices, id: \.self) { index in
      if Self.startsGroup(at: index, in: elements) { Divider() }
      row(elements[index])
    }
  }

  /// The runs a separator sets apart. Separators are drawn here and never
  /// emitted, so the emitted rows stay one to one with the named records the
  /// gate reads.
  enum RowGroup { case runners, status, actions, quit }

  static func group(_ element: QuickMenuPresentation.Emission.Element) -> RowGroup {
    switch element {
    case .runnerMenu: .runners
    case .text: .status
    case .refresh, .openControlCenter, .openSettings: .actions
    case .quit: .quit
    }
  }

  static func startsGroup(
    at index: Int, in elements: [QuickMenuPresentation.Emission.Element]
  ) -> Bool {
    index > 0 && group(elements[index]) != group(elements[index - 1])
  }

  @ViewBuilder
  private func row(_ element: QuickMenuPresentation.Emission.Element) -> some View {
    switch element {
    case .text(let line):
      Text(line)
        .accessibilityIdentifier("dev.standfast.quick-menu.static")
    case .runnerMenu(let runner):
      RunnerEchoMenu(runner: runner, fleet: fleet)
    case .refresh:
      // A status menu's key equivalents answer only while it is open, so this
      // never competes with the toolbar's ⌘R.
      Button(L10n.menuItemRefreshNow) { fleet.refresh() }
        .keyboardShortcut("r")
        .accessibilityIdentifier("dev.standfast.quick-menu.static")
    case .openControlCenter:
      Button(L10n.controlCenter) {
        sceneActivation.openAndActivate(.controlCenter) {
          openWindow(id: "control-center")
        }
      }
      .accessibilityIdentifier("dev.standfast.quick-menu.static")
    case .openSettings:
      Button(L10n.settings) {
        sceneActivation.openAndActivate(.settings) {
          openSettings()
        }
      }
      .keyboardShortcut(",")
      .accessibilityIdentifier("dev.standfast.quick-menu.static")
    case .quit:
      Button(L10n.quit) { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
        .accessibilityIdentifier("dev.standfast.quick-menu.static")
    }
  }

}

/// A runner echo with detail is one native menu element. Its secondary copy
/// and recovery action are children of this submenu and cannot expand the
/// menu's top-level height budget.
private struct RunnerEchoMenu: View {
  let runner: QuickMenuPresentation.RunnerEcho
  @ObservedObject var fleet: RunnerFleetModel

  var body: some View {
    Menu {
      Text(runner.longState)
      if let progress = runner.progress { Text(progress) }
      if let job = runner.currentJob {
        Text(job.context)
        Text(job.detail)
        Text(job.association)
        ForEach(job.links) { link in
          Link(link.menuTitle, destination: link.url)
        }
      }
      if let operation = runner.operation {
        // Icons belong to a whole group or to none of it, and none of this
        // submenu's other lines has one.
        Label(operation.title, systemImage: operation.symbolName)
          .labelStyle(.titleOnly)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(operation.title)
          .accessibilityValue(operation.detail)
        Text(operation.detail)
          .accessibilityHidden(true)
      }
      if runner.canStart {
        Button(L10n.start) {
          fleet.perform(.start, onRunnerID: runner.id)
        }
      }
    } label: {
      // The symbol repeats the state for the eye. The item's name stays the
      // title alone, which the gate reads as `name · state`.
      Label(runner.title, systemImage: runner.symbolName)
        .labelStyle(.titleAndIcon)
    }
    .accessibilityIdentifier("dev.standfast.quick-menu.runner")
    .accessibilityLabel(runner.title)
    .accessibilityValue(runner.longState)
  }
}
