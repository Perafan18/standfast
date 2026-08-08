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
  #expect(compact.contains(".frame(maxWidth:.infinity,minHeight:44)"))
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
