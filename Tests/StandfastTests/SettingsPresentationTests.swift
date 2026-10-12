import Foundation
import RunnerKit
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

  // Panes of grouped forms behind toolbar tabs, the way System Settings draws
  // its own, rather than one long scrolling column of cards.
  #expect(compact.contains("TabView(selection:"))
  #expect(compact.contains(".formStyle(.grouped)"))
  #expect(compact.contains(".tabItem"))
  #expect(!compact.contains("ScrollView{"))
  #expect(!compact.contains("NavigationStack"))
  #expect(!compact.contains("NavigationSplitView"))
  // Not remembered across launches. A tab view keeps only the selected pane in
  // the accessibility tree, so a launch that brought Settings back on Accounts
  // would hide every switch the strict gate reads.
  #expect(source.contains("@State private var pane"))
  #expect(!compact.contains("@AppStorage(\"settings.pane\""))
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
}

@Test func theVersionSitsUnderGeneralsFormAndNotInAFooter() throws {
  // A section with no rows draws an empty box, and a grouped form is a list:
  // a footer scrolled out of sight can leave the accessibility tree, taking
  // the gate's version identifier with it.
  let compact = settingsSource("SettingsView.swift").filter { !$0.isWhitespace }
  let general = try #require(compact.range(of: "structGeneralSettingsPane:View{"))
  let form = try #require(
    compact.range(of: ".formStyle(.grouped)", range: general.upperBound..<compact.endIndex))
  let version = try #require(
    compact.range(of: ".accessibilityIdentifier(SettingsAccessibility.version)"))
  let frame = try #require(
    compact.range(
      of: "height:StandfastTheme.settingsGeneralHeight)",
      range: general.upperBound..<compact.endIndex))

  #expect(form.upperBound <= version.lowerBound)
  #expect(version.upperBound <= frame.lowerBound)
  #expect(!compact.contains("Section{}"))
}

@Test func eachTokenSectionSavesOnReturnAndOffersRemoveOnItsOwn() {
  let compact = settingsSource("SettingsView.swift").filter { !$0.isWhitespace }

  // Remove does not depend on Save: over http nothing is saved, and a token
  // stored before that rule must still be removable.
  #expect(compact.contains("ifpresentation.canRemove{Button(L10n.settingsGitHubRemove"))
  #expect(
    compact.contains(
      ".disabled(draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)"
    ))
  // Return in the field. A default button per section would put several in
  // one window as soon as a GitLab instance has a section.
  #expect(compact.contains(".onSubmit{save(draft,to:access)}"))
  #expect(!compact.contains(".keyboardShortcut(.defaultAction)"))
  // A grouped form draws the field borderless. Its label is what makes the row
  // read as a field, so the prompt never stands in for one.
  #expect(
    compact.contains(
      "SecureField(text:draft,prompt:Text(placeholder)){Text(L10n.settingsToken)}"))
  #expect(!compact.contains(".labelsHidden()"))
  #expect(compact.contains(".accessibilityIdentifier(identifiers.token)"))
  #expect(compact.contains(".accessibilityIdentifier(identifiers.save)"))
  #expect(compact.contains(".accessibilityIdentifier(identifiers.remove)"))
  #expect(compact.contains(".accessibilityIdentifier(SettingsAccessibility.runnersAdd)"))
  // Each GitLab section redraws when its own access object changes.
  #expect(compact.contains("ObservingAccess(access:entry.access)"))
}

