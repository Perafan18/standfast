import SwiftUI

@main
struct StandfastApp: App {
  @StateObject private var fleet = RunnerFleetModel()
  @StateObject private var loginItem = LoginItem()
  @StateObject private var thermal = ThermalMonitor()

  var body: some Scene {
    MenuBarExtra {
      QuickMenuView(fleet: fleet, thermal: thermal)
    } label: {
      let display = FleetSummary.summarising(fleet.snapshots.map(\.display))
      Image(systemName: FleetSummary.symbolName(for: fleet.snapshots.map(\.display)))
        .accessibilityLabel(L10n.statusItemLabel)
        .accessibilityValue(FleetSummary.accessibilityValue(for: display))
    }

    Window(L10n.controlCenterTitle, id: "control-center") {
      ControlCenterView(fleet: fleet)
    }
    .defaultSize(width: 640, height: 720)

    Settings {
      SettingsView(
        loginItem: loginItem, notifications: fleet.notifications, sleep: fleet.sleep)
    }
  }
}
