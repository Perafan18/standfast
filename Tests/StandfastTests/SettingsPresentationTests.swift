import Foundation
import Testing

@testable import Standfast

private func settingsSource(_ name: String) -> String {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = repository.appendingPathComponent("Sources/Standfast/\(name)")
  return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
}

@Test func versionUsesTheBundleShortVersionAndBuild() {
  #expect(
    SettingsPresentation.version(infoDictionary: [
      "CFBundleShortVersionString": "0.5.0",
      "CFBundleVersion": "5",
    ]) == "Standfast 0.5.0 (5)")
}

@Test func versionDegradesCleanlyWhenBundleFieldsAreMissing() {
  #expect(
    SettingsPresentation.version(infoDictionary: [
      "CFBundleShortVersionString": "0.5.0"
    ]) == "Standfast 0.5.0")
  #expect(
    SettingsPresentation.version(infoDictionary: [
      "CFBundleVersion": "5"
    ]) == "Standfast (5)")
  #expect(SettingsPresentation.version(infoDictionary: [:]) == "Standfast")
  #expect(SettingsPresentation.version(infoDictionary: nil) == "Standfast")
}

@Test func versionRejectsBlankOrUnexpectedBundleValuesWithoutLeakingOptionals() {
  let version = SettingsPresentation.version(infoDictionary: [
    "CFBundleShortVersionString": "  ",
    "CFBundleVersion": 5,
  ])

  #expect(version == "Standfast")
  #expect(!version.contains("Optional"))
  #expect(!version.contains("()"))
}

@Test func runtimeNoticesAreAdditionalToEveryPermanentFooter() {
  let presentation = SettingsPresentation(
    notificationNotice: "Permission denied",
    loginItemNotice: "Approval required",
    infoDictionary: [:])

  #expect(
    presentation.notifications.supportingText
      == [L10n.settingsNotificationsFooter, "Permission denied"])
  #expect(
    presentation.power.supportingText
      == [L10n.settingsPowerFooter])
  #expect(
    presentation.startup.supportingText
      == [L10n.settingsStartupFooter, "Approval required"])
}

@Test func permanentFootersRemainWhenThereAreNoRuntimeNotices() {
  let presentation = SettingsPresentation(
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(
    presentation.notifications.supportingText
      == [L10n.settingsNotificationsFooter])
  #expect(presentation.power.supportingText == [L10n.settingsPowerFooter])
  #expect(presentation.startup.supportingText == [L10n.settingsStartupFooter])
}

@Test func settingsAccessibilityIdentifiersAreStableAndNonlocalized() {
  #expect(
    SettingsAccessibility.notification(.jobFailed)
      == "dev.standfast.settings.notifications.job-failed")
  #expect(
    SettingsAccessibility.notification(.runnerDisconnected)
      == "dev.standfast.settings.notifications.disconnected")
  #expect(
    SettingsAccessibility.notification(.runnerStopped)
      == "dev.standfast.settings.notifications.stopped")
  #expect(
    SettingsAccessibility.powerPreventSleep
      == "dev.standfast.settings.power.prevent-sleep")
  #expect(
    SettingsAccessibility.startupOpenAtLogin
      == "dev.standfast.settings.startup.open-at-login")
  #expect(SettingsAccessibility.version == "dev.standfast.settings.version")
}

@Test func settingsSourceKeepsPermanentCopyAndExactToggleIdentifiersWired() {
  let source = settingsSource("SettingsView.swift")
  let compact = source.filter { !$0.isWhitespace }

  #expect(!compact.contains("Form{"))
  #expect(!compact.contains(".formStyle(.grouped)"))
  #expect(!compact.contains("TabView"))
  #expect(!compact.contains("NavigationStack"))
  #expect(!compact.contains("NavigationSplitView"))
  #expect(compact.contains("ScrollView{"))
  #expect(compact.contains("Image(nsImage:NSApplication.shared.applicationIconImage)"))
  #expect(
    compact.contains(
      ".accessibilityIdentifier(SettingsAccessibility.notification(kind))"))
  #expect(
    compact.contains(
      ".accessibilityIdentifier(SettingsAccessibility.powerPreventSleep)"))
  #expect(
    compact.contains(
      ".accessibilityIdentifier(SettingsAccessibility.startupOpenAtLogin)"))
  #expect(
    compact.contains(
      ".accessibilityIdentifier(SettingsAccessibility.version)"))
  #expect(compact.contains("supportingText(presentation.power)"))
  #expect(!compact.contains("ifsleep.isEnabled"))
  // The row keeps the 44 pt pointer target and takes the whole card width, so
  // every switch lands on one trailing edge. An intrinsically sized row hugs
  // its own label instead, and the section reads as a ragged, centred stack.
  // 32, not 44: 44 is the iPhone touch target this theme rejected once
  // already — `controlMinimumHeight` is 28 because a pointer is not a thumb.
  // A settings row still wants more air than a button, which is why it is not
  // 28 either.
  #expect(compact.contains(".frame(maxWidth:.infinity,minHeight:32)"))
  #expect(
    compact.contains(
      "Label(title,systemImage:systemImage).foregroundStyle(palette.textPrimary.color)"
        + ".frame(maxWidth:.infinity,alignment:.leading)"))
  #expect(compact.contains("VStack(alignment:.leading,spacing:0){"))
}

