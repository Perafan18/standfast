import AppKit
import RunnerKit
import SwiftUI

/// The only preference surface. Every value is owned by the same long-lived
/// objects the fleet and menu observe.
struct SettingsView: View {
  @ObservedObject var loginItem: LoginItem
  @ObservedObject var notifications: NotificationSettings
  let sleep: SleepGuard
  @ObservedObject var github: GitHubAccess
  /// One token section per GitLab instance, each over its own Keychain
  /// account, re-read when Settings is shown rather than on every body pass.
  let gitLab: GitLabInstanceCards
  let manualRunners: ManualRunnerDirectories
  /// Whether this Mac shows Standfast in the Dock. `LSUIElement` starts the
  /// process without a tile; this is what can give it one afterwards.
  let dock: DockVisibility
  let infoDictionary: [String: Any]?

  /// Not remembered across launches, so the first opening is on General, which
  /// is the one the strict gate reads. A `TabView` keeps only the selected pane
  /// in the accessibility tree, and every identifier it reads lives on General.
  @State private var pane: SettingsPane = .general

  var body: some View {
    let presentation = SettingsPresentation(
      githubState: github.state, githubNotice: github.notice,
      notificationNotice: notifications.notice,
      loginItemNotice: loginItem.notice,
      infoDictionary: infoDictionary)

    TabView(selection: $pane) {
      GeneralSettingsPane(
        presentation: presentation, notifications: notifications, sleep: sleep,
        loginItem: loginItem, dock: dock
      )
      .tabItem { Label(L10n.settingsTabGeneral, systemImage: "gearshape") }
      .tag(SettingsPane.general)

      RunnersSettingsPane(manualRunners: manualRunners)
        .tabItem { Label(L10n.settingsTabRunners, systemImage: "folder") }
        .tag(SettingsPane.runners)

      AccountsSettingsPane(
        presentation: presentation.github, github: github, gitLab: gitLab
      )
      .tabItem { Label(L10n.settingsTabAccounts, systemImage: "person.crop.circle") }
      .tag(SettingsPane.accounts)
    }
    // Reopening Settings can reuse this view rather than build a new one, and
    // leaving System Settings, where these answers change, reactivates the app.
    .onAppear { rereadWhatMacOSDecides() }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification)
    ) { _ in rereadWhatMacOSDecides() }
  }

  private func rereadWhatMacOSDecides() {
    loginItem.refresh()
    notifications.refreshAuthorizationIfEnabled()
    gitLab.reload()
  }
}

private enum SettingsPane: Hashable {
  case general, runners, accounts
}

