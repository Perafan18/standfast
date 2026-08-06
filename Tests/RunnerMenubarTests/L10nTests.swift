import Foundation
import Testing

@testable import RunnerMenubar

/// Reads one `.lproj` straight off disk, rather than through `L10n`, which
/// answers in whichever language the test host booted in.
private func catalogue(_ localization: String) throws -> [String: String] {
  let bundle = try #require(L10n.resourceBundle)
  let path = try #require(
    bundle.path(
      forResource: "Localizable", ofType: "strings", inDirectory: nil,
      forLocalization: localization))
  return try #require(
    NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String])
}

/// One catalogue as a bundle, so a lookup can be pointed at a language instead
/// of at whatever this host prefers.
private func speaking(_ localization: String) throws -> Bundle {
  let bundle = try #require(L10n.resourceBundle)
  let path = try #require(bundle.path(forResource: localization, ofType: "lproj"))
  return try #require(Bundle(path: path))
}

// MARK: - The floor

@Test func everyStringSurvivesHavingNoCatalogueAtAll() {
  // The promise the fallbacks exist to keep. Unit 6 assembles the `.app` with
  // a shell script, so the catalogues not arriving is a live possibility, and
  // it has to cost the translation and nothing else.
  for (key, english) in L10n.english {
    #expect(L10n.t(key, in: []) == english)
  }
}

@Test func noStringEverComesBackAsItsOwnKey() {
  // The other way a broken localisation shows up on screen: a menu of dotted
  // identifiers. `t` can only produce one by being asked for a key the table
  // does not have, so this is really a check that the table is complete.
  for key in L10n.english.keys {
    #expect(L10n.t(key, in: []) != key)
  }
  let everyString = [
    L10n.start, L10n.stop, L10n.restart, L10n.openOnGitHub, L10n.refreshNow,
    L10n.quit, L10n.noRunnersFound, L10n.someRunnersUnreadable, L10n.moreUnreadable,
    L10n.stateIdle, L10n.stateBusy, L10n.stateDisconnected, L10n.stateStopped,
    L10n.stateStarting, L10n.stateUnknownNoCLI, L10n.stateUnknownNotAuthenticated,
    L10n.stateUnknownNoAnswer, L10n.runnerRow("a", "b"),
  ]
  for string in everyString {
    #expect(!string.isEmpty)
    #expect(!string.hasPrefix("menu."))
    #expect(!string.hasPrefix("state."))
  }
}

@Test func aBundleThatCannotBeFoundIsNotAnError() {
  // `Bundle.module` would have made it one: the accessor SwiftPM generates for
  // it calls `fatalError` when the bundle is neither beside the binary nor at
  // the absolute build path it was compiled with — which is every machine
  // except the one that built it. Nothing degrades after a trap.
  let found = [L10n.resourceBundle, Bundle.main].compactMap { $0 }
  #expect(L10n.bundles.count == found.count)
  #expect(L10n.t("menu.start", in: []) == "Start")
}

// MARK: - The catalogues

@Test func theEnglishCatalogueAndTheBuiltInEnglishAreTheSameText() throws {
  // Two copies of the same strings, and they would drift silently: the
  // catalogue is what a correctly packaged app shows, the table is what a
  // broken one shows, and nobody sees both.
  #expect(try catalogue("en") == L10n.english)
}

@Test func spanishTranslatesExactlyTheSameKeys() throws {
  let spanish = try catalogue("es")
  #expect(Set(spanish.keys) == Set(L10n.english.keys))
  #expect(!spanish.values.contains(""))
}

@Test func theCatalogueIsWhatTheLookupReads() throws {
  // Pointed at Spanish on purpose rather than at this host's language: on an
  // English CI runner the catalogue and the built-in table hold the same
  // strings, and a test that cannot tell them apart proves nothing about
  // either.
  let spanish = try speaking("es")
  #expect(L10n.t("menu.start", in: [spanish]) == "Arrancar")
  #expect(L10n.t("menu.start", in: [spanish]) != L10n.english["menu.start"])
  #expect(L10n.t("state.stopped", in: [spanish]) == "Detenido")
}

@Test func everyUnknownReasonTellsTheUserWhatToDo() {
  // The likeliest thing a new user ever sees. "Unknown" on its own leaves them
  // with nothing to try, so each line has to be the instruction.
  #expect(L10n.english["state.unknown.noCLI"]?.contains("gh") == true)
  #expect(
    L10n.english["state.unknown.notAuthenticated"]?.contains("gh auth login") == true)
  #expect(L10n.english["state.unknown.noAnswer"]?.contains("network") == true)
}

@Test func theRunnerRowFormatTakesBothOfItsArguments() throws {
  #expect(L10n.runnerRow("build-mac", "Idle").contains("build-mac"))
  #expect(L10n.runnerRow("build-mac", "Idle").contains("Idle"))
  for language in ["en", "es"] {
    let format = try #require(try catalogue(language)["menu.runnerRow"])
    #expect(format.components(separatedBy: "%@").count == 3)
  }
}

// MARK: - Which language

@Test func theLanguageIsTheOneThisMacAskedFor() throws {
  // Not what `Bundle` would negotiate by itself. That runs through the main
  // bundle, which under `swift run` declares no languages at all, so it
  // answers "en" whatever the user set — measured on a Mac running es-419 with
  // both catalogues sitting in the bundle it was reading from.
  let chosen = try #require(L10n.localization)
  #expect(["en", "es"].contains(chosen))
  #expect(try catalogue(chosen)["menu.start"] == L10n.start)
}
