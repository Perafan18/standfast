import SwiftUI

@main
struct StandfastApp: App {
  @StateObject private var fleet = RunnerFleetModel(
    serviceConfirmation: ServiceAlertConfirmation())
  @StateObject private var loginItem = LoginItem()
  @StateObject private var thermal = ThermalMonitor()
  @StateObject private var sceneActivation = SceneActivationCoordinator.live()

  var body: some Scene {
    MenuBarExtra {
      QuickMenuView(
        fleet: fleet,
        thermal: thermal,
        sceneActivation: sceneActivation)
    } label: {
      let display = FleetSummary.summarising(fleet.snapshots.map(\.display))
      Image(systemName: FleetSummary.symbolName(for: fleet.snapshots.map(\.display)))
        .accessibilityLabel(L10n.statusItemLabel)
        .accessibilityValue(FleetSummary.accessibilityValue(for: display))
    }

    Window(L10n.controlCenterTitle, id: "control-center") {
      ControlCenterView(fleet: fleet)
        .background(
          SceneWindowProbe(
            target: .controlCenter,
            registry: sceneActivation.windowRegistry))
    }
    .defaultSize(
      width: StandfastTheme.controlCenterDefaultWidth,
      height: StandfastTheme.controlCenterDefaultHeight)

    Settings {
      SettingsView(
        loginItem: loginItem, notifications: fleet.notifications, sleep: fleet.sleep
      )
      .background(
        SceneWindowProbe(
          target: .settings,
          registry: sceneActivation.windowRegistry))
    }
  }
}
