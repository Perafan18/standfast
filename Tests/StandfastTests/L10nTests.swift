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

private func l10nSource() -> String {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = repository.appendingPathComponent("Sources/Standfast/L10n.swift")
  return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
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
    L10n.quit, L10n.controlCenter, L10n.settings, L10n.recentJobs, L10n.openAtLogin,
    L10n.openAtLoginFailed,
    L10n.openAtLoginNeedsApproval, L10n.openAtLoginUnavailable,
    L10n.notifyMe, L10n.notifyJobFailed, L10n.notifyDisconnected, L10n.notifyStopped,
    L10n.notificationsBlocked, L10n.preventSleep, L10n.preventSleepLidNotice,
    L10n.thermalSerious, L10n.thermalCritical, L10n.thermalSlowingJobs,
    L10n.notificationJobFailedTitle, L10n.notificationDisconnectedTitle,
    L10n.notificationStoppedTitle, L10n.notificationJobFailedBody("a", "b"),
    L10n.notificationDisconnectedBody("a"), L10n.notificationStoppedBody("a"),
    L10n.noRunnersFound, L10n.checkingRunners, L10n.launchAgentsUnreadable,
    L10n.someRunnersUnreadable,
    L10n.moreUnreadable,
    L10n.stateIdle, L10n.stateBusy, L10n.stateDisconnected, L10n.stateStopped,
    L10n.stateStarting, L10n.stateUnknownNoCLI, L10n.stateUnknownNotAuthenticated,
    L10n.stateUnknownNoAnswer, L10n.stateUnknownNoLocalAnswer,
    L10n.stateUnknownNoToken, L10n.stateUnknownRateLimited,
    L10n.queueWaitingOne, L10n.queueWaiting(2), L10n.queueWaitingPartial(2),
    L10n.queueEmpty, L10n.queueUnknownScope,
    L10n.settingsGitHub, L10n.settingsGitHubFooter, L10n.settingsGitHubStored,
    L10n.settingsGitHubAbsent, L10n.settingsGitHubUnreadable,
    L10n.settingsGitHubPlaceholder, L10n.settingsGitHubSave,
    L10n.settingsGitHubRemove, L10n.settingsGitHubKeychainFailed,
    L10n.stateReadyShort, L10n.stateRunningShort, L10n.stateDisconnectedShort,
    L10n.stateStoppedShort, L10n.stateStartingShort, L10n.stateUnknownShort,
    L10n.checkedJustNow, L10n.checkFailedThenChecked(L10n.checkedJustNow),
    L10n.checkedNever, L10n.jobSucceeded, L10n.jobFailed,
    L10n.jobCanceled, L10n.jobInterrupted,
    L10n.runnerRow("a", "b"), L10n.runnerInScope("a", "b"),
    L10n.quickMenuRunner("a", "b"), L10n.quickMenuRunnerInScope("a", "b", "c"),
    L10n.quickMenuScopeWithID("a", 1),
    L10n.jobRunning("a", "b"), L10n.jobRunningWithTypical("a", "b", "c"),
    L10n.jobRow("a", "b", "c"), L10n.jobRowNoDuration("a", "b"), L10n.checkedAgo("a"),
    L10n.durationHoursMinutes(1, 2), L10n.durationMinutesSeconds(1, 2),
    L10n.durationHours(1), L10n.durationMinutes(1), L10n.durationSeconds(1),
    L10n.maintenance, L10n.measureDiskUse, L10n.deletingOnlyWhenIdle,
    L10n.diskWorking, L10n.diskNotMeasured, L10n.diskMeasuredJustNow,
    L10n.diskUnavailable, L10n.cleanupDelete, L10n.cleanupCancel,
    L10n.cleanupToolCacheEffect, L10n.cleanupActionCacheEffect,
    L10n.diskToolCache("a"), L10n.diskActionCache("a"), L10n.diskCheckouts("a"),
    L10n.diskTemporary("a"), L10n.diskOther("a"), L10n.diskStandfastTrash("a"),
    L10n.diskLogs("a"), L10n.diskMeasuredAgo("a"), L10n.freeToolCache("a"),
    L10n.freeActionCache("a"), L10n.cleanStandfastTrash("a"),
    L10n.deleteOldLogs("a"), L10n.runnerVersion("a"),
    L10n.runnerVersionUnreadable,
    L10n.runnerVersionOutdated("a", "b"), L10n.cleanupConfirmTitle("a"),
    L10n.cleanupConfirmBody("a", "b"), L10n.cleanupStandfastTrashTitle("a"),
    L10n.cleanupStandfastTrashEffect, L10n.cleanupLogsTitle(1, "a"),
    L10n.cleanupLogsTitle(2, "a"), L10n.cleanupLogsEffect(1),
    L10n.cleanupLogsEffect(2), L10n.cleanupRefused("a"), L10n.cleanupFailed("a"),
    L10n.cleanupPartiallyFailed("a"),
    L10n.serviceConfirmStopTitle("a"), L10n.serviceConfirmRestartTitle("a"),
    L10n.serviceConfirmStopBusy("a", "b", "c"),
    L10n.serviceConfirmRestartBusy("a", "b", "c"),
    L10n.serviceConfirmStopUncertain("a", "b"),
    L10n.serviceConfirmRestartUncertain("a", "b"),
    L10n.serviceConfirmCancel(),
    L10n.serviceOperationInFlightTitle("a"), L10n.serviceOperationInFlightDetail("a"),
    L10n.serviceOperationAcceptedTitle("a"), L10n.serviceOperationAcceptedDetail("a"),
    L10n.serviceOperationTimedOutTitle("a"), L10n.serviceOperationTimedOutDetail("a"),
    L10n.serviceOperationScriptMissingTitle("a"),
    L10n.serviceOperationScriptMissingDetail("a"),
    L10n.serviceOperationCouldNotLaunchTitle("a"),
    L10n.serviceOperationCouldNotLaunchDetail("a"),
    L10n.serviceOperationUnexpectedFailureTitle("a"),
    L10n.serviceOperationUnexpectedFailureDetail("a"),
    L10n.serviceOperationConfirmationUnavailableTitle("a"),
    L10n.serviceOperationConfirmationUnavailableDetail("a"),
    L10n.serviceOperationRestartStartFailedTitle,
    L10n.serviceOperationRestartStartFailedDetail,
    L10n.serviceOperationRestartStartTimedOutTitle,
    L10n.serviceOperationRestartStartTimedOutDetail,
    L10n.statusItemLabel, L10n.controlCenterTitle,
    L10n.controlCenterNoRunnersDescription, L10n.controlCenterScope,
    L10n.controlCenterStatus, L10n.controlCenterService,
    L10n.openWorkflowRuns, L10n.openRunnerSettings,
    L10n.runnerAttention(1), L10n.runnerAttention(2), L10n.viewRuns(),
    L10n.viewSettings(), L10n.historyEmpty(), L10n.historyUnavailable(),
    L10n.maintenanceCompact(), L10n.foldCard, L10n.unfoldCard,
    L10n.serviceStart, L10n.serviceStop, L10n.serviceRestart,
    L10n.stateLayerRunningLocally, L10n.stateLayerGitHubSilent,
    L10n.stateLayerLocalUnreadable,
    L10n.startRunner("a"), L10n.stopRunner("a"),
    L10n.restartRunner("a"),
    L10n.settingsNotifications, L10n.settingsPower, L10n.settingsStartup,
    L10n.settingsNotificationsFooter, L10n.settingsPowerFooter,
    L10n.settingsStartupFooter, L10n.settingsVersion(" 0.5.0 (5)"),
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
      "menu.controlCenter", "menu.settings",
      "menu.refreshNow", "menu.quit", "menu.recentJobs", "menu.openAtLogin",
      "menu.openAtLogin.failed", "menu.openAtLogin.needsApproval",
      "menu.openAtLogin.unavailable", "menu.runnerRow", "menu.runnerInScope",
      "menu.quickRunner", "menu.quickRunnerScoped", "menu.quickRunnerScopeID",
      "menu.notify", "menu.notify.jobFailed", "menu.notify.disconnected",
      "menu.notify.stopped", "menu.notify.blocked", "menu.preventSleep",
      "menu.preventSleep.lid", "thermal.serious", "thermal.critical",
      "thermal.slowingJobs", "notification.jobFailed.title",
      "notification.jobFailed.body", "notification.disconnected.title",
      "notification.disconnected.body", "notification.stopped.title",
      "notification.stopped.body",
      "state.noRunners", "state.checking", "state.launchAgentsUnreadable",
      "state.unreadable",
      "state.unreadable.more", "state.idle",
      "state.busy", "state.disconnected", "state.stopped", "state.starting",
      "state.short.ready", "state.short.running", "state.short.disconnected",
      "state.short.stopped", "state.short.starting", "state.short.unknown",
      "state.unknown.noCLI", "state.unknown.notAuthenticated",
      "state.unknown.noAnswer", "state.unknown.noToken",
      "state.unknown.rateLimited",
      "queue.waiting.one", "queue.waiting", "queue.waitingPartial",
      "queue.empty", "queue.unknownScope", "state.unknown.noLocalAnswer",
      "state.checkedAgo",
      "state.checkedJustNow", "state.checkFailed", "state.checkedNever", "job.running",
      "job.runningWithTypical", "job.row", "job.rowNoDuration",
      "job.ageAndDuration",
      "job.result.succeeded", "job.result.failed", "job.result.canceled",
      "job.result.interrupted", "duration.hoursMinutes", "duration.minutesSeconds",
      "duration.days", "duration.hours", "duration.minutes", "duration.seconds",
      "menu.maintenance", "menu.maintenance.measure",
      "menu.maintenance.freeToolCache", "menu.maintenance.freeActionCache",
      "menu.maintenance.cleanStandfastTrash", "menu.maintenance.trimLogs",
      "menu.maintenance.onlyWhenIdle",
      "menu.runnerVersion", "menu.runnerVersion.unreadable", "menu.runnerVersion.update",
      "disk.toolCache", "disk.actionCache", "disk.checkout", "disk.temporary",
      "disk.other", "disk.standfastTrash", "disk.logs", "disk.working", "disk.notMeasured",
      "disk.measuredJustNow", "disk.measuredAgo", "disk.unavailable",
      "cleanup.confirm.title", "cleanup.confirm.body", "cleanup.confirm.delete",
      "cleanup.confirm.cancel", "cleanup.toolCache.effect",
      "cleanup.actionCache.effect", "cleanup.standfastTrash.title",
      "cleanup.standfastTrash.effect", "cleanup.logs.title.one", "cleanup.logs.title",
      "cleanup.logs.effect.one", "cleanup.logs.effect",
      "cleanup.confirmationUnavailable", "cleanup.checkoutNotOffered", "cleanup.refused",
      "cleanup.failed",
      "cleanup.partiallyFailed",
      "service.confirm.stop.title", "service.confirm.restart.title",
      "service.confirm.stop.busy", "service.confirm.restart.busy",
      "service.confirm.stop.uncertain", "service.confirm.restart.uncertain",
      "service.confirm.cancel",
      "operation.inFlight.title", "operation.inFlight.detail",
      "operation.accepted.title", "operation.accepted.detail",
      "operation.timedOut.title", "operation.timedOut.detail",
      "operation.scriptMissing.title", "operation.scriptMissing.detail",
      "operation.couldNotLaunch.title", "operation.couldNotLaunch.detail",
      "operation.unexpectedFailure.title", "operation.unexpectedFailure.detail",
      "operation.confirmationUnavailable.title",
      "operation.confirmationUnavailable.detail",
      "operation.restartStartFailed.title", "operation.restartStartFailed.detail",
      "operation.restartStartTimedOut.title", "operation.restartStartTimedOut.detail",
      "app.statusItem", "controlCenter.title", "controlCenter.noRunners.description",
      "controlCenter.scope", "controlCenter.status", "controlCenter.service",
      "controlCenter.openWorkflowRuns", "controlCenter.openRunnerSettings",
      "controlCenter.attention.one", "controlCenter.attention",
      "controlCenter.viewRuns", "controlCenter.viewSettings",
      "controlCenter.history.empty", "controlCenter.history.unavailable",
      "controlCenter.maintenance.compact", "controlCenter.fold",
      "controlCenter.service.start", "controlCenter.service.stop",
      "controlCenter.service.restart", "state.layer.runningLocally",
      "state.layer.gitHubSilent", "state.layer.localUnreadable",
      "controlCenter.unfold", "controlCenter.action.start",
      "controlCenter.action.stop", "controlCenter.action.restart",
      "settings.notifications", "settings.power", "settings.startup",
      "settings.notifications.footer", "settings.power.footer",
      "settings.startup.footer", "settings.version",
      "settings.github", "settings.github.footer", "settings.github.stored",
      "settings.github.absent", "settings.github.unreadable",
      "settings.github.placeholder", "settings.github.save",
      "settings.github.remove", "settings.github.keychainFailed",
    ])
  #expect(everyKey == reached)
}

