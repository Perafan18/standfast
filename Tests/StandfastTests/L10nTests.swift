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
    L10n.someRunnersUnreadable, L10n.launchAgentsUnreadableTitle,
    L10n.someRunnersUnreadableTitle,
    L10n.moreUnreadable,
    L10n.stateIdle, L10n.stateBusy, L10n.stateDisconnected, L10n.stateStopped,
    L10n.stateStarting, L10n.stateUnknownNoCLI, L10n.stateUnknownNotAuthenticated,
    L10n.stateUnknownNoAnswer, L10n.stateUnknownNoLocalAnswer,
    L10n.stateUnknownManagedFleetWaiting, L10n.stateUnknownManagedFleetUnavailable,
    L10n.stateUnknownNoToken, L10n.stateUnknownRateLimited,
    L10n.stateUnknownGitLabNoToken, L10n.stateUnknownGitLabNotAuthenticated,
    L10n.stateUnknownGitLabRateLimited, L10n.stateUnknownGitLabSilent,
    L10n.stateLayerGitLabNotAsked, L10n.stateLayerGitLabRefusedToken,
    L10n.stateLayerGitLabRateLimited, L10n.stateLayerGitLabSilent,
    L10n.stateLayerManagedFleetWaiting, L10n.stateLayerManagedFleetUnavailable,
    L10n.queueWaitingOne, L10n.queueWaiting(2), L10n.queueWaitingPartial(2),
    L10n.queueEmpty, L10n.queueUnknownScope,
    L10n.settingsRunners, L10n.settingsRunnersFooter, L10n.settingsRunnersNone,
    L10n.settingsRunnersAdd, L10n.settingsRunnersRemove("a"),
    L10n.settingsGitLab, L10n.settingsGitLabFooter, L10n.settingsGitLabStored,
    L10n.settingsGitLabAbsent, L10n.settingsGitLabPlaceholder,
    L10n.runnerManagedFleet,
    L10n.managedJobOpen, L10n.managedRunOpen,
    L10n.managedPROpen(702), L10n.managedJobNoPR("push"),
    L10n.settingsGitHub, L10n.settingsGitHubFooter, L10n.settingsGitHubStored,
    L10n.settingsGitHubAbsent, L10n.settingsGitHubUnreadable,
    L10n.settingsGitHubPlaceholder, L10n.settingsGitHubSave,
    L10n.settingsGitHubRemove, L10n.settingsGitHubKeychainFailed,
    L10n.stateReadyShort, L10n.stateRunningShort, L10n.stateDisconnectedShort,
    L10n.stateStoppedShort, L10n.stateStartingShort,
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
    L10n.diskUnavailable, L10n.diskOutsideRunner, L10n.diskManagedFleet,
    L10n.cleanupDelete, L10n.cleanupCancel,
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
    L10n.cleanupPartiallyFailed("a"), L10n.cleanupUnconfirmed("a"),
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
    L10n.controlCenterNoRunnersDescription, L10n.controlCenterInstallGuide,
    L10n.controlCenterScope,
    L10n.controlCenterStatus, L10n.controlCenterService,
    L10n.openWorkflowRuns, L10n.openRunnerSettings,
    L10n.runnerAttention(1), L10n.runnerAttention(2), L10n.viewRuns(),
    L10n.viewSettings(), L10n.historyEmpty(), L10n.historyUnavailable(),
    L10n.maintenanceCompact(),
    L10n.serviceStart, L10n.serviceStop, L10n.serviceRestart,
    L10n.stateLayerRunningLocally, L10n.stateLayerGitHubSilent,
    L10n.stateLayerLocalUnreadable,
    L10n.startRunner("a"), L10n.stopRunner("a"),
    L10n.restartRunner("a"),
    L10n.settingsNotifications, L10n.settingsPower, L10n.settingsStartup,
    L10n.settingsNotificationsFooter, L10n.settingsPowerFooter,
    L10n.settingsStartupFooter, L10n.settingsVersion(" 0.5.0 (5)"),
    L10n.settingsGitHubKeychainRemoveFailed,
    L10n.diskGitLabService, L10n.openGitLab,
    L10n.stateDisconnectedGitLab, L10n.notificationDisconnectedGitLabBody("a"),
    L10n.stateUnknownNoLocalAnswerProcess,
    L10n.stateUnknownGitLabPaused, L10n.stateLayerGitLabPaused,
    L10n.settingsGitLabInsecure,
    L10n.controlCenterThisMac, L10n.controlCenterFleetSupervisor, L10n.gitHub,
    L10n.gitLab, L10n.layerLocalRunning, L10n.layerLocalNotRunning,
    L10n.layerLocalStarting, L10n.layerRemoteOnline, L10n.layerRemoteBusy,
    L10n.layerRemoteOffline, L10n.layerRemoteWaitingToAppear,
    L10n.layerRemoteNotAskedStopped, L10n.layerRemoteNotAsked, L10n.managedFleet,
    L10n.settingsTabGeneral, L10n.settingsTabRunners, L10n.settingsTabAccounts,
    L10n.settingsToken, L10n.controlCenterOverview, L10n.controlCenterWaiting,
    L10n.controlCenterCurrentJob, L10n.controlCenterLastAction,
    L10n.controlCenterNeedsAttention, L10n.controlCenterDiscovery,
    L10n.controlCenterAllRunners, L10n.controlCenterDetails,
    L10n.controlCenterLayersValue("a", "b", "c", "d"),
    L10n.runnerMenu, L10n.showLogsInFinder, L10n.menuItemStartService,
    L10n.menuItemStopService, L10n.menuItemRestartService, L10n.menuItemViewRuns,
    L10n.menuItemViewSettings, L10n.menuItemOpenGitLab, L10n.menuItemOpenInBrowser,
    L10n.menuItemShowLogsInFinder, L10n.menuItemCopyName, L10n.menuItemRefreshNow,
    L10n.menuItemOpenJob, L10n.menuItemOpenRun, L10n.menuItemOpenPR(702),
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
      "state.unreadable", "state.launchAgentsUnreadable.title", "state.unreadable.title",
      "state.unreadable.more", "state.idle",
      "state.busy", "state.disconnected", "state.stopped", "state.starting",
      "state.short.ready", "state.short.running", "state.short.disconnected",
      "state.short.stopped", "state.short.starting",
      "state.unknown.noCLI", "state.unknown.notAuthenticated",
      "state.unknown.noAnswer", "state.unknown.noToken",
      "state.unknown.rateLimited",
      "state.unknown.managedFleetWaiting", "state.unknown.managedFleetUnavailable",
      "state.unknown.gitLabNoToken", "state.unknown.gitLabNotAuthenticated",
      "state.unknown.gitLabRateLimited", "state.unknown.gitLabSilent",
      "state.layer.gitLabNotAsked", "state.layer.gitLabRefusedToken",
      "state.layer.gitLabRateLimited", "state.layer.gitLabSilent",
      "state.layer.managedFleetWaiting", "state.layer.managedFleetUnavailable",
      "state.unknown.tokenRefused", "state.layer.gitHubRefusedToken",
      "state.unknown.tokenUnreadable", "state.unknown.gitLabTokenUnreadable",
      "state.unknown.gitLabInsecure",
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
      "disk.measuredJustNow", "disk.measuredAgo", "disk.unavailable", "disk.outsideRunner",
      "disk.managedFleet",
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
      "controlCenter.installGuide", "controlCenter.noRunners.manual",
      "controlCenter.scope", "controlCenter.scope.explained",
      "controlCenter.history.latest", "controlCenter.status", "controlCenter.service",
      "controlCenter.openWorkflowRuns", "controlCenter.openRunnerSettings",
      "controlCenter.attention.one", "controlCenter.attention",
      "controlCenter.viewRuns", "controlCenter.viewSettings",
      "controlCenter.history.empty", "controlCenter.history.unavailable",
      "controlCenter.maintenance.compact",
      "controlCenter.service.start", "controlCenter.service.stop",
      "controlCenter.service.restart", "state.layer.runningLocally", "runner.startedByHand",
      "runner.gitLabService", "runner.managedFleet",
      "managedJob.open", "managedJob.openRun", "managedJob.openPR", "managedJob.noPR",
      "state.layer.gitHubSilent", "state.layer.gitHubNotAsked",
      "state.layer.gitHubRateLimited", "state.layer.localUnreadable",
      "controlCenter.action.start",
      "controlCenter.action.stop", "controlCenter.action.restart",
      "settings.notifications", "settings.power", "settings.startup",
      "settings.notifications.footer", "settings.power.footer",
      "settings.startup.footer", "settings.version",
      "settings.appearance", "settings.appearance.footer", "settings.showInDock",
      "settings.runners", "settings.runners.footer", "settings.runners.none",
      "settings.runners.add", "settings.runners.remove",
      "settings.gitlab", "settings.gitlab.footer", "settings.gitlab.stored",
      "settings.gitlab.absent", "settings.gitlab.placeholder",
      "settings.github", "settings.github.footer", "settings.github.stored",
      "settings.github.absent", "settings.github.unreadable",
      "settings.github.placeholder", "settings.github.save",
      "settings.github.remove", "settings.github.keychainFailed",
      "cleanup.unconfirmed",
      "menu.openAtLogin.needsApproval.extensions",
      "menu.openAtLogin.unavailable.extensions",
      "settings.github.keychainRemoveFailed",
      "disk.gitLabService", "controlCenter.openGitLab",
      "state.disconnected.gitLab", "notification.disconnected.body.gitLab",
      "state.unknown.noLocalAnswer.process",
      "state.unknown.gitLabPaused", "state.layer.gitLabPaused",
      "settings.gitlab.insecure",
      "controlCenter.thisMac", "controlCenter.fleetSupervisor",
      "controlCenter.group.gitHub", "controlCenter.group.gitLab",
      "layer.local.running", "layer.local.notRunning", "layer.local.starting",
      "layer.remote.online", "layer.remote.busy", "layer.remote.offline",
      "layer.remote.waitingToAppear", "layer.remote.notAskedStopped",
      "layer.remote.notAsked", "controlCenter.group.managedFleet",
      "settings.tab.general", "settings.tab.runners", "settings.tab.accounts",
      "settings.token", "controlCenter.overview", "controlCenter.waiting",
      "controlCenter.currentJob", "controlCenter.lastAction",
      "controlCenter.needsAttention", "controlCenter.discovery",
      "controlCenter.allRunners", "controlCenter.details", "controlCenter.layers.value",
      "controlCenter.runnerMenu", "controlCenter.showLogs", "menuItem.startService",
      "menuItem.stopService", "menuItem.restartService", "menuItem.viewRuns",
      "menuItem.viewSettings", "menuItem.openGitLab", "menuItem.openInBrowser",
      "menuItem.showLogsInFinder", "menuItem.copyName", "menuItem.refreshNow",
      "menuItem.openJob", "menuItem.openRun", "menuItem.openPR",
      "controlCenter.runnerCount.one", "controlCenter.runnerCount", "runner.identity",
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
      == "Open Standfast, then try Stop again.")
  #expect(
    L10n.serviceOperationConfirmationUnavailableTitle(
      "Detener", in: [spanish]) == "Confirmación de Detener no disponible")
  #expect(
    L10n.serviceOperationConfirmationUnavailableDetail(
      "Detener", in: [spanish])
      == "Abre Standfast y luego prueba Detener otra vez.")
  #expect(
    L10n.serviceOperationConfirmationUnavailableTitle(
      "Stop", in: []) == "Stop confirmation unavailable")
  #expect(
    L10n.serviceOperationConfirmationUnavailableDetail(
      "Stop", in: [])
      == "Open Standfast, then try Stop again.")
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
      == "Aun así, cerrar la tapa pone esta Mac en reposo.")
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
      + "writing now is never deleted, and neither is the history Standfast shows.")
  #expect(
    L10n.cleanupLogsTitle(1, "/tmp/runner", in: [spanish])
      == "¿Borrar 1 archivo de log antiguo de /tmp/runner?")
  #expect(
    L10n.cleanupLogsEffect(1, in: [spanish])
      == "1 archivo en el que nadie escribe desde hace más de una semana. El log que "
      + "el runner está escribiendo ahora nunca se borra, ni tampoco el historial que "
      + "muestra Standfast.")
}

