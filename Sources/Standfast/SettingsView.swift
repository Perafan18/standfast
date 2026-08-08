import AppKit
import SwiftUI

/// The only preference surface. Every value is owned by the same long-lived
/// objects the fleet and menu observe.
struct SettingsView: View {
  @ObservedObject var loginItem: LoginItem
  @ObservedObject var notifications: NotificationSettings
  @ObservedObject var sleep: SleepGuard
  let infoDictionary: [String: Any]?

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private var palette: StandfastPalette {
    StandfastTheme.palette(
      for: colorScheme == .dark ? .dark : .light,
      increasedContrast: colorSchemeContrast == .increased,
      reduceTransparency: reduceTransparency)
  }

  var body: some View {
    let presentation = SettingsPresentation(
      notificationNotice: notifications.notice,
      loginItemNotice: loginItem.notice,
      infoDictionary: infoDictionary)

    ScrollView {
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.standard) {
        productHeader

        settingsCard(
          title: L10n.settingsNotifications,
          systemImage: "bell.badge.fill"
        ) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(NotificationKind.allCases, id: \.self) { kind in
              notificationToggle(kind)
              if kind != NotificationKind.allCases.last { separator }
            }
          }
          supportingText(presentation.notifications)
        }

        settingsCard(
          title: L10n.settingsPower,
          systemImage: "bolt.fill"
        ) {
          settingsToggle(
            title: L10n.preventSleep,
            systemImage: "moon.zzz",
            isOn: Binding(
              get: { sleep.isEnabled },
              set: { sleep.setEnabled($0) })
          )
          .accessibilityIdentifier(SettingsAccessibility.powerPreventSleep)
          supportingText(presentation.power)
        }

        settingsCard(
          title: L10n.settingsStartup,
          systemImage: "power"
        ) {
          settingsToggle(
            title: L10n.openAtLogin,
            systemImage: "arrow.clockwise",
            isOn: Binding(
              get: { loginItem.isEnabled },
              set: { loginItem.setEnabled($0) })
          )
          .accessibilityIdentifier(SettingsAccessibility.startupOpenAtLogin)
          supportingText(presentation.startup)
        }

        Text(presentation.version)
          .font(.caption)
          .foregroundStyle(palette.textSecondary.color)
          .frame(maxWidth: .infinity, alignment: .center)
          .accessibilityIdentifier(SettingsAccessibility.version)
      }
      .padding(StandfastTheme.Spacing.large)
    }
    .frame(
      minWidth: StandfastTheme.settingsMinimumWidth,
      idealWidth: StandfastTheme.settingsIdealWidth,
      maxWidth: StandfastTheme.settingsMaximumWidth
    )
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var productHeader: some View {
    HStack(spacing: StandfastTheme.Spacing.compact) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
      Text(L10n.statusItemLabel)
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.textPrimary.color)
    }
    .accessibilityElement(children: .combine)
  }

  private func notificationToggle(_ kind: NotificationKind) -> some View {
    settingsToggle(
      title: kind.menuLabel,
      systemImage: notificationSymbol(for: kind),
      isOn: Binding(
        get: { notifications.isEnabled(kind) },
        set: { notifications.setEnabled(kind, $0) })
    )
    .accessibilityIdentifier(SettingsAccessibility.notification(kind))
  }

  private func notificationSymbol(for kind: NotificationKind) -> String {
    switch kind {
    case .jobFailed: "exclamationmark.circle"
    case .runnerDisconnected: "antenna.radiowaves.left.and.right.slash"
    case .runnerStopped: "stop.circle"
    }
  }

  private func settingsToggle(
    title: String, systemImage: String, isOn: Binding<Bool>
  ) -> some View {
    // The row owns the full card width so every switch lands on the same
    // trailing edge. Left to its intrinsic width, each row hugs its own label
    // and the section reads as a ragged, centred stack instead of a list.
    Toggle(isOn: isOn) {
      Label(title, systemImage: systemImage)
        .foregroundStyle(palette.textPrimary.color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .toggleStyle(.switch)
    .frame(maxWidth: .infinity, minHeight: 44)
    .contentShape(Rectangle())
  }

  private func settingsCard<Content: View>(
    title: String, systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
      Label(title, systemImage: systemImage)
        .font(.headline)
        .foregroundStyle(palette.textPrimary.color)
      content()
    }
    .padding(StandfastTheme.Spacing.standard)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      palette.surface.color,
      in: RoundedRectangle(
        cornerRadius: StandfastTheme.Radius.surface, style: .continuous)
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: StandfastTheme.Radius.surface, style: .continuous
      )
      .stroke(
        palette.structuralBorder.color,
        lineWidth: StandfastTheme.Stroke.structural)
    }
  }

  private func supportingText(
    _ presentation: SettingsSectionPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.small) {
      Text(presentation.footer)
        .font(.caption)
        .foregroundStyle(palette.textSecondary.color)
      if let notice = presentation.notice {
        Label(notice, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(palette.attentionForeground.color)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var separator: some View {
    Rectangle()
      .fill(palette.structuralBorder.color)
      .frame(height: StandfastTheme.Stroke.separator)
  }
}