@Test func confirmationUnavailableFeedbackHasEnglishSpanishAndFallbackParity() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.serviceOperationConfirmationUnavailableTitle(
      "Stop", in: [english]) == "Stop confirmation unavailable")
  #expect(
    L10n.serviceOperationConfirmationUnavailableDetail(
      "Stop", in: [english])
      == "Open the Standfast Control Center, then try Stop again.")
  #expect(
    L10n.serviceOperationConfirmationUnavailableTitle(
      "Detener", in: [spanish]) == "Confirmación de Detener no disponible")
  #expect(
    L10n.serviceOperationConfirmationUnavailableDetail(
      "Detener", in: [spanish])
      == "Abre el Centro de control de Standfast y luego prueba Detener otra vez.")
  #expect(
    L10n.serviceOperationConfirmationUnavailableTitle(
      "Stop", in: []) == "Stop confirmation unavailable")
  #expect(
    L10n.serviceOperationConfirmationUnavailableDetail(
      "Stop", in: [])
      == "Open the Standfast Control Center, then try Stop again.")
}

@Test func obsoleteFleetOverflowLocalizationIsAbsentEverywhere() throws {
  let forbiddenKeys: Set<String> = [
    "menu.fleet", "menu.fleetOverflow", "menu.moreRunners.one",
    "menu.moreRunners",
  ]
  let forbiddenSymbols = ["quickMenuFleet", "quickMenuMoreRunners"]

  #expect(forbiddenKeys.isDisjoint(with: L10n.english.keys))
  for language in ["en", "es"] {
    #expect(forbiddenKeys.isDisjoint(with: try catalogue(language).keys))
  }
  for symbol in forbiddenSymbols {
    #expect(!l10nSource().contains(symbol))
  }
}

