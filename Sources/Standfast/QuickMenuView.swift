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

    ForEach(presentation.items.indices, id: \.self) { index in
      row(presentation.items[index])
    }
  }

  @ViewBuilder
  private func row(_ item: QuickMenuPresentation.Item) -> some View {
    switch item {
    case .fleet(let line), .discovery(let line), .thermal(let line),
      .freshness(let line):
      Text(line)
    case .runner(let runner):
      Text(runner.title)
      if let progress = runner.progress { Text(progress) }
      if let operation = runner.operation {
        Label(operation.title, systemImage: operation.symbolName)
          .accessibilityElement(children: .combine)
          .accessibilityLabel(operation.title)
          .accessibilityValue(operation.detail)
        Text(operation.detail)
      }
      if runner.canStart {
        Button(L10n.start) {
          fleet.perform(.start, onRunnerID: runner.id)
        }
      }
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
