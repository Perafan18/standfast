import SwiftUI

/// The only preference surface. Every value is owned by the same long-lived
/// objects the fleet and menu observe.
struct SettingsView: View {
  @ObservedObject var loginItem: LoginItem
  @ObservedObject var notifications: NotificationSettings
  @ObservedObject var sleep: SleepGuard

  var body: some View {
    Form {
      Section(L10n.settingsNotifications) {
        ForEach(NotificationKind.allCases, id: \.self) { kind in
          Toggle(
            kind.menuLabel,
            isOn: Binding(
              get: { notifications.isEnabled(kind) },
              set: { notifications.setEnabled(kind, $0) }))
        }
        if let notice = notifications.notice { Text(notice) }
      }

      Section(L10n.settingsPower) {
        Toggle(
          L10n.preventSleep,
          isOn: Binding(
            get: { sleep.isEnabled }, set: { sleep.setEnabled($0) }))
        if sleep.isEnabled { Text(L10n.preventSleepLidNotice) }
      }

      Section(L10n.settingsStartup) {
        Toggle(
          L10n.openAtLogin,
          isOn: Binding(
            get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
        if let notice = loginItem.notice { Text(notice) }
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 440)
  }
}