@Test func pluralLogCleanupAlsoNamesWhereTheHistoryIsShownInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.cleanupLogsEffect(4, in: [english])
      == "4 files nothing has written to in over a week. The log the runner is "
      + "writing now is never deleted, and neither is the history Standfast shows.")
  #expect(
    L10n.cleanupLogsEffect(4, in: [spanish])
      == "4 archivos en los que nadie escribe desde hace más de una semana. El log "
      + "que el runner está escribiendo ahora nunca se borra, ni tampoco el historial "
      + "que muestra Standfast.")
}

@Test func aRefusalNobodyCouldConfirmNamesNoJobInEitherLanguage() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.t("cleanup.unconfirmed", in: [english])
      == "Cleanup stopped: could not confirm that %@ is idle or stopped")
  #expect(
    L10n.t("cleanup.unconfirmed", in: [spanish])
      == "La limpieza se detuvo: no se pudo confirmar que %@ esté inactivo o detenido")
}

@Test func aCappedQueueCountReadsCorrectlyForOneJobInBothLanguages() throws {
  // A partial reading with a single match is ordinary: more than ten queued
  // runs and one of them for this Mac. "1 trabajos o más" is what the plural
  // format used to make of it.
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(
    L10n.queueWaitingPartial(1, in: [english])
      == "1 or more jobs are waiting for this machine")
  #expect(
    L10n.queueWaitingPartial(1, in: [spanish])
      == "1 o más trabajos esperando a esta máquina")
  #expect(
    L10n.queueWaitingPartial(3, in: [spanish])
      == "3 o más trabajos esperando a esta máquina")
}

@Test func premiumCompactVocabularyIsExactInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")

  #expect(L10n.t("state.short.ready", in: [english]) == "Ready")
  #expect(L10n.t("state.short.running", in: [english]) == "Running")
  #expect(L10n.t("state.short.disconnected", in: [english]) == "Disconnected")
  #expect(L10n.t("state.short.stopped", in: [english]) == "Stopped")
  #expect(L10n.t("state.short.starting", in: [english]) == "Starting")
  #expect(L10n.t("state.short.ready", in: [spanish]) == "Listo")
  #expect(L10n.t("state.short.running", in: [spanish]) == "Ejecutando")
  #expect(L10n.t("state.short.disconnected", in: [spanish]) == "Desconectado")
  #expect(L10n.t("state.short.stopped", in: [spanish]) == "Detenido")
  #expect(L10n.t("state.short.starting", in: [spanish]) == "Arrancando")
  // The unknown states no longer share a badge: each names the layer that
  // went quiet, in the same words its long sentence uses.
  #expect(L10n.t("state.layer.gitHubSilent", in: [english]) == "GitHub not answering")
  #expect(L10n.t("state.layer.gitHubNotAsked", in: [english]) == "GitHub not asked")
  #expect(
    L10n.t("state.layer.gitHubRateLimited", in: [english])
      == "GitHub rate limit reached")
  #expect(
    L10n.t("state.layer.localUnreadable", in: [english]) == "Local service unreadable")
  #expect(L10n.t("state.layer.gitHubSilent", in: [spanish]) == "GitHub sin respuesta")
  #expect(L10n.t("state.layer.gitHubNotAsked", in: [spanish]) == "GitHub sin consultar")
  #expect(
    L10n.t("state.layer.gitHubRateLimited", in: [spanish])
      == "Límite de GitHub alcanzado")
  #expect(
    L10n.t("state.layer.localUnreadable", in: [spanish])
      == "No se pudo leer el servicio local")

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

