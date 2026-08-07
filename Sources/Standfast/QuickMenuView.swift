import AppKit
import SwiftUI

/// A bounded echo of the fleet. Every row comes from `QuickMenuPresentation`;
/// preferences and full operational controls live in their own scenes.
struct QuickMenuView: View {
  @ObservedObject var fleet: RunnerFleetModel
  @ObservedObject var thermal: ThermalMonitor

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
    case .runnerText(let runner):
      Text(runner.title)
    case .runnerMenu(let runner):
      RunnerEchoMenu(runner: runner, fleet: fleet)
    case .refresh:
      Button(L10n.refreshNow) { fleet.refresh() }
    case .openControlCenter:
      Button(L10n.controlCenter) {
        openWindow(id: "control-center")
        NSApplication.shared.activate()
      }
    case .openSettings:
      Button(L10n.settings) {
        openSettings()
        NSApplication.shared.activate()
      }
    case .quit:
      Button(L10n.quit) { NSApplication.shared.terminate(nil) }
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
  }
}