@Test func checkingRunnerCopyIsAtomicInEnglishSpanishAndFallback() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(L10n.t("state.checking", in: [english]) == "Checking runners")
  #expect(L10n.t("state.checking", in: [spanish]) == "Consultando runners")
  #expect(L10n.t("state.checking", in: []) == "Checking runners")
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

@Test func settingsPermanentCopyAndVersionFormatAreExactInBothLanguages() throws {
  let english = try catalogue("en")
  let spanish = try catalogue("es")

  #expect(
    english["settings.notifications.footer"]
      == "Alerts use system notifications.")
  #expect(
    english["settings.power.footer"]
      == "Closing the lid still puts this Mac to sleep.")
  #expect(
    english["settings.startup.footer"]
      == "Standfast can open automatically when you log in.")
  #expect(english["settings.version"] == "Standfast%@")

  #expect(
    spanish["settings.notifications.footer"]
      == "Las alertas usan las notificaciones del sistema.")
  #expect(
    spanish["settings.power.footer"]
      == "Cerrar la tapa la sigue durmiendo.")
  #expect(
    spanish["settings.startup.footer"]
      == "Standfast puede abrirse automáticamente al iniciar sesión.")
  #expect(spanish["settings.version"] == "Standfast%@")

  #expect(
    L10n.settingsVersion(" 0.5.0 (5)", in: [try speaking("en")])
      == "Standfast 0.5.0 (5)")
  #expect(
    L10n.settingsVersion(" 0.5.0 (5)", in: [try speaking("es")])
      == "Standfast 0.5.0 (5)")
}

