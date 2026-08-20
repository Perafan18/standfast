import Foundation

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
  let github: GitHubSettingsPresentation
  /// Nil on a Mac with no gitlab-runner configured, which is most Macs: a
  /// token field for a provider with nothing on the machine is a question the
  /// user cannot act on.
  let gitLab: GitHubSettingsPresentation?
  let version: String

  init(
    githubState: GitHubAccessState = .absent, githubNotice: String? = nil,
    gitLabState: GitHubAccessState? = nil, gitLabNotice: String? = nil,
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
    github = GitHubSettingsPresentation(
      currentState: Self.currentState(githubState),
      footer: L10n.settingsGitHubFooter,
      notice: githubNotice,
      // Removal stays available when the Keychain would not answer: it is the
      // recovery from an item this app can no longer read, and withholding it
      // would leave the user hunting for the entry in Keychain Access.
      canRemove: githubState != .absent)
    gitLab = gitLabState.map { state in
      GitHubSettingsPresentation(
        currentState: Self.gitLabCurrentState(state),
        footer: L10n.settingsGitLabFooter,
        notice: gitLabNotice,
        canRemove: state != .absent)
    }
    version = Self.version(infoDictionary: infoDictionary)
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
  static let version = "dev.standfast.settings.version"
  static let githubToken = "dev.standfast.settings.github.token"
  static let githubSave = "dev.standfast.settings.github.save"
  static let githubRemove = "dev.standfast.settings.github.remove"
  static let gitlabToken = "dev.standfast.settings.gitlab.token"
  static let gitlabSave = "dev.standfast.settings.gitlab.save"
  static let gitlabRemove = "dev.standfast.settings.gitlab.remove"
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
