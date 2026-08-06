import Foundation
import Testing

@testable import Standfast

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
    L10n.quit, L10n.recentJobs, L10n.openAtLogin, L10n.openAtLoginFailed,
    L10n.openAtLoginNeedsApproval, L10n.openAtLoginUnavailable,
    L10n.noRunnersFound, L10n.someRunnersUnreadable, L10n.moreUnreadable,
    L10n.stateIdle, L10n.stateBusy, L10n.stateDisconnected, L10n.stateStopped,
    L10n.stateStarting, L10n.stateUnknownNoCLI, L10n.stateUnknownNotAuthenticated,
    L10n.stateUnknownNoAnswer, L10n.stateUnknownNoLocalAnswer,
    L10n.checkedJustNow, L10n.checkedNever, L10n.jobSucceeded, L10n.jobFailed,
    L10n.jobCanceled, L10n.jobInterrupted,
    L10n.runnerRow("a", "b"), L10n.runnerInScope("a", "b"),
    L10n.jobRunning("a", "b"), L10n.jobRunningWithTypical("a", "b", "c"),
    L10n.jobRow("a", "b", "c"), L10n.jobRowNoDuration("a", "b"), L10n.checkedAgo("a"),
    L10n.durationHoursMinutes(1, 2), L10n.durationMinutesSeconds(1, 2),
    L10n.durationHours(1), L10n.durationMinutes(1), L10n.durationSeconds(1),
  ]
  // Every prefix a key in this app can start with. Derived rather than listed,
  // so a new family of keys cannot quietly escape the check.
  let prefixes = Set(L10n.english.keys.compactMap { $0.split(separator: ".").first })
  for string in everyString {
    #expect(!string.isEmpty)
    for prefix in prefixes { #expect(!string.hasPrefix(prefix + ".")) }
  }
}

@Test func everyKeyInTheTableIsReachableThroughLOne() {
  // The table is what a broken package falls back to, and a key nobody reads
  // is a string the menu can never show — a translated line that goes nowhere,
  // or worse, a call site that never got moved off a literal.
  let everyKey = Set(L10n.english.keys)
  let reached = Set(
    [
      "menu.start", "menu.stop", "menu.restart", "menu.openOnGitHub",
      "menu.refreshNow", "menu.quit", "menu.recentJobs", "menu.openAtLogin",
      "menu.openAtLogin.failed", "menu.openAtLogin.needsApproval",
      "menu.openAtLogin.unavailable", "menu.runnerRow", "menu.runnerInScope",
      "state.noRunners", "state.unreadable", "state.unreadable.more", "state.idle",
      "state.busy", "state.disconnected", "state.stopped", "state.starting",
      "state.unknown.noCLI", "state.unknown.notAuthenticated",
      "state.unknown.noAnswer", "state.unknown.noLocalAnswer", "state.checkedAgo",
      "state.checkedJustNow", "state.checkedNever", "job.running",
      "job.runningWithTypical", "job.row", "job.rowNoDuration",
      "job.result.succeeded", "job.result.failed", "job.result.canceled",
      "job.result.interrupted", "duration.hoursMinutes", "duration.minutesSeconds",
      "duration.hours", "duration.minutes", "duration.seconds",
    ])
  #expect(everyKey == reached)
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
  // This one is not about gh at all — it is the local probe that went quiet —
  // so pointing the user at their network or their credentials would send them
  // to the wrong place entirely.
  let noLocal = L10n.english["state.unknown.noLocalAnswer"]
  #expect(noLocal?.contains("launchctl") == true)
  #expect(noLocal?.contains(L10n.english["menu.refreshNow"] ?? "") == true)
}

@Test func theRunnerRowFormatTakesBothOfItsArguments() throws {
  #expect(L10n.runnerRow("build-mac", "Idle").contains("build-mac"))
  #expect(L10n.runnerRow("build-mac", "Idle").contains("Idle"))
  for language in ["en", "es"] {
    let format = try #require(try catalogue(language)["menu.runnerRow"])
    #expect(format.components(separatedBy: "%@").count == 3)
  }
}

@Test func everyFormatKeepsThePlaceholdersItsCallSitePasses() throws {
  // A translation that dropped one silently erases whichever fact it stood for
  // — the job's name, how long it has been going, or what it usually takes —
  // and `String(format:)` will not say a word about it.
  let expected = [
    "job.running": 2, "job.runningWithTypical": 3, "job.row": 3,
    "job.rowNoDuration": 2, "state.checkedAgo": 1,
  ]
  for language in ["en", "es"] {
    let catalogue = try catalogue(language)
    for (key, count) in expected {
      let format = try #require(catalogue[key])
      #expect(format.components(separatedBy: "%@").count == count + 1)
    }
  }
}

@Test func everyDurationFormatKeepsItsNumbers() throws {
  let expected = [
    "duration.hoursMinutes": 2, "duration.minutesSeconds": 2, "duration.hours": 1,
    "duration.minutes": 1, "duration.seconds": 1,
  ]
  for language in ["en", "es"] {
    let catalogue = try catalogue(language)
    for (key, count) in expected {
      let format = try #require(catalogue[key])
      #expect(format.filter { $0 == "%" }.count == count)
      // `%@` where a number is passed is a format reading a `CVarArg` as a
      // pointer, which is a crash rather than a wrong string.
      #expect(!format.contains("%@"))
    }
  }
  #expect(L10n.durationMinutesSeconds(2, 47) == "2m 47s")
  // Zero-padded, so `2m 7s` never sits under `2m 47s` looking longer.
  #expect(L10n.durationMinutesSeconds(2, 7) == "2m 07s")
}

@Test func theScopedNameFormatTakesBothOfItsArgumentsToo() throws {
  // A format that dropped one of them would silently erase either the runner's
  // name or the only thing separating it from the runner below it.
  #expect(L10n.runnerInScope("mac-mini-m4", "acme/widget").contains("mac-mini-m4"))
  #expect(L10n.runnerInScope("mac-mini-m4", "acme/widget").contains("acme/widget"))
  for language in ["en", "es"] {
    let format = try #require(try catalogue(language)["menu.runnerInScope"])
    #expect(format.components(separatedBy: "%@").count == 3)
  }
}