@Test func cataloguesNeverMapAKeyToItself() throws {
  let rawKeyPattern = #"(^| — )(menu|state|job|duration|thermal|notification)\."#
  for language in ["en", "es"] {
    let entries = try catalogue(language)
    for (key, value) in entries {
      #expect(value != key, "\(language): \(key)")
      #expect(
        value.range(of: rawKeyPattern, options: .regularExpression) == nil,
        "\(language): \(key) → \(value)")
    }
  }
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

@Test func oneOldLogUsesTheSingularInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.cleanupLogsTitle(1, "/tmp/runner", in: [english])
      == "Delete 1 old log file from /tmp/runner?")
  #expect(
    L10n.cleanupLogsEffect(1, in: [english])
      == "1 file nothing has written to in over a week. The log the runner is "
      + "writing now is never deleted, and neither is the history shown in the "
      + "Standfast Control Center.")
  #expect(
    L10n.cleanupLogsTitle(1, "/tmp/runner", in: [spanish])
      == "¿Borrar 1 archivo de log antiguo de /tmp/runner?")
  #expect(
    L10n.cleanupLogsEffect(1, in: [spanish])
      == "1 archivo en el que nadie escribe desde hace más de una semana. El log que "
      + "el runner está escribiendo ahora nunca se borra, ni tampoco el historial que "
      + "muestra el Centro de control de Standfast.")
}