@Test func settingsGeometryUsesMeasuredThemeTokensAtTheViewAndScene() {
  let view = settingsSource("SettingsView.swift").filter { !$0.isWhitespace }
  let app = settingsSource("App.swift").filter { !$0.isWhitespace }

  #expect(view.contains("minWidth:StandfastTheme.settingsMinimumWidth"))
  #expect(view.contains("idealWidth:StandfastTheme.settingsIdealWidth"))
  #expect(view.contains("maxWidth:StandfastTheme.settingsMaximumWidth"))
  #expect(app.contains("width:StandfastTheme.settingsIdealWidth"))
  #expect(app.contains("height:StandfastTheme.settingsDefaultHeight"))
  #expect(app.contains("infoDictionary:Bundle.main.infoDictionary"))
}

// MARK: - GitHub access

@Test func aMachineWithNoTokenIsToldItIsUsingTheCli() {
  let presentation = SettingsPresentation(
    githubState: .absent, githubNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(presentation.github.currentState == L10n.settingsGitHubAbsent)
  #expect(presentation.github.supportingText == [L10n.settingsGitHubFooter])
  // Nothing to remove, so nothing offers to. A button that does nothing is a
  // question the user has to answer about their own machine.
  #expect(!presentation.github.canRemove)
}

@Test func aStoredTokenIsAnnouncedWithoutEverBeingShown() {
  let presentation = SettingsPresentation(
    githubState: .stored, githubNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(presentation.github.currentState == L10n.settingsGitHubStored)
  #expect(presentation.github.canRemove)
}

@Test func aKeychainThatWouldNotAnswerStillOffersTheWayOut() {
  // Remove stays available: it is the recovery from an item this app can no
  // longer read, and refusing to offer it would leave the user with a Keychain
  // entry they have to go find themselves.
  let presentation = SettingsPresentation(
    githubState: .unreadable, githubNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(presentation.github.currentState == L10n.settingsGitHubUnreadable)
  #expect(presentation.github.canRemove)
}

@Test func aKeychainComplaintJoinsThePermanentExplanation() {
  let presentation = SettingsPresentation(
    githubState: .absent, githubNotice: L10n.settingsGitHubKeychainFailed,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(
    presentation.github.supportingText
      == [L10n.settingsGitHubFooter, L10n.settingsGitHubKeychainFailed])
}

@Test func theGitHubIdentifiersAreStableAndNonlocalized() {
  #expect(SettingsAccessibility.githubToken == "dev.standfast.settings.github.token")
  #expect(SettingsAccessibility.githubSave == "dev.standfast.settings.github.save")
  #expect(SettingsAccessibility.githubRemove == "dev.standfast.settings.github.remove")
}

// MARK: - GitLab access

@Test func aMacWithoutGitLabGetsNoGitLabCard() {
  // Most Macs. A token field for a provider with nothing on the machine is a
  // question the user cannot act on.
  let presentation = SettingsPresentation(
    githubState: .absent, githubNotice: nil,
    gitLabState: nil, gitLabNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(presentation.gitLab == nil)
}

@Test func aMacWithGitLabRunnersGetsItsOwnTokenCard() {
  let presentation = SettingsPresentation(
    githubState: .absent, githubNotice: nil,
    gitLabState: .absent, gitLabNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  let gitLab = presentation.gitLab
  #expect(gitLab?.currentState == L10n.settingsGitLabAbsent)
  #expect(gitLab?.footer == L10n.settingsGitLabFooter)
  #expect(gitLab?.canRemove == false)
}

@Test func aStoredGitLabTokenIsAnnouncedInGitLabsWords() {
  let presentation = SettingsPresentation(
    githubState: .absent, githubNotice: nil,
    gitLabState: .stored, gitLabNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(presentation.gitLab?.currentState == L10n.settingsGitLabStored)
  #expect(presentation.gitLab?.canRemove == true)
}
