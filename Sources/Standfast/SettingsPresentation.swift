import Foundation
import RunnerKit

struct SettingsSectionPresentation: Equatable {
  let footer: String
  let notice: String?

  var supportingText: [String] {
    if let notice { [footer, notice] } else { [footer] }
  }
}

/// What Settings says about this Mac's own GitHub credential.
///
/// It says whether one exists and never what it is. There is no field here for
/// the token itself, and no accessor for it anywhere above `GitHubAccess`: a
/// live GitHub credential rendered on screen is one screenshot away from being
/// published, and nothing about this surface needs to read it.
struct GitHubSettingsPresentation: Equatable {
  let currentState: String
  let footer: String
  let notice: String?
  /// False where a token would never be sent, so nothing invites one.
  let canSave: Bool
  /// False when there is nothing stored. A Remove button over an empty
  /// Keychain is a question the user has to answer about their own machine.
  let canRemove: Bool

  var supportingText: [String] {
    if let notice { [footer, notice] } else { [footer] }
  }
}

struct SettingsPresentation: Equatable {
  let notifications: SettingsSectionPresentation
  let power: SettingsSectionPresentation
  let startup: SettingsSectionPresentation
  /// Where the app is willing to be seen. `LSUIElement` cannot be a
  /// preference — it is read once at launch — so the switch it stands for
  /// lives here; see `DockVisibility`.
  let appearance: SettingsSectionPresentation
  let github: GitHubSettingsPresentation
  let version: String

  init(
    githubState: GitHubAccessState = .absent, githubNotice: String? = nil,
    notificationNotice: String?, loginItemNotice: String?,
    infoDictionary: [String: Any]?
  ) {
    notifications = SettingsSectionPresentation(
      footer: L10n.settingsNotificationsFooter,
      notice: notificationNotice)
    power = SettingsSectionPresentation(
      footer: L10n.settingsPowerFooter,
      notice: nil)
    startup = SettingsSectionPresentation(
      footer: L10n.settingsStartupFooter,
      notice: loginItemNotice)
    appearance = SettingsSectionPresentation(
      footer: L10n.settingsAppearanceFooter,
      notice: nil)
    github = GitHubSettingsPresentation(
      currentState: Self.currentState(githubState),
      footer: L10n.settingsGitHubFooter,
      notice: githubNotice,
      canSave: true,
      // Removal stays available when the Keychain would not answer: it is the
      // recovery from an item this app can no longer read, and withholding it
      // would leave the user hunting for the entry in Keychain Access.
      canRemove: githubState != .absent)
    version = Self.version(infoDictionary: infoDictionary)
  }

  /// One GitLab instance's card. There is one per instance, so it is asked for
  /// per instance rather than built with the rest.
  static func gitLab(
    _ state: GitHubAccessState, notice: String?, isServedOverHTTPS: Bool
  ) -> GitHubSettingsPresentation {
    GitHubSettingsPresentation(
      // The stored and absent lines both describe an instance a token would
      // reach, and the client sends none over http.
      currentState: isServedOverHTTPS
        ? gitLabCurrentState(state) : L10n.settingsGitLabInsecure,
      footer: L10n.settingsGitLabFooter,
      notice: notice,
      canSave: isServedOverHTTPS,
      // Still offered over http: a token saved before Standfast stopped
      // asking there would otherwise have to be found in Keychain Access.
      canRemove: state != .absent)
  }

  private static func gitLabCurrentState(_ state: GitHubAccessState) -> String {
    switch state {
    case .stored: L10n.settingsGitLabStored
    case .absent: L10n.settingsGitLabAbsent
    // The Keychain sentence names no provider, so both cards share it.
    case .unreadable: L10n.settingsGitHubUnreadable
    }
  }

  private static func currentState(_ state: GitHubAccessState) -> String {
    switch state {
    case .stored: L10n.settingsGitHubStored
    case .absent: L10n.settingsGitHubAbsent
    case .unreadable: L10n.settingsGitHubUnreadable
    }
  }

  static func version(infoDictionary: [String: Any]?) -> String {
    let shortVersion = string(
      for: "CFBundleShortVersionString", in: infoDictionary)
    let build = string(for: "CFBundleVersion", in: infoDictionary)
    let suffix =
      switch (shortVersion, build) {
      case let (.some(shortVersion), .some(build)):
        " \(shortVersion) (\(build))"
      case let (.some(shortVersion), .none):
        " \(shortVersion)"
      case let (.none, .some(build)):
        " (\(build))"
      case (.none, .none):
        ""
      }
    return L10n.settingsVersion(suffix)
  }

  private static func string(
    for key: String, in infoDictionary: [String: Any]?
  ) -> String? {
    guard let raw = infoDictionary?[key] as? String else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

enum SettingsAccessibility {
  static let powerPreventSleep = "dev.standfast.settings.power.prevent-sleep"
  static let startupOpenAtLogin = "dev.standfast.settings.startup.open-at-login"
  static let appearanceShowInDock = "dev.standfast.settings.appearance.show-in-dock"
  static let version = "dev.standfast.settings.version"
  static let githubToken = "dev.standfast.settings.github.token"
  static let githubSave = "dev.standfast.settings.github.save"
  static let githubRemove = "dev.standfast.settings.github.remove"
  static let runnersAdd = "dev.standfast.settings.runners.add"

  /// One per row, so a probe can name the folder it means.
  ///
  /// The path with its separators flattened rather than hashed: these appear in
  /// a manual accessibility matrix somebody reads, and an identifier they can
  /// match to a folder by eye is worth more here than a short one.
  static func runnerRow(_ path: String) -> String {
    "dev.standfast.settings.runners.row"
      + path.replacingOccurrences(of: "/", with: ".")
  }

  /// One set per GitLab card, named by the instance it holds a token for.
  static func gitlab(
    _ instance: GitLabInstance
  ) -> (token: String, save: String, remove: String) {
    let card = "dev.standfast.settings.gitlab." + instance.name
    return (token: card + ".token", save: card + ".save", remove: card + ".remove")
  }

  static func notification(_ kind: NotificationKind) -> String {
    switch kind {
    case .jobFailed:
      "dev.standfast.settings.notifications.job-failed"
    case .runnerDisconnected:
      "dev.standfast.settings.notifications.disconnected"
    case .runnerStopped:
      "dev.standfast.settings.notifications.stopped"
    }
  }
}