@Test func pluralLogCleanupAlsoNamesTheControlCenterInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.cleanupLogsEffect(4, in: [english])
      == "4 files nothing has written to in over a week. The log the runner is "
      + "writing now is never deleted, and neither is the history shown in the "
      + "Standfast Control Center.")
  #expect(
    L10n.cleanupLogsEffect(4, in: [spanish])
      == "4 archivos en los que nadie escribe desde hace más de una semana. El log "
      + "que el runner está escribiendo ahora nunca se borra, ni tampoco el historial "
      + "que muestra el Centro de control de Standfast.")
}

@Test func premiumCompactVocabularyIsExactInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(L10n.t("state.short.ready", in: [english]) == "Ready")
  #expect(L10n.t("state.short.running", in: [english]) == "Running")
  #expect(L10n.t("state.short.disconnected", in: [english]) == "Disconnected")
  #expect(L10n.t("state.short.stopped", in: [english]) == "Stopped")
  #expect(L10n.t("state.short.starting", in: [english]) == "Starting")
  #expect(L10n.t("state.short.unknown", in: [english]) == "Unknown")
  #expect(L10n.t("state.short.ready", in: [spanish]) == "Listo")
  #expect(L10n.t("state.short.running", in: [spanish]) == "Ejecutando")
  #expect(L10n.t("state.short.disconnected", in: [spanish]) == "Desconectado")
  #expect(L10n.t("state.short.stopped", in: [spanish]) == "Detenido")
  #expect(L10n.t("state.short.starting", in: [spanish]) == "Arrancando")
  #expect(L10n.t("state.short.unknown", in: [spanish]) == "Desconocido")

  #expect(L10n.runnerAttention(1, in: [english]) == "1 runner needs attention")
  #expect(L10n.runnerAttention(3, in: [english]) == "3 runners need attention")
  #expect(L10n.runnerAttention(1, in: [spanish]) == "1 runner requiere atención")
  #expect(L10n.runnerAttention(3, in: [spanish]) == "3 runners requieren atención")
  #expect(L10n.viewRuns(in: [english]) == "View runs")
  #expect(L10n.viewRuns(in: [spanish]) == "Ver ejecuciones")
  #expect(L10n.viewSettings(in: [english]) == "View settings")
  #expect(L10n.viewSettings(in: [spanish]) == "Ver configuración")
  #expect(L10n.historyEmpty(in: [english]) == "No jobs recorded")
  #expect(L10n.historyEmpty(in: [spanish]) == "Sin trabajos registrados")
  #expect(L10n.historyUnavailable(in: [english]) == "Job history unavailable")
  #expect(L10n.historyUnavailable(in: [spanish]) == "Historial no disponible")
  #expect(L10n.maintenanceCompact(in: [english]) == "Not measured")
  #expect(L10n.maintenanceCompact(in: [spanish]) == "Sin medir")
  #expect(L10n.startRunner("build-mac", in: [english]) == "Start build-mac")
  #expect(L10n.startRunner("build-mac", in: [spanish]) == "Arrancar build-mac")
  #expect(L10n.stopRunner("build-mac", in: [english]) == "Stop build-mac")
  #expect(L10n.stopRunner("build-mac", in: [spanish]) == "Parar build-mac")
  #expect(L10n.restartRunner("build-mac", in: [english]) == "Restart build-mac")
  #expect(L10n.restartRunner("build-mac", in: [spanish]) == "Reiniciar build-mac")
}

