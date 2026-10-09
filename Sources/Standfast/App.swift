import RunnerKit
import SwiftUI

@main
struct StandfastApp: App {
  @StateObject private var fleet: RunnerFleetModel
  @StateObject private var loginItem = LoginItem()
  @StateObject private var github = GitHubAccess(unattended: .gitHub)
  @StateObject private var manualRunners = ManualRunnerDirectories()
  /// Applies the saved Dock preference at launch, before anybody opens
  /// Settings: `LSUIElement` decides how the process starts, and this decides
  /// whether it stays that way.
  @StateObject private var dock = DockVisibility()
  /// One card per GitLab instance this Mac's gitlab-runner reports to,
  /// re-read when Settings is shown. None on a Mac without it.
  @StateObject private var gitLabCards = GitLabInstanceCards(
    configFile: FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".gitlab-runner/config.toml"))
  @StateObject private var thermal = ThermalMonitor()
  @StateObject private var sceneActivation: SceneActivationCoordinator

  @MainActor
  init() {
    let windowRegistry = SceneWindowRegistry()
    _fleet = StateObject(
      wrappedValue: RunnerFleetModel(
        serviceConfirmation: ServiceAlertConfirmation(
          parentWindow:
            ServiceAlertConfirmation.controlCenterParentWindow(in: windowRegistry))))
    _sceneActivation = StateObject(
      wrappedValue:
        SceneActivationCoordinator.live(windowRegistry: windowRegistry))
  }

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
        github: github, gitLab: gitLabCards,
        manualRunners: manualRunners, dock: dock,
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
