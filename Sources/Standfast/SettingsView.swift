import AppKit
import SwiftUI

/// The only preference surface. Every value is owned by the same long-lived
/// objects the fleet and menu observe.
struct SettingsView: View {
  @ObservedObject var loginItem: LoginItem
  @ObservedObject var notifications: NotificationSettings
  @ObservedObject var sleep: SleepGuard
  @ObservedObject var github: GitHubAccess
  /// The GitLab token, over its own Keychain account. Its card only appears
  /// when this Mac has gitlab-runner configured; see `showsGitLab`.
  @ObservedObject var gitLab: GitHubAccess
  /// Decided at launch from whether `config.toml` exists. Static per run on
  /// purpose: installing gitlab-runner mid-session is rare, and a Settings
  /// pane that reads the disk on every body pass is not the price for it.
  let showsGitLab: Bool
  @ObservedObject var manualRunners: ManualRunnerDirectories
  /// Whether this Mac shows Standfast in the Dock. `LSUIElement` starts the
  /// process without a tile; this is what can give it one afterwards.
  @ObservedObject var dock: DockVisibility
  let infoDictionary: [String: Any]?

  /// What is in the field right now, and never where the stored token lives.
  /// It is emptied the moment Save hands it over, so the secret does not sit
  /// in a view that a screen recording or a screenshot would capture.
  @State private var draftToken = ""
  @State private var draftGitLabToken = ""

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
      githubState: github.state, githubNotice: github.notice,
      gitLabState: showsGitLab ? gitLab.state : nil, gitLabNotice: gitLab.notice,
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
          title: L10n.settingsRunners,
          systemImage: "folder.badge.plus"
        ) {
          handStartedRunners
        }

        settingsCard(
          title: L10n.settingsGitHub,
          systemImage: "key.fill"
        ) {
          githubAccess(presentation.github)
        }

        if let gitLabPresentation = presentation.gitLab {
          settingsCard(
            title: L10n.settingsGitLab,
            systemImage: "key.fill"
          ) {
            tokenAccess(
              gitLabPresentation, draft: $draftGitLabToken, access: gitLab,
              placeholder: L10n.settingsGitLabPlaceholder,
              identifiers: (
                token: SettingsAccessibility.gitlabToken,
                save: SettingsAccessibility.gitlabSave,
                remove: SettingsAccessibility.gitlabRemove
              ))
          }
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

        settingsCard(
          title: L10n.settingsAppearance,
          systemImage: "dock.rectangle"
        ) {
          settingsToggle(
            title: L10n.settingsShowInDock,
            systemImage: "macwindow",
            isOn: Binding(
              get: { dock.isVisible },
              set: { dock.setVisible($0) })
          )
          .accessibilityIdentifier(SettingsAccessibility.appearanceShowInDock)
          supportingText(presentation.appearance)
        }

        Text(presentation.version)
          .font(StandfastTheme.Typography.micro)
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
      // UI-028. The icon is a beacon whose metal measures about 2.46:1 against
      // this surface, so at 48 pt only its glow survived and the rest read as a
      // smudge. A well of canvas behind it gives the dark half something to sit
      // against; the artwork is untouched.
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 48, height: 48)
        .padding(StandfastTheme.Spacing.small)
        .background(
          palette.canvas.color,
          in: RoundedRectangle(
            cornerRadius: StandfastTheme.Radius.compact, style: .continuous)
        )
        .accessibilityHidden(true)
      Text(L10n.statusItemLabel)
        .font(StandfastTheme.Typography.display)
        .foregroundStyle(palette.textPrimary.color)
    }
    .accessibilityElement(children: .combine)
  }

  private var handStartedRunners: some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
      if manualRunners.directories.isEmpty {
        Text(L10n.settingsRunnersNone)
          .font(StandfastTheme.Typography.secondary)
          .foregroundStyle(palette.textPrimary.color)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ForEach(manualRunners.directories, id: \.path) { directory in
          HStack(spacing: StandfastTheme.Spacing.compact) {
            // The last component reads as the runner; the full path is what
            // disambiguates two with the same name, so it stays available to
            // anything reading this row rather than only to a wide window.
            Text(directory.lastPathComponent)
              .font(StandfastTheme.Typography.secondary)
              .foregroundStyle(palette.textPrimary.color)
              .frame(maxWidth: .infinity, alignment: .leading)
              .help(directory.path)
            Button {
              manualRunners.remove(directory)
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.settingsRunnersRemove(directory.lastPathComponent))
          }
          .frame(maxWidth: .infinity, minHeight: 28)
          .accessibilityIdentifier(SettingsAccessibility.runnerRow(directory.path))
        }
      }

      Button(L10n.settingsRunnersAdd) { chooseRunnerFolder() }
        .accessibilityIdentifier(SettingsAccessibility.runnersAdd)

      supportingLines(footer: L10n.settingsRunnersFooter, notice: nil)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// A folder chosen, never a path typed. The panel is also the only thing that
  /// can tell this app it may read somewhere it was not launched from.
  private func chooseRunnerFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = L10n.settingsRunnersAdd
    guard panel.runModal() == .OK, let chosen = panel.url else { return }
    manualRunners.add(chosen)
  }

  private func githubAccess(
    _ presentation: GitHubSettingsPresentation
  ) -> some View {
    tokenAccess(
      presentation, draft: $draftToken, access: github,
      placeholder: L10n.settingsGitHubPlaceholder,
      identifiers: (
        token: SettingsAccessibility.githubToken,
        save: SettingsAccessibility.githubSave,
        remove: SettingsAccessibility.githubRemove
      ))
  }

  /// One shape for both providers' token cards, because they are one shape:
  /// what differs is which Keychain account is behind them and which words
  /// describe it, and both arrive as parameters.
  private func tokenAccess(
    _ presentation: GitHubSettingsPresentation, draft: Binding<String>,
    access: GitHubAccess, placeholder: String,
    identifiers: (token: String, save: String, remove: String)
  ) -> some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
      Text(presentation.currentState)
        .font(StandfastTheme.Typography.secondary)
        .foregroundStyle(palette.textPrimary.color)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: StandfastTheme.Spacing.compact) {
        // Secure, so the token is never on screen even while it is being
        // pasted — this window is the one people screenshot when they ask for
        // help with it.
        SecureField(placeholder, text: draft)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(identifiers.token)
        Button(L10n.settingsGitHubSave) {
          access.save(draft.wrappedValue)
          draft.wrappedValue = ""
        }
        .disabled(
          draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .accessibilityIdentifier(identifiers.save)
      }

      if presentation.canRemove {
        Button(L10n.settingsGitHubRemove) { access.remove() }
          .accessibilityIdentifier(identifiers.remove)
      }

      supportingLines(footer: presentation.footer, notice: presentation.notice)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
    // 44 is the iPhone touch target, and this theme rejected it once already:
    // `controlMinimumHeight` is 28 because a pointer is not a thumb. A settings
    // row still wants more air than a button, hence 32 rather than 28 — but not
    // the height of a control on a phone.
    .frame(maxWidth: .infinity, minHeight: 32)
    .contentShape(Rectangle())
  }

  private func settingsCard<Content: View>(
    title: String, systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
      Label(title, systemImage: systemImage)
        .font(StandfastTheme.Typography.title)
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
    supportingLines(footer: presentation.footer, notice: presentation.notice)
  }

  private func supportingLines(footer: String, notice: String?) -> some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.small) {
      Text(footer)
        .font(StandfastTheme.Typography.micro)
        .foregroundStyle(palette.textSecondary.color)
      if let notice {
        Label(notice, systemImage: "exclamationmark.triangle.fill")
          .font(StandfastTheme.Typography.micro)
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
