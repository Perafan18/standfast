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