@Test func theLayerRowsAreExactInBothLanguages() throws {
  let english = try catalogue("en")
  let spanish = try catalogue("es")
  let rows = [
    ("controlCenter.thisMac", "This Mac", "Esta Mac"),
    ("controlCenter.fleetSupervisor", "Fleet supervisor", "Supervisor del fleet"),
    ("controlCenter.group.gitHub", "GitHub", "GitHub"),
    ("controlCenter.group.gitLab", "GitLab", "GitLab"),
    ("controlCenter.group.managedFleet", "Managed Fleet", "Fleet gestionado"),
    ("layer.local.running", "Running", "En marcha"),
    ("layer.local.notRunning", "Not running", "Detenido"),
    ("layer.local.starting", "Starting", "Arrancando"),
    ("layer.remote.online", "Online, waiting for jobs", "En línea, esperando trabajos"),
    ("layer.remote.busy", "Online, running a job", "En línea, ejecutando un trabajo"),
    ("layer.remote.offline", "Offline", "Sin conexión"),
    ("layer.remote.waitingToAppear", "Waiting to appear", "Esperando a aparecer"),
    (
      "layer.remote.notAskedStopped", "Not asked while stopped",
      "Sin consultar mientras está detenido"
    ),
    ("layer.remote.notAsked", "Not asked", "Sin consultar"),
  ]
  for (key, en, es) in rows {
    #expect(english[key] == en, "en/\(key)")
    #expect(spanish[key] == es, "es/\(key)")
  }
  // `Ejecutando` means on a job, which a live process alone does not claim.
  #expect(spanish["layer.local.running"] != spanish["state.short.running"])
  // Named as the line sending somebody to check the supervisor names it.
  for pack in [english, spanish] {
    let supervisor = try #require(pack["controlCenter.fleetSupervisor"]).lowercased()
    let remedy = try #require(pack["state.unknown.managedFleetUnavailable"])
    #expect(remedy.contains(supervisor))
  }
  // The spec wrote "Supervisor de la flota". Every Spanish line about the fleet
  // already says "fleet", and a window saying both reads as two things, so the
  // new rows say it too. Switch them all in one change, or none.
  let flota = #"\bflotas?\b"#
  for (key, value) in spanish {
    let found = value.range(of: flota, options: [.regularExpression, .caseInsensitive])
    #expect(found == nil, "es/\(key)")
  }
}