@Test func settingsGeometryUsesMeasuredThemeTokensAtTheViewAndScene() {
  let view = settingsSource("SettingsView.swift").filter { !$0.isWhitespace }
  let app = settingsSource("App.swift").filter { !$0.isWhitespace }
  let settingsScene = app.components(separatedBy: "Settings{").last ?? ""

  // A height of its own on every pane: under `.contentSize` a form without
  // one collapses. Each is cut to the display it opens on, never stretched.
  for height in [
    "settingsGeneralHeight)",
    "settingsRunnersHeight(folders:manualRunners.directories.count))",
    "settingsAccountsHeight(gitLabInstances:gitLab.cards.count))",
  ] {
    #expect(view.contains(".settingsPaneFrame(height:StandfastTheme." + height))
  }
  #expect(view.components(separatedBy: ".settingsPaneFrame(").count == 4)
  #expect(
    view.contains(
      "frame(width:StandfastTheme.settingsPaneWidth,height:StandfastTheme.settingsPaneHeight("
        + "height,screenHeight:NSScreen.main?.visibleFrame.height))"))
  #expect(settingsScene.contains("width:StandfastTheme.settingsPaneWidth"))
  #expect(settingsScene.contains(".windowResizability(.contentSize)"))
  #expect(app.contains("infoDictionary:Bundle.main.infoDictionary"))
}

@Test func aPaneIsCutToADisplayTooShortForItAndNeverStretched() {
  // Literals, not built from the tokens: these are display sizes.
  // Nothing to ask, as in a test run with no screen: the measured height.
  #expect(StandfastTheme.settingsPaneHeight(690, screenHeight: nil) == 690)
  // 1440×900 less the menu bar has room for General and its chrome.
  #expect(StandfastTheme.settingsPaneHeight(690, screenHeight: 875) == 690)
  // 1024×640, a 13" MacBook Air at Larger Text, less a notched menu bar:
  // General fits under its title bar and tabs, and its form scrolls.
  #expect(StandfastTheme.settingsPaneHeight(690, screenHeight: 603) == 503)
  // A pane that already fits keeps its own height.
  #expect(StandfastTheme.settingsPaneHeight(230, screenHeight: 603) == 230)
  // However short the display, a pane keeps more than a row or two.
  #expect(StandfastTheme.settingsPaneHeight(690, screenHeight: 200) == 300)
  #expect(StandfastTheme.settingsPaneHeight(230, screenHeight: 200) == 230)
}

@Test func aPaneGrowsWithWhatItListsUntilGeneralsHeight() {
  // Literals, not built from the tokens: these are the measured numbers.
  #expect(StandfastTheme.settingsPaneWidth == 520)
  #expect(StandfastTheme.settingsGeneralHeight == 690)
  // The empty line and one folder take the same room, then a row each.
  #expect(StandfastTheme.settingsRunnersHeight(folders: 0) == 230)
  #expect(StandfastTheme.settingsRunnersHeight(folders: 1) == 230)
  #expect(StandfastTheme.settingsRunnersHeight(folders: 3) == 342)
  // GitHub alone, then a section per GitLab instance.
  #expect(StandfastTheme.settingsAccountsHeight(gitLabInstances: 0) == 300)
  #expect(StandfastTheme.settingsAccountsHeight(gitLabInstances: 1) == 580)
  // Past General's height the form scrolls instead, so no pane makes the
  // window taller than General.
  #expect(StandfastTheme.settingsRunnersHeight(folders: 40) == 690)
  #expect(StandfastTheme.settingsAccountsHeight(gitLabInstances: 5) == 690)
}

// MARK: - GitHub access

