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
      row(elements[index])
    }
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
      Button(L10n.refreshNow) { fleet.refresh() }
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
      .accessibilityIdentifier("dev.standfast.quick-menu.static")
    case .quit:
      Button(L10n.quit) { NSApplication.shared.terminate(nil) }
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
      if let operation = runner.operation {
        Label(operation.title, systemImage: operation.symbolName)
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
      Text(runner.title)
    }
    .accessibilityIdentifier("dev.standfast.quick-menu.runner")
    .accessibilityLabel(runner.title)
    .accessibilityValue(runner.longState)
  }
}