@Test func theOverviewIsExactInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")
  let headings = [
    ("controlCenter.needsAttention", "Needs Attention", "Requiere atención"),
    ("controlCenter.discovery", "Discovery", "Detección"),
    ("controlCenter.allRunners", "All Runners", "Todos los runners"),
    ("controlCenter.details", "Details…", "Detalles…"),
  ]
  for (key, en, es) in headings {
    #expect(L10n.t(key, in: [english]) == en, "en/\(key)")
    #expect(L10n.t(key, in: [spanish]) == es, "es/\(key)")
  }
  // Each reading after its own layer's name, in the order the columns draw
  // them. A format that dropped a name leaves "Running. Offline", and nobody
  // listening can tell which half is down.
  #expect(
    L10n.controlCenterLayersValue("This Mac", "Running", "GitHub", "Offline", in: [english])
      == "This Mac: Running. GitHub: Offline")
  #expect(
    L10n.controlCenterLayersValue(
      "Esta Mac", "En marcha", "GitLab", "Sin conexión", in: [spanish])
      == "Esta Mac: En marcha. GitLab: Sin conexión")
  #expect(
    L10n.controlCenterLayersValue("This Mac", "Running", "GitHub", "Offline", in: [])
      == "This Mac: Running. GitHub: Offline")
}

@Test func theRunnerDetailsHeadingsShareOneCapitalisation() throws {
  // Title case in English, as the Overview's headings are. "Recent jobs" sat
  // between "Current Job" and "Maintenance", and a grouped form on macOS 26
  // no longer upper-cases its headers, so the mismatch showed as written.
  let english = try speaking("en")
  let spanish = try speaking("es")
  let headings = [
    ("controlCenter.status", "Status", "Estado"),
    ("controlCenter.lastAction", "Last Action", "Última acción"),
    ("controlCenter.currentJob", "Current Job", "Trabajo actual"),
    ("menu.recentJobs", "Recent Jobs", "Trabajos recientes"),
    ("menu.maintenance", "Maintenance", "Mantenimiento"),
  ]
  for (key, en, es) in headings {
    #expect(L10n.t(key, in: [english]) == en, "en/\(key)")
    #expect(L10n.t(key, in: [spanish]) == es, "es/\(key)")
    #expect(L10n.t(key, in: []) == en, "fallback/\(key)")
  }
}

@Test func theRunnerMenusOwnLinesAreExactInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")
  // Title case in English, as the HIG asks of a menu item: the Runner menu,
  // a sidebar row's context menu and the quick menu. Spanish menus keep
  // sentence case, so their lines read as they did.
  let lines = [
    ("controlCenter.runnerMenu", "Runner", "Runner"),
    ("menuItem.startService", "Start Service", "Arrancar servicio"),
    ("menuItem.stopService", "Stop Service", "Parar servicio"),
    ("menuItem.restartService", "Restart Service", "Reiniciar servicio"),
    ("menuItem.viewRuns", "View Runs", "Ver ejecuciones"),
    ("menuItem.viewSettings", "View Settings", "Ver configuración"),
    ("menuItem.openGitLab", "Open GitLab", "Abrir GitLab"),
    ("menuItem.openInBrowser", "Open in Browser", "Abrir en el navegador"),
    ("menuItem.showLogsInFinder", "Show Logs in Finder", "Mostrar los logs en el Finder"),
    ("menuItem.copyName", "Copy Name", "Copiar nombre"),
    ("menuItem.refreshNow", "Refresh Now", "Actualizar ahora"),
    ("menuItem.openJob", "Open Job on GitHub", "Abrir job en GitHub"),
    (
      "menuItem.openRun", "Open Workflow Run on GitHub",
      "Abrir ejecución del workflow en GitHub"
    ),
    ("menuItem.openPR", "Open PR #%d on GitHub", "Abrir PR #%d en GitHub"),
  ]
  for (key, en, es) in lines {
    #expect(L10n.t(key, in: [english]) == en, "en/\(key)")
    #expect(L10n.t(key, in: [spanish]) == es, "es/\(key)")
    #expect(L10n.t(key, in: []) == en, "fallback/\(key)")
  }
  // The Maintenance rows beside Show logs say "Logs" and "Borrar los logs
  // antiguos"; a button saying "registros" would read as another folder.
  let logLines = try catalogue("es").filter {
    $0.key.localizedCaseInsensitiveContains("logs")
  }
  #expect(logLines.keys.contains("controlCenter.showLogs"))
  #expect(logLines.keys.contains("menuItem.showLogsInFinder"))
  #expect(logLines.keys.contains("menu.maintenance.trimLogs"))
  for (key, value) in logLines {
    let named = value.range(
      of: #"\blogs?\b"#, options: [.regularExpression, .caseInsensitive])
    #expect(named != nil, "es/\(key)")
  }
}