@Test func disruptiveServiceConfirmationCopyIsExactInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(L10n.serviceConfirmStopTitle("build-mac", in: [english]) == "Stop build-mac?")
  #expect(
    L10n.serviceConfirmRestartTitle("build-mac", in: [spanish])
      == "¿Reiniciar build-mac?")
  #expect(
    L10n.serviceConfirmStopBusy(
      "build-mac", "acme/widget", "testflight", in: [english])
      == "build-mac in acme/widget is running “testflight”. "
      + "Stopping it interrupts this job.")
  #expect(
    L10n.serviceConfirmRestartBusy(
      "build-mac", "acme/widget", "testflight", in: [spanish])
      == "build-mac en acme/widget está ejecutando “testflight”. "
      + "Reiniciarlo interrumpe este job. Si Arrancar falla después de Parar, "
      + "el runner puede quedar detenido.")
  #expect(
    L10n.serviceConfirmStopUncertain("build-mac", "acme/widget", in: [spanish])
      == "build-mac en acme/widget puede tener trabajo en curso. "
      + "Pararlo puede interrumpir ese trabajo.")
  #expect(
    L10n.serviceConfirmRestartUncertain(
      "build-mac", "acme/widget", in: [english])
      == "build-mac in acme/widget may have work in progress. "
      + "Restarting can interrupt that work. If Start fails after Stop, the runner "
      + "can remain stopped.")
  #expect(L10n.serviceConfirmCancel(in: [english]) == "Cancel")
  #expect(L10n.serviceConfirmCancel(in: [spanish]) == "Cancelar")
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

@Test func quickMenuRunnerIdentityFormatsAreExactInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.quickMenuRunner("build-mac", "Ready", in: [english])
      == "build-mac · Ready")
  #expect(
    L10n.quickMenuRunnerInScope(
      "mac-mini-m4", "nest-rules-app", "Ready", in: [english])
      == "mac-mini-m4 · nest-rules-app · Ready")
  #expect(
    L10n.quickMenuRunnerInScope(
      "mac-mini-m4", "acme/standfast", "Running", in: [english])
      == "mac-mini-m4 · acme/standfast · Running")
  #expect(
    L10n.quickMenuScopeWithID("acme/standfast", 123, in: [english])
      == "acme/standfast · #123")
  #expect(
    L10n.quickMenuRunnerInScope(
      "mac-mini-m4", "acme/standfast", "Ejecutando", in: [spanish])
      == "mac-mini-m4 · acme/standfast · Ejecutando")
}

@Test func everyFormatKeepsThePlaceholdersItsCallSitePasses() throws {
  // A translation that dropped one silently erases whichever fact it stood for
  // — the job's name, how long it has been going, or what it usually takes —
  // and `String(format:)` will not say a word about it.
  let expected = [
    "job.running": 2, "job.runningWithTypical": 3, "job.row": 3,
    "job.rowNoDuration": 2, "job.ageAndDuration": 2, "state.checkedAgo": 1,
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
    "cleanup.partiallyFailed": 1, "cleanup.refused": 1,
    "cleanup.standfastTrash.title": 1, "cleanup.logs.title": 1,
    // The size is the reason to press the button.
    "menu.maintenance.freeToolCache": 1, "menu.maintenance.freeActionCache": 1,
    "menu.maintenance.cleanStandfastTrash": 1, "menu.maintenance.trimLogs": 1,
    "disk.toolCache": 1, "disk.actionCache": 1,
    "disk.checkout": 1, "disk.temporary": 1, "disk.other": 1,
    "disk.standfastTrash": 1, "disk.logs": 1,
    "disk.measuredAgo": 1,
    "menu.runnerVersion": 1, "menu.runnerVersion.update": 2,
    "menu.quickRunner": 2, "menu.quickRunnerScoped": 3,
    "menu.quickRunnerScopeID": 1,
    "operation.inFlight.title": 1, "operation.inFlight.detail": 1,
    "operation.accepted.title": 1, "operation.accepted.detail": 1,
    "operation.timedOut.title": 1, "operation.timedOut.detail": 1,
    "operation.scriptMissing.title": 1, "operation.scriptMissing.detail": 1,
    "operation.couldNotLaunch.title": 1, "operation.couldNotLaunch.detail": 1,
    "operation.unexpectedFailure.title": 1, "operation.unexpectedFailure.detail": 1,
    "operation.confirmationUnavailable.title": 1,
    "operation.confirmationUnavailable.detail": 1,
    "controlCenter.action.start": 1, "controlCenter.action.stop": 1,
    "controlCenter.action.restart": 1,
    "service.confirm.stop.title": 1, "service.confirm.restart.title": 1,
    "service.confirm.stop.busy": 3, "service.confirm.restart.busy": 3,
    "service.confirm.stop.uncertain": 2,
    "service.confirm.restart.uncertain": 2,
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