@Test func aMachineWithNoTokenIsToldItIsUsingTheCli() {
  let presentation = SettingsPresentation(
    githubState: .absent, githubNotice: nil,
    notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil)

  #expect(presentation.github.currentState == L10n.settingsGitHubAbsent)
  #expect(presentation.github.supportingText == [L10n.settingsGitHubFooter])
  #expect(presentation.github.canSave)
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

@MainActor
@Test func aMacWithoutGitLabGetsNoGitLabCard() {
  // Most Macs. A token field for a provider with nothing on the machine is a
  // question the user cannot act on.
  let missing = URL(fileURLWithPath: "/nonexistent/.gitlab-runner/config.toml")

  #expect(GitLabInstanceAccess.forInstances(in: missing).isEmpty)
}

/// One instance's token, in memory: Settings must not read the Keychain of
/// whoever runs the tests.
private struct InstanceTokenStore: GitHubTokenStoring {
  let stored: String?

  func token() throws -> String? { stored }
  func store(_ token: String) throws {}
  func clear() throws {}
}

@MainActor
@Test func eachInstanceTheConfigNamesGetsACardOverItsOwnToken() async throws {
  // Settings writes a pasted token where its card's store points. A card over
  // another instance's store, or one store for all of them, saves a token
  // where the client never reads it, and shows one instance's as another's.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "standfast-gitlab-cards-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let config = root.appendingPathComponent("config.toml")
  try """
  [[runners]]
    id = 1
    url = "https://gitlab.com"
  [[runners]]
    id = 2
    url = "https://gitlab.corp.example:8443/"
  [[runners]]
    id = 3
    url = "https://gitlab.com/"
  """.write(to: config, atomically: true, encoding: .utf8)
  let com = try #require(GitLabInstance(url: "https://gitlab.com"))
  let corp = try #require(GitLabInstance(url: "https://gitlab.corp.example:8443"))
  var asked: [GitLabInstance] = []

  let cards = GitLabInstanceAccess.forInstances(in: config) { instance in
    asked.append(instance)
    return InstanceTokenStore(stored: instance == corp ? "glpat-corp" : nil)
  }

  #expect(cards.map(\.instance) == [com, corp])
  #expect(asked == [com, corp])
  for card in cards { await card.access.quiesce() }
  #expect(cards.map(\.access.state) == [.absent, .stored])
}

/// Every instance's token in memory, counting what Settings does with each:
/// a read it repeats for a card it already has is one more Keychain read, and
/// one more chance at a dialog, every time Settings is looked at.
private final class InstanceTokens: @unchecked Sendable {
  private let lock = NSLock()
  private var tokens: [String: String]
  private var reads: [String: Int] = [:]
  private var handedOut: [String: Int] = [:]

  init(_ tokens: [String: String] = [:]) { self.tokens = tokens }

  func store(for instance: GitLabInstance) -> any GitHubTokenStoring {
    lock.withLock { handedOut[instance.name, default: 0] += 1 }
    return Account(owner: self, name: instance.name)
  }

  func readCount(_ name: String) -> Int { lock.withLock { reads[name, default: 0] } }
  /// Counted as it happens, unlike the read each store's card starts in the
  /// background, so a test cannot finish before the extra one lands.
  func storeCount(_ name: String) -> Int { lock.withLock { handedOut[name, default: 0] } }

  private func read(_ name: String) -> String? {
    lock.withLock {
      reads[name, default: 0] += 1
      return tokens[name]
    }
  }

  private func write(_ token: String?, _ name: String) {
    lock.withLock { tokens[name] = token }
  }

  private struct Account: GitHubTokenStoring {
    let owner: InstanceTokens
    let name: String

    func token() throws -> String? { owner.read(name) }
    func store(_ token: String) throws { owner.write(token, name) }
    func clear() throws { owner.write(nil, name) }
  }
}

@Test func aGitLabInstanceGetsItsOwnTokenCard() {
  let gitLab = SettingsPresentation.gitLab(.absent, notice: nil, isServedOverHTTPS: true)

  #expect(gitLab.currentState == L10n.settingsGitLabAbsent)
  #expect(gitLab.footer == L10n.settingsGitLabFooter)
  #expect(gitLab.canSave == true)
  #expect(gitLab.canRemove == false)
}

@Test func aStoredGitLabTokenIsAnnouncedInGitLabsWords() {
  let gitLab = SettingsPresentation.gitLab(.stored, notice: nil, isServedOverHTTPS: true)

  #expect(gitLab.currentState == L10n.settingsGitLabStored)
  #expect(gitLab.canSave == true)
  #expect(gitLab.canRemove == true)
}

@Test func anInstanceServedOverHTTPIsNotSaidToBeAsked() {
  // The client never sends a token over http, so "Standfast asks GitLab
  // directly" on this card is false whatever is stored, and a field inviting a
  // token asks somebody to store one that is never sent. Remove stays: a token
  // saved before that rule must still be removable from here.
  for state in [GitHubAccessState.stored, .unreadable, .absent] {
    let gitLab = SettingsPresentation.gitLab(state, notice: nil, isServedOverHTTPS: false)

    #expect(gitLab.currentState == L10n.settingsGitLabInsecure, "\(state)")
    #expect(gitLab.canSave == false, "\(state)")
    #expect(gitLab.canRemove == (state != .absent), "\(state)")
  }
}

@Test func everyGitLabCardHasIdentifiersOfItsOwn() throws {
  // Two instances mean two cards, and a probe has to be able to say which
  // card's token field it means.
  let com = try #require(GitLabInstance(url: "https://gitlab.com"))
  let corp = try #require(GitLabInstance(url: "https://gitlab.corp.example:8443"))

  #expect(
    SettingsAccessibility.gitlab(com).token
      == "dev.standfast.settings.gitlab.gitlab.com.token")
  #expect(
    SettingsAccessibility.gitlab(com).token != SettingsAccessibility.gitlab(corp).token)
}