/// Every switch in the app, and the version. Its height is measured so nothing
/// scrolls: a grouped form is a list, and a row scrolled out of sight can take
/// the gate's identifier out of the accessibility tree. Only a display too
/// short for it makes the form scroll, which beats a switch below its edge.
struct GeneralSettingsPane: View {
  let presentation: SettingsPresentation
  @ObservedObject var notifications: NotificationSettings
  @ObservedObject var sleep: SleepGuard
  @ObservedObject var loginItem: LoginItem
  @ObservedObject var dock: DockVisibility

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          ForEach(NotificationKind.allCases, id: \.self) { kind in
            settingsToggle(
              kind.menuLabel,
              isOn: Binding(
                get: { notifications.isEnabled(kind) },
                set: { notifications.setEnabled(kind, $0) })
            )
            .accessibilityIdentifier(SettingsAccessibility.notification(kind))
          }
        } header: {
          Text(L10n.settingsNotifications)
        } footer: {
          supportingText(presentation.notifications)
        }

        Section {
          settingsToggle(
            L10n.preventSleep,
            isOn: Binding(
              get: { sleep.isEnabled },
              set: { sleep.setEnabled($0) })
          )
          .accessibilityIdentifier(SettingsAccessibility.powerPreventSleep)
        } header: {
          Text(L10n.settingsPower)
        } footer: {
          supportingText(presentation.power)
        }

        Section {
          settingsToggle(
            L10n.openAtLogin,
            isOn: Binding(
              get: { loginItem.isEnabled },
              set: { loginItem.setEnabled($0) })
          )
          .accessibilityIdentifier(SettingsAccessibility.startupOpenAtLogin)
        } header: {
          Text(L10n.settingsStartup)
        } footer: {
          supportingText(presentation.startup)
        }

        Section {
          settingsToggle(
            L10n.settingsShowInDock,
            isOn: Binding(
              get: { dock.isVisible },
              set: { dock.setVisible($0) })
          )
          .accessibilityIdentifier(SettingsAccessibility.appearanceShowInDock)
        } header: {
          Text(L10n.settingsAppearance)
        } footer: {
          supportingText(presentation.appearance)
        }
      }
      .formStyle(.grouped)

      // Under the form rather than in a section of its own: a section with no
      // rows still draws an empty box.
      HStack(spacing: 8) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 32, height: 32)
          .accessibilityHidden(true)
        Text(presentation.version)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier(SettingsAccessibility.version)
      }
      .padding(.bottom)
    }
    .settingsPaneFrame(height: StandfastTheme.settingsGeneralHeight)
  }

  private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
      .toggleStyle(.switch)
      .controlSize(.mini)
  }

  private func supportingText(
    _ presentation: SettingsSectionPresentation
  ) -> some View {
    SettingsFooter(footer: presentation.footer, notice: presentation.notice)
  }
}

/// The runners nothing announces: started with `./run.sh`, so found only
/// because somebody pointed Settings at their folders.
struct RunnersSettingsPane: View {
  @ObservedObject var manualRunners: ManualRunnerDirectories

