import RunnerKit
import SwiftUI

@main
struct StandfastApp: App {
  @StateObject private var fleet: RunnerFleetModel
  @StateObject private var loginItem = LoginItem()
  @StateObject private var github = GitHubAccess()
  @StateObject private var gitLabAccess = GitHubAccess(
    store: KeychainTokenStore(account: GitLabAPIClient.keychainAccount))
  @StateObject private var manualRunners = ManualRunnerDirectories()
  /// Applies the saved Dock preference at launch, before anybody opens
  /// Settings: `LSUIElement` decides how the process starts, and this decides
  /// whether it stays that way.
  @StateObject private var dock = DockVisibility()
  /// Whether this Mac has gitlab-runner configured, decided at launch. The
  /// Settings card for a GitLab token only exists where it can matter.
  private let showsGitLab = FileManager.default.fileExists(
    atPath: FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".gitlab-runner/config.toml").path)
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
        github: github, gitLab: gitLabAccess, showsGitLab: showsGitLab,
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