/// Whether an English line is in the HIG's title case: every word capitalised
/// except articles, coordinating conjunctions and short prepositions, which
/// are lower case unless first or last. A word opening with no letter, such
/// as `#%d`, counts either way.
private func isTitleCase(_ line: String) -> Bool {
  let minor: Set<String> = [
    "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "as", "at", "by",
    "in", "of", "on", "to", "via", "from", "into", "onto", "over", "with",
  ]
  let words = line.split(separator: " ")
  return words.indices.allSatisfy { index in
    let word = words[index]
    guard let first = word.first, first.isLetter else { return true }
    let edge = index == words.startIndex || index == words.index(before: words.endIndex)
    let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    return !edge && minor.contains(bare) ? first.isLowercase : first.isUppercase
  }
}

@Test func everyMenuCommandIsTitleCaseInEnglish() throws {
  // Read off the menus' source: a line routed back to a button's key, or a new
  // menu key in sentence case, fails here. These five are already title case:
  // one word each, or a line no button says.
  let reused = [
    "runnerMenu": "controlCenter.runnerMenu", "start": "menu.start",
    "controlCenter": "menu.controlCenter", "settings": "menu.settings", "quit": "menu.quit",
  ]
  let english = try catalogue("en")
  let l10n = l10nSource()
  for file in ["RunnerCommands.swift", "QuickMenuView.swift"] {
    let names = standfastSource(file).components(separatedBy: "L10n.").dropFirst().map {
      String($0.prefix { $0.isLetter || $0.isNumber })
    }
    #expect(!names.isEmpty, "\(file)")
    for name in names {
      let key: String
      if name.hasPrefix("menuItem") {
        let rest = name.dropFirst("menuItem".count)
        key = "menuItem." + rest.prefix(1).lowercased() + String(rest.dropFirst())
        #expect(l10n.contains("static let \(name) = t(\"\(key)\")"), "\(name)")
      } else {
        key = try #require(reused[name], "\(file) names L10n.\(name)")
      }
      let line = try #require(english[key], "en/\(key)")
      #expect(isTitleCase(line), "\(file): en/\(key) = \(line)")
    }
  }
  // Every line of the family, the job links the quick menu draws among them.
  let family = L10n.english.filter { $0.key.hasPrefix("menuItem.") }
  #expect(!family.isEmpty)
  for (key, line) in family {
    #expect(isTitleCase(line), "fallback/\(key) = \(line)")
    #expect(english[key].map(isTitleCase) == true, "en/\(key)")
  }
  // The rule, against the lines it was written for.
  #expect(isTitleCase("Show Logs in Finder"))
  #expect(isTitleCase("Open PR #702 on GitHub"))
  #expect(isTitleCase("Open in Browser"))
  #expect(!isTitleCase("Show logs in Finder"))
  #expect(!isTitleCase("Show Logs In Finder"))
  #expect(!isTitleCase("Refresh now"))
  #expect(!isTitleCase("Open workflow run on GitHub"))
}

@Test func aMenuItemSaysWhatItsButtonSaysInTheMenusOwnCase() throws {
  // A button, the toolbar, the detail form's links and every sentence keep
  // sentence case: "try Refresh now" names the toolbar's button, which still
  // says it that way. Spanish menus are in sentence case already.
  let english = try catalogue("en")
  let spanish = try catalogue("es")
  let pairs = [
    ("menuItem.refreshNow", "menu.refreshNow", "Refresh now"),
    ("menuItem.showLogsInFinder", "controlCenter.showLogs", "Show logs in Finder"),
    ("menuItem.startService", "controlCenter.service.start", "Start service"),
    ("menuItem.stopService", "controlCenter.service.stop", "Stop service"),
    ("menuItem.restartService", "controlCenter.service.restart", "Restart service"),
    ("menuItem.viewRuns", "controlCenter.viewRuns", "View runs"),
    ("menuItem.viewSettings", "controlCenter.viewSettings", "View settings"),
    ("menuItem.openGitLab", "controlCenter.openGitLab", "Open GitLab"),
    ("menuItem.openJob", "managedJob.open", "Open job on GitHub"),
    ("menuItem.openRun", "managedJob.openRun", "Open workflow run on GitHub"),
    ("menuItem.openPR", "managedJob.openPR", "Open PR #%d on GitHub"),
  ]
  for (menuKey, sharedKey, shared) in pairs {
    #expect(english[sharedKey] == shared, "en/\(sharedKey)")
    #expect(L10n.english[sharedKey] == shared, "fallback/\(sharedKey)")
    #expect(english[menuKey]?.lowercased() == shared.lowercased(), "en/\(menuKey)")
    #expect(spanish[menuKey] == spanish[sharedKey], "es/\(menuKey)")
  }
}