  var body: some View {
    Form {
      Section {
        if manualRunners.directories.isEmpty {
          Text(L10n.settingsRunnersNone)
            .foregroundStyle(.secondary)
        } else {
          ForEach(manualRunners.directories, id: \.path) { directory in
            LabeledContent {
              Button(role: .destructive) {
                manualRunners.remove(directory)
              } label: {
                Image(systemName: "minus.circle.fill")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel(L10n.settingsRunnersRemove(directory.lastPathComponent))
            } label: {
              // The last component reads as the runner; the full path is what
              // tells two with the same name apart.
              Label(directory.lastPathComponent, systemImage: "folder")
              Text(directory.path)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(SettingsAccessibility.runnerRow(directory.path))
          }
        }

        Button(L10n.settingsRunnersAdd) { chooseRunnerFolder() }
          .accessibilityIdentifier(SettingsAccessibility.runnersAdd)
      } header: {
        Text(L10n.settingsRunners)
      } footer: {
        SettingsFooter(footer: L10n.settingsRunnersFooter, notice: nil)
      }
    }
    .formStyle(.grouped)
    .settingsPaneFrame(
      height: StandfastTheme.settingsRunnersHeight(
        folders: manualRunners.directories.count))
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
}

/// This Mac's own tokens, one section per provider account: whether one is
/// stored, and the way to replace or remove it, never the token itself.
struct AccountsSettingsPane: View {
  let presentation: GitHubSettingsPresentation
  let github: GitHubAccess
  @ObservedObject var gitLab: GitLabInstanceCards

  /// What is in the field right now, never the stored token. Save empties it
  /// at once, so the secret does not sit in a view a screen recording or a
  /// screenshot would capture.
  @State private var draftToken = ""
  @State private var draftGitLabTokens: [String: String] = [:]

  var body: some View {
    Form {
      tokenSection(
        presentation, draft: $draftToken, access: github,
        placeholder: L10n.settingsGitHubPlaceholder,
        identifiers: (
          token: SettingsAccessibility.githubToken,
          save: SettingsAccessibility.githubSave,
          remove: SettingsAccessibility.githubRemove
        )
      ) {
        Text(L10n.settingsGitHub)
      }

      ForEach(gitLab.cards) { entry in
        ObservingAccess(access: entry.access) { access in
          tokenSection(
            SettingsPresentation.gitLab(
              access.state, notice: access.notice,
              isServedOverHTTPS: entry.instance.isServedOverHTTPS),
            draft: gitLabDraft(for: entry.instance), access: access,
            placeholder: L10n.settingsGitLabPlaceholder,
            identifiers: SettingsAccessibility.gitlab(entry.instance)
          ) {
            // One Mac can report to more than one instance, and each holds a
            // token of its own.
            VStack(alignment: .leading, spacing: 2) {
              Text(L10n.settingsGitLab)
              Text(entry.instance.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .settingsPaneFrame(
      height: StandfastTheme.settingsAccountsHeight(gitLabInstances: gitLab.cards.count))
  }

  private func gitLabDraft(for instance: GitLabInstance) -> Binding<String> {
    Binding(
      get: { draftGitLabTokens[instance.name, default: ""] },
      set: { draftGitLabTokens[instance.name] = $0 })
  }

  /// One shape for both providers: only the Keychain account behind it and the
  /// words describing it differ, and both arrive as parameters. Save and Remove
  /// are independent: over http a stored token can be removed but none saved.
  private func tokenSection<Header: View>(
    _ presentation: GitHubSettingsPresentation, draft: Binding<String>,
    access: GitHubAccess, placeholder: String,
    identifiers: (token: String, save: String, remove: String),
    @ViewBuilder header: () -> Header
  ) -> some View {
    Section {
      LabeledContent(L10n.controlCenterStatus, value: presentation.currentState)

      if presentation.canSave {
        HStack {
          // Secure, so the token is never on screen, even mid-paste: people
          // screenshot this window when asking for help. Labelled, because a
          // grouped form draws fields borderless, and with no label the prompt
          // reads as one.
          SecureField(text: draft, prompt: Text(placeholder)) {
            Text(L10n.settingsToken)
          }
          .accessibilityIdentifier(identifiers.token)
          // Return in the field rather than a default button: with a GitLab
          // instance there is more than one Save in this pane, and a window
          // has one default button.
          .onSubmit { save(draft, to: access) }
          Button(L10n.settingsGitHubSave) { save(draft, to: access) }
            .disabled(
              draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier(identifiers.save)
        }
      }

      if presentation.canRemove {
        Button(L10n.settingsGitHubRemove, role: .destructive) { access.remove() }
          .accessibilityIdentifier(identifiers.remove)
      }
    } header: {
      header()
    } footer: {
      SettingsFooter(footer: presentation.footer, notice: presentation.notice)
    }
  }

  private func save(_ draft: Binding<String>, to access: GitHubAccess) {
    access.save(draft.wrappedValue)
    draft.wrappedValue = ""
  }
}

extension View {
  /// One width on every pane, and the pane's measured height as far as the
  /// display Settings opens on allows. Under `.contentSize` a form with no
  /// height collapses.
  fileprivate func settingsPaneFrame(height: CGFloat) -> some View {
    frame(
      width: StandfastTheme.settingsPaneWidth,
      height: StandfastTheme.settingsPaneHeight(
        height, screenHeight: NSScreen.main?.visibleFrame.height))
  }
}

/// A section's permanent explanation, and under it whatever macOS or the
/// Keychain just refused.
private struct SettingsFooter: View {
  let footer: String
  let notice: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(footer)
      if let notice {
        // The triangle carries the colour. The words stay primary, so the one
        // line somebody has to act on is never the faintest in the section.
        Label {
          Text(notice)
            .foregroundStyle(.primary)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
        }
      }
    }
    .formFooterStyle()
  }
}

/// Redraws its content whenever one access object changes. GitLab has a
/// section per instance, and a view cannot observe the objects inside an array.
private struct ObservingAccess<Content: View>: View {
  @ObservedObject var access: GitHubAccess
  @ViewBuilder let content: (GitHubAccess) -> Content

  var body: some View { content(access) }
}
