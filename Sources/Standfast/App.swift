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
      let overview = fleet.overview
      Image(systemName: overview.symbolName)
        .accessibilityLabel(L10n.statusItemLabel)
        .accessibilityValue(overview.summary)
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
        loginItem: loginItem, notifications: fleet.notifications, sleep: fleet.sleep,
        infoDictionary: Bundle.main.infoDictionary
      )
      .background(
        SceneWindowProbe(
          target: .settings,
          registry: sceneActivation.windowRegistry))
    }
    .defaultSize(
      width: StandfastTheme.settingsIdealWidth,
      height: StandfastTheme.settingsDefaultHeight)
  }
}