@Test func discoveryFailuresEndInAColonOnlyWhereAPathFollows() throws {
  // The menu prints the path on the same line; the Control Center's headings
  // keep the paths behind a button or under the title, so a colon there
  // points at nothing.
  let english = try speaking("en")
  let spanish = try speaking("es")
  let copy = [
    (
      "state.launchAgentsUnreadable", "The LaunchAgents directory could not be read:",
      "No se pudo leer el directorio LaunchAgents:"
    ),
    (
      "state.launchAgentsUnreadable.title", "The LaunchAgents directory could not be read",
      "No se pudo leer el directorio LaunchAgents"
    ),
    (
      "state.unreadable", "Some runner files could not be read:",
      "No se pudieron leer algunos archivos de runner:"
    ),
    (
      "state.unreadable.title", "Some runner files could not be read",
      "No se pudieron leer algunos archivos de runner"
    ),
  ]
  for (key, en, es) in copy {
    #expect(L10n.t(key, in: [english]) == en, "en/\(key)")
    #expect(L10n.t(key, in: [spanish]) == es, "es/\(key)")
    #expect(L10n.t(key, in: []) == en, "fallback/\(key)")
  }
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
  #expect(
    L10n.english["state.unknown.managedFleetWaiting"]?.contains(
      "supervisor") == true)
  #expect(
    L10n.english["state.unknown.managedFleetUnavailable"]?.contains(
      "supervisor") == true)
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
      "mac-mini-m4", "gadget-app", "Ready", in: [english])
      == "mac-mini-m4 · gadget-app · Ready")
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
    "cleanup.partiallyFailed": 1, "cleanup.refused": 1, "cleanup.unconfirmed": 1,
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

@Test func everyUnknownSentenceOpensWithTheBadgeBesideIt() throws {
  // The rest of UI-034 is a *stable* grammar, not two vocabularies that happen
  // to agree: the badge names what is wrong, and the sentence beneath it is
  // that same clause plus the remedy. They are separate strings, so nothing
  // stopped one being reworded without the other — and something already had.
  // `noToken` and `rateLimited` say "not asked" and "rate limit reached", and
  // a badge reading "not answering" over either is a small lie.
  //
  // Which badge each state carries is `DisplayState.shortSummary`'s business
  // and is tested there. This is the other half: that the two catalogues keep
  // saying the same thing, in both languages, where a translator editing one
  // side is exactly how they drift.
  let pairs = [
    ("state.unknown.noCLI", "state.layer.gitHubSilent"),
    ("state.unknown.notAuthenticated", "state.layer.gitHubSilent"),
    ("state.unknown.noAnswer", "state.layer.gitHubSilent"),
    ("state.unknown.noToken", "state.layer.gitHubNotAsked"),
    ("state.unknown.rateLimited", "state.layer.gitHubRateLimited"),
    ("state.unknown.noLocalAnswer", "state.layer.localUnreadable"),
    ("state.unknown.gitLabNoToken", "state.layer.gitLabNotAsked"),
    ("state.unknown.gitLabNotAuthenticated", "state.layer.gitLabRefusedToken"),
    ("state.unknown.gitLabRateLimited", "state.layer.gitLabRateLimited"),
    ("state.unknown.gitLabSilent", "state.layer.gitLabSilent"),
    ("state.unknown.tokenRefused", "state.layer.gitHubRefusedToken"),
    ("state.unknown.tokenUnreadable", "state.layer.gitHubNotAsked"),
    ("state.unknown.gitLabTokenUnreadable", "state.layer.gitLabNotAsked"),
    ("state.unknown.gitLabInsecure", "state.layer.gitLabNotAsked"),
    ("state.unknown.noLocalAnswer.process", "state.layer.localUnreadable"),
    ("state.unknown.gitLabPaused", "state.layer.gitLabPaused"),
  ]

  for language in ["en", "es"] {
    let pack = try speaking(language)
    for (sentenceKey, badgeKey) in pairs {
      let sentence = L10n.t(sentenceKey, in: [pack])
      let badge = L10n.t(badgeKey, in: [pack])
      // Case-insensitively: a badge is capitalised and the same clause sits
      // mid-sentence below it. The words are the contract, not the casing.
      #expect(
        sentence.range(of: badge, options: .caseInsensitive) != nil,
        "\(language)/\(sentenceKey) does not open with \(badgeKey)")
    }
  }
}

