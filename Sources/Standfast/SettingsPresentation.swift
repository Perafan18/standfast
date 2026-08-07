import Foundation

struct SettingsSectionPresentation: Equatable {
  let footer: String
  let notice: String?

  var supportingText: [String] {
    if let notice { [footer, notice] } else { [footer] }
  }
}

struct SettingsPresentation: Equatable {
  let notifications: SettingsSectionPresentation
  let power: SettingsSectionPresentation
  let startup: SettingsSectionPresentation
  let version: String

  init(
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
    version = Self.version(infoDictionary: infoDictionary)
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