@MainActor
@Test func aGitLabRunnerRegisteredAfterLaunchStillGetsItsTokenCard() async throws {
  // Standfast opens at login and runs for weeks. A runner registered in
  // between appears at the next scan saying to add a GitLab token in Settings,
  // and Settings has to have somewhere to add it.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "standfast-gitlab-reload-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let config = root.appendingPathComponent("config.toml")
  let tokens = InstanceTokens()
  let cards = GitLabInstanceCards(
    configFile: config, store: tokens.store(for:), defaults: scratchDefaults())
  #expect(cards.cards.isEmpty)

  try """
  [[runners]]
    id = 1
    url = "https://gitlab.com"
  """.write(to: config, atomically: true, encoding: .utf8)
  cards.reload()
  let first = try #require(cards.cards.first)
  #expect(cards.cards.map(\.id) == ["gitlab.com"])
  await first.access.quiesce()

  try """
  [[runners]]
    id = 1
    url = "https://gitlab.com"
  [[runners]]
    id = 2
    url = "https://gitlab.corp.example:8443/"
  """.write(to: config, atomically: true, encoding: .utf8)
  cards.reload()
  cards.reload()
  for card in cards.cards { await card.access.quiesce() }

  // Settings rereads the file each time it appears and each time the app
  // comes back to the front. The new instance gets a card and one read; the
  // one it already showed keeps its card and is not read again.
  #expect(cards.cards.map(\.id) == ["gitlab.com", "gitlab.corp.example:8443"])
  #expect(cards.cards.first?.access === first.access)
  #expect(tokens.storeCount("gitlab.com") == 1)
  #expect(tokens.readCount("gitlab.com") == 1)
  #expect(tokens.readCount("gitlab.corp.example:8443") == 1)

  try """
  [[runners]]
    id = 2
    url = "https://gitlab.corp.example:8443/"
  """.write(to: config, atomically: true, encoding: .utf8)
  cards.reload()

  // Dropped from the file, an instance keeps its card: a token stored for it
  // can still be removed there.
  #expect(cards.cards.map(\.id) == ["gitlab.com", "gitlab.corp.example:8443"])
}

@Test func eachGitLabCardIsDrawnForTheSchemeItsInstanceIsServedOver() {
  // The view decides nothing, so these two are its whole share of the http
  // rule: the card is told the scheme, and the field obeys what it is told.
  let view = settingsSource("SettingsView.swift").filter { !$0.isWhitespace }

  #expect(view.contains("isServedOverHTTPS:entry.instance.isServedOverHTTPS"))
  #expect(view.contains("ifpresentation.canSave{HStack"))
}

