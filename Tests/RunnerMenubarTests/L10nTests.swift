import Foundation
import Testing

@testable import RunnerMenubar

/// Reads one `.lproj` straight off disk, rather than through `L10n`, which
/// answers in whichever language the test host booted in.
private func catalogue(_ localization: String) throws -> [String: String] {
  let path = try #require(
    L10n.resourceBundle.path(
      forResource: "Localizable", ofType: "strings", inDirectory: nil,
      forLocalization: localization))
  let parsed = try #require(
    NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String])
  return parsed
}

@Test func theEnglishCatalogueIsWhatShipsAsTheDefault() throws {
  let english = try catalogue("en")
  #expect(english["menu.start"] == "Start")
  #expect(english["menu.quit"] == "Quit")
  #expect(english["state.noRunners"] == "No runners installed on this Mac")
}

@Test func everyUnknownReasonTellsTheUserWhatToDo() throws {
  // The likeliest thing a new user ever sees. "Unknown" on its own leaves them
  // with nothing to try, so each line has to be the instruction.
  let english = try catalogue("en")
  #expect(english["state.unknown.noCLI"]?.contains("gh") == true)
  #expect(english["state.unknown.notAuthenticated"]?.contains("gh auth login") == true)
  #expect(english["state.unknown.noAnswer"]?.contains("network") == true)
}

@Test func spanishTranslatesExactlyTheSameKeys() throws {
  // A key present in one catalogue and missing from the other is a menu line
  // that silently switches language, or falls back while everything around it
  // does not.
  let english = try catalogue("en")
  let spanish = try catalogue("es")
  #expect(Set(english.keys) == Set(spanish.keys))
  #expect(!spanish.values.contains(""))
}

@Test func everyStringUsedInTheMenuIsInTheCatalogue() throws {
  // `L10n` falls back to English in code when a key is missing, which is what
  // keeps a packaging mistake from blanking the menu — and would also hide a
  // key that was never translated. This is the check that does not.
  let english = try catalogue("en")
  let used = [
    "menu.start", "menu.stop", "menu.restart", "menu.openOnGitHub",
    "menu.refreshNow", "menu.quit", "state.noRunners", "state.unreadable",
    "state.idle", "state.busy", "state.disconnected", "state.stopped",
    "state.starting", "state.unknown.noCLI", "state.unknown.notAuthenticated",
    "state.unknown.noAnswer",
  ]
  #expect(Set(used) == Set(english.keys))
}

@Test func theCatalogueIsWhatTheMenuActuallyReads() throws {
  // Without this, the fallbacks would carry the whole app and a localisation
  // that never shipped would look exactly like one that did: every string
  // resolves, in English, and every other test still passes.
  #expect(L10n.t("menu.start", "not from the catalogue") != "not from the catalogue")

  // And it is the language this Mac asked for that wins. Worth more on a host
  // that does not boot in English, where "en" and the in-code fallback are
  // indistinguishable.
  let chosen = try #require(L10n.localization)
  #expect(L10n.start == (try catalogue(chosen))["menu.start"])
}

@Test func theChosenLanguageIsTheUsersAndNotTheBundleNegotiation() throws {
  // The negotiation `Bundle` does on its own runs through the main bundle,
  // which for this app declares no languages — so it answers "en" whatever
  // the user set, and every catalogue but English becomes dead weight.
  let asked = Bundle.preferredLocalizations(
    from: L10n.resourceBundle.localizations, forPreferences: Locale.preferredLanguages)
  #expect(L10n.localization == asked.first)
  #expect(L10n.resourceBundle.localizations.sorted() == ["en", "es"])
}

@Test func aMissingCatalogueCostsTheTranslationAndNothingElse() {
  // The reason every string carries English in the source. This app is
  // assembled into its `.app` by a shell script, so `.lproj` directories
  // landing in the wrong place is a packaging mistake waiting to happen, and
  // it has to cost an untranslated menu rather than a blank one.
  #expect(L10n.t("no.such.key.exists", "Refresh now") == "Refresh now")
  #expect(L10n.t("", "Start") == "Start")
}

@Test func theLookupAnswersWithSomethingUsableForEveryString() {
  // Whatever language this host is in, no string may come back empty or as its
  // own dotted key — the two ways a broken localisation shows up on screen.
  let everyString = [
    L10n.start, L10n.stop, L10n.restart, L10n.openOnGitHub, L10n.refreshNow,
    L10n.quit, L10n.noRunnersFound, L10n.someRunnersUnreadable, L10n.stateIdle,
    L10n.stateBusy, L10n.stateDisconnected, L10n.stateStopped, L10n.stateStarting,
    L10n.stateUnknownNoCLI, L10n.stateUnknownNotAuthenticated,
    L10n.stateUnknownNoAnswer,
  ]
  for string in everyString {
    #expect(!string.isEmpty)
    #expect(!string.hasPrefix("menu."))
    #expect(!string.hasPrefix("state."))
  }
  #expect(Set(everyString).count == everyString.count)
}