@Test func noLineTheTokenPathCanProduceNamesGh() throws {
  // With a token stored `gh` is never run, so a line naming it sends the user
  // to a tool that played no part. Both catalogues, because the test host
  // only ever speaks one of them.
  let keys = [
    "state.unknown.noAnswer", "state.unknown.rateLimited", "state.unknown.tokenRefused",
    "state.unknown.tokenUnreadable",
  ]
  for language in ["en", "es"] {
    let pack = try speaking(language)
    for key in keys {
      let line = L10n.t(key, in: [pack])
      #expect(
        line.range(of: #"\bgh\b"#, options: .regularExpression) == nil,
        "\(language)/\(key): \(line)")
    }
  }
}

@Test func theLoginItemsNoticeNamesThePaneThisMacOSHas() throws {
  // macOS 15 renamed the pane and 14 is still supported, so one sentence would
  // send somebody on one of them to a name that is not on their screen.
  let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0)
  let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
  let panes = [
    ("en", "Login Items", "Login Items & Extensions"),
    ("es", "Ítems de inicio", "Ítems de inicio y extensiones"),
  ]
  let keys = ["menu.openAtLogin.needsApproval", "menu.openAtLogin.unavailable"]

  for (language, old, renamed) in panes {
    let pack = try speaking(language)
    for key in keys {
      let before = L10n.t(L10n.loginItemsPaneKey(key, on: sonoma), in: [pack])
      let after = L10n.t(L10n.loginItemsPaneKey(key, on: sequoia), in: [pack])
      #expect(before.hasSuffix("› " + old), "\(language)/\(key) on 14")
      #expect(after.hasSuffix("› " + renamed), "\(language)/\(key) on 15")
    }
  }
  // On whichever macOS runs this, the lines the app shows take the same turn.
  #expect(
    L10n.openAtLoginNeedsApproval
      == L10n.t(L10n.loginItemsPaneKey("menu.openAtLogin.needsApproval")))
  #expect(
    L10n.openAtLoginUnavailable
      == L10n.t(L10n.loginItemsPaneKey("menu.openAtLogin.unavailable")))
}

@Test func theUnaskableQueueLineCoversEnterpriseRunnersToo() throws {
  // GitHub has no queue endpoint for either scope, so both get this line, and
  // naming only one tells an enterprise runner it is something else.
  let english = try #require(try catalogue("en")["queue.unknownScope"])
  let spanish = try #require(try catalogue("es")["queue.unknownScope"])

  #expect(english.contains("organization") && english.contains("enterprise"))
  #expect(spanish.contains("organización") && spanish.contains("empresa"))
}

@Test func spanishCopyReadsAsOneVoice() throws {
  let spanish = try catalogue("es")

  for (key, value) in spanish {
    // Every other line says `esta Mac`, and one `este Mac` reads as somebody else.
    #expect(!value.contains("este Mac"), "es/\(key)")
    // A button name is not an instruction on its own.
    #expect(!value.contains(". Actualizar ahora"), "es/\(key)")
    #expect(!value.contains("luego Actualizar ahora"), "es/\(key)")
  }
  // The `una` of the second sentence stands for the noun the first one names.
  #expect(spanish["cleanup.toolCache.effect"]?.contains("las toolchains") == true)
  #expect(spanish["menu.preventSleep.lid"] == "Aun así, cerrar la tapa la pone en reposo")
}

@Test func theOverviewCountAndARunnersIdentityReadTheSameInBothLanguages() throws {
  let english = try speaking("en")
  let spanish = try speaking("es")
  #expect(L10n.controlCenterRunnerCount(1, in: [english]) == "1 runner on this Mac")
  #expect(L10n.controlCenterRunnerCount(5, in: [english]) == "5 runners on this Mac")
  #expect(L10n.controlCenterRunnerCount(1, in: [spanish]) == "1 runner en esta Mac")
  #expect(L10n.controlCenterRunnerCount(5, in: [spanish]) == "5 runners en esta Mac")
  #expect(L10n.controlCenterRunnerCount(5, in: []) == "5 runners on this Mac")
  for bundles in [[english], [spanish], []] {
    #expect(
      L10n.runnerIdentity("mac-mini-m4", "widget-factory", in: bundles)
        == "mac-mini-m4 · widget-factory")
  }
}