@MainActor
@Test func aTokenTheFileNoLongerNamesKeepsItsCardAfterARelaunch() async throws {
  // `gitlab-runner unregister` rewrites config.toml without the instance, and
  // the token pasted for it stays in the Keychain. Standfast opens at login,
  // so the next launch is the next login, and its card is the only Remove
  // button that token has.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "standfast-gitlab-orphans-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let config = root.appendingPathComponent("config.toml")
  try """
  [[runners]]
    id = 1
    url = "https://gitlab.com"
  [[runners]]
    id = 2
    url = "https://gitlab.corp.example:8443/"
  [[runners]]
    id = 3
    url = "http://gitlab.lan/ci"
  """.write(to: config, atomically: true, encoding: .utf8)
  let com = try #require(GitLabInstance(url: "https://gitlab.com"))
  let corp = try #require(GitLabInstance(url: "https://gitlab.corp.example:8443"))
  let lan = try #require(GitLabInstance(url: "http://gitlab.lan/ci"))
  let tokens = InstanceTokens([corp.name: "glpat-corp", lan.name: "glpat-lan"])
  let defaults = scratchDefaults()
  let launch = {
    GitLabInstanceCards(configFile: config, store: tokens.store(for:), defaults: defaults)
  }
  _ = launch()

  try """
  [[runners]]
    id = 1
    url = "https://gitlab.com"
  """.write(to: config, atomically: true, encoding: .utf8)
  let relaunched = launch()
  for card in relaunched.cards { await card.access.quiesce() }

  // Rebuilt from the name alone, an http instance has to stay http: over
  // https it would be another Keychain account, and not the one holding it.
  #expect(relaunched.cards.map(\.instance) == [com, corp, lan])
  #expect(relaunched.cards.map(\.access.state) == [.absent, .stored, .stored])
  // Not only the launch after: for as long as a token is stored for it.
  relaunched.reload()
  #expect(launch().cards.map(\.instance) == [com, corp, lan])
  // Names, never tokens: SECURITY.md promises no token in `UserDefaults`.
  #expect(
    defaults.stringArray(forKey: GitLabInstanceCards.defaultsKey)
      == [com.name, corp.name, lan.name])
}

@MainActor
@Test func anInstanceTheFileDroppedIsForgottenOnceNothingIsStoredForIt() async throws {
  // Remembered for good, a removed token's card would come back at every
  // launch with nothing on it to remove.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "standfast-gitlab-forget-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let config = root.appendingPathComponent("config.toml")
  try """
  [[runners]]
    id = 1
    url = "https://gitlab.com"
  [[runners]]
    id = 2
    url = "https://gitlab.corp.example:8443/"
  """.write(to: config, atomically: true, encoding: .utf8)
  let tokens = InstanceTokens(["gitlab.corp.example:8443": "glpat-corp"])
  let defaults = scratchDefaults()
  let launch = {
    GitLabInstanceCards(configFile: config, store: tokens.store(for:), defaults: defaults)
  }
  _ = launch()
  try "".write(to: config, atomically: true, encoding: .utf8)

  let cards = launch()
  // Before its read settles, a card cannot say nothing is stored, so a reload
  // in that window must not forget it.
  cards.reload()
  #expect(launch().cards.map(\.id) == ["gitlab.com", "gitlab.corp.example:8443"])
  for card in cards.cards { await card.access.quiesce() }
  let corp = try #require(cards.cards.last?.access)
  corp.remove()
  await corp.quiesce()
  cards.reload()

  // Still shown until the app quits, and gone after: nothing names either
  // instance any more, and nothing is stored for either.
  #expect(cards.cards.count == 2)
  #expect(launch().cards.isEmpty)
}

@Test func settingsRereadsTheGitLabCardsWhenItIsShown() {
  let view = settingsSource("SettingsView.swift").filter { !$0.isWhitespace }

  #expect(view.contains("gitLab.reload()"))
  #expect(view.contains(".onAppear{rereadWhatMacOSDecides()}"))
}
