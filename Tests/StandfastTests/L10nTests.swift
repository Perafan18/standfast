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
    L10n.notifyMe, L10n.notifyJobFailed, L10n.notifyDisconnected, L10n.notifyStopped,
    L10n.notificationsBlocked, L10n.preventSleep, L10n.preventSleepLidNotice,
    L10n.thermalSerious, L10n.thermalCritical, L10n.thermalSlowingJobs,
    L10n.notificationJobFailedTitle, L10n.notificationDisconnectedTitle,
    L10n.notificationStoppedTitle, L10n.notificationJobFailedBody("a", "b"),
    L10n.notificationDisconnectedBody("a"), L10n.notificationStoppedBody("a"),
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
    L10n.maintenance, L10n.measureDiskUse, L10n.deletingOnlyWhenIdle,
    L10n.diskWorking, L10n.diskNotMeasured, L10n.diskMeasuredJustNow,
    L10n.diskUnavailable, L10n.cleanupDelete, L10n.cleanupCancel,
    L10n.cleanupToolCacheEffect, L10n.cleanupActionCacheEffect,
    L10n.diskToolCache("a"), L10n.diskActionCache("a"), L10n.diskCheckouts("a"),
    L10n.diskTemporary("a"), L10n.diskOther("a"), L10n.diskLogs("a"),
    L10n.diskMeasuredAgo("a"), L10n.freeToolCache("a"), L10n.freeActionCache("a"),
    L10n.deleteOldLogs("a"), L10n.runnerVersion("a"),
    L10n.runnerVersionOutdated("a", "b"), L10n.cleanupConfirmTitle("a"),
    L10n.cleanupConfirmBody("a", "b"), L10n.cleanupLogsTitle(1, "a"),
    L10n.cleanupLogsEffect(1), L10n.cleanupRefused("a"), L10n.cleanupFailed("a"),
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
      "menu.notify", "menu.notify.jobFailed", "menu.notify.disconnected",
      "menu.notify.stopped", "menu.notify.blocked", "menu.preventSleep",
      "menu.preventSleep.lid", "thermal.serious", "thermal.critical",
      "thermal.slowingJobs", "notification.jobFailed.title",
      "notification.jobFailed.body", "notification.disconnected.title",
      "notification.disconnected.body", "notification.stopped.title",
      "notification.stopped.body",
      "state.noRunners", "state.unreadable", "state.unreadable.more", "state.idle",
      "state.busy", "state.disconnected", "state.stopped", "state.starting",
      "state.unknown.noCLI", "state.unknown.notAuthenticated",
      "state.unknown.noAnswer", "state.unknown.noLocalAnswer", "state.checkedAgo",
      "state.checkedJustNow", "state.checkedNever", "job.running",
      "job.runningWithTypical", "job.row", "job.rowNoDuration",
      "job.result.succeeded", "job.result.failed", "job.result.canceled",
      "job.result.interrupted", "duration.hoursMinutes", "duration.minutesSeconds",
      "duration.hours", "duration.minutes", "duration.seconds",
      "menu.maintenance", "menu.maintenance.measure",
      "menu.maintenance.freeToolCache", "menu.maintenance.freeActionCache",
      "menu.maintenance.trimLogs", "menu.maintenance.onlyWhenIdle",
      "menu.runnerVersion", "menu.runnerVersion.update",
      "disk.toolCache", "disk.actionCache", "disk.checkout", "disk.temporary",
      "disk.other", "disk.logs", "disk.working", "disk.notMeasured",
      "disk.measuredJustNow", "disk.measuredAgo", "disk.unavailable",
      "cleanup.confirm.title", "cleanup.confirm.body", "cleanup.confirm.delete",
      "cleanup.confirm.cancel", "cleanup.toolCache.effect",
      "cleanup.actionCache.effect", "cleanup.logs.title", "cleanup.logs.effect",
      "cleanup.refused", "cleanup.failed",
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
    // A banner is read out of the corner of an eye. A translation that dropped
    // the runner's name leaves "failed on" and a Mac with two runners, which is
    // a notification that costs a trip to GitHub to act on.
    "notification.jobFailed.body": 2, "notification.disconnected.body": 1,
    "notification.stopped.body": 1,
    // The confirmation is the last thing between a click and four gigabytes
    // going away, and both of its facts are placeholders: a translation that
    // dropped one leaves a dialogue that does not say what is about to be
    // deleted, or does not say how much.
    "cleanup.confirm.title": 1, "cleanup.confirm.body": 2, "cleanup.failed": 1,
    "cleanup.refused": 1, "cleanup.logs.title": 1,
    // The size is the reason to press the button.
    "menu.maintenance.freeToolCache": 1, "menu.maintenance.freeActionCache": 1,
    "menu.maintenance.trimLogs": 1, "disk.toolCache": 1, "disk.actionCache": 1,
    "disk.checkout": 1, "disk.temporary": 1, "disk.other": 1, "disk.logs": 1,
    "disk.measuredAgo": 1,
    "menu.runnerVersion": 1, "menu.runnerVersion.update": 2,
  ]
  for language in ["en", "es"] {
    let catalogue = try catalogue(language)
    for (key, count) in expected {
      let format = try #require(catalogue[key])
      #expect(format.components(separatedBy: "%@").count == count + 1)
    }
  }
}

/// The conversion characters a format uses, in the order `String(format:)`
/// consumes its arguments. `%%` is a literal percent and takes none.
private func specifiers(in format: String) -> [Character] {
  // Flags, width, precision, positional index and length modifiers — everything
  // that may sit between the `%` and the letter saying what type is being read.
  let modifiers = Set("0123456789.$-+ #'hlLqjzt")
  var found: [Character] = []
  var index = format.startIndex
  while let percent = format[index...].firstIndex(of: "%") {
    index = format.index(after: percent)
    while index < format.endIndex, modifiers.contains(format[index]) {
      index = format.index(after: index)
    }
    guard index < format.endIndex else { break }
    if format[index] != "%" { found.append(format[index]) }
    index = format.index(after: index)
  }
  return found
}

@Test func everyTranslationTakesItsArgumentsInTheSameOrderAndTheSameTypes() throws {
  // `String(format:)` matches specifiers to arguments by position and checks
  // nothing. Counting `%@` is not enough on its own: `cleanup.logs.title` is
  // the first format in this app to mix a number with a string, and Spanish
  // word order makes reordering the two a plausible edit rather than a
  // hypothetical one. An Int read through `%@` is dereferenced as a pointer,
  // which is a crash and not a wrong line.
  //
  // Derived from the catalogues rather than from a list kept by hand, so a new
  // key is covered the day it is added.
  let english = try catalogue("en")
  let spanish = try catalogue("es")
  for (key, format) in english {
    let translated = try #require(spanish[key], "\(key)")
    #expect(specifiers(in: translated) == specifiers(in: format), "\(key)")
  }
  // And the one the call site fixes: a count, and then a path.
  #expect(specifiers(in: try #require(english["cleanup.logs.title"])) == ["d", "@"])
  // The helper itself, against the two shapes this app writes.
  #expect(specifiers(in: "%d%% of %@") == ["d", "@"])
  #expect(specifiers(in: "%dm %02ds") == ["d", "d"])
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
