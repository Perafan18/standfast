import Foundation

/// Every user-facing string, in one place.
///
/// Call sites say `L10n.start`, so replacing `.strings` with a String Catalog,
/// or dropping the catalogue entirely, touches this file and nothing else.
enum L10n {
  static let statusItemLabel = t("app.statusItem")
  static let controlCenterTitle = t("controlCenter.title")
  static let controlCenterNoRunnersDescription = t(
    "controlCenter.noRunners.description")
  static let controlCenterInstallGuide = t("controlCenter.installGuide")
  /// Said only on the empty state, where somebody who started a runner with
  /// `./run.sh` would otherwise decide this app cannot see their machine.
  static let controlCenterNoRunnersManual = t("controlCenter.noRunners.manual")
  static let settingsAppearance = t("settings.appearance")
  static let settingsAppearanceFooter = t("settings.appearance.footer")
  static let settingsShowInDock = t("settings.showInDock")
  static let controlCenterScope = t("controlCenter.scope")
  /// What a scope *is* to a runner, for the line that only shows the name.
  static func scopeExplained(_ scope: String) -> String {
    String(format: t("controlCenter.scope.explained"), scope)
  }
  /// How many of the recent jobs are listed — the badge used to be a bare `5+`.
  static func historyLatest(_ count: Int) -> String {
    String(format: t("controlCenter.history.latest"), count)
  }
  static let controlCenterStatus = t("controlCenter.status")
  static let controlCenterService = t("controlCenter.service")
  /// The service buttons, with the object the bare verbs were missing.
  ///
  /// `Parar` alone can be read as "stop taking work", "cancel this job
  /// cleanly" or "stop the service". The confirmation dialog does say which —
  /// after the click. These say it before, and leave `Cancelar job` free for
  /// the day that function exists.
  static let serviceStart = t("controlCenter.service.start")
  static let serviceStop = t("controlCenter.service.stop")
  static let serviceRestart = t("controlCenter.service.restart")
  /// The two halves a runner's state is made of, named only where they
  /// disagree — which is where one word alone lies.
  static let stateLayerRunningLocally = t("state.layer.runningLocally")
  static let runnerStartedByHand = t("runner.startedByHand")
  static let runnerGitLabService = t("runner.gitLabService")
  static let runnerManagedFleet = t("runner.managedFleet")
  static let managedJobOpen = t("managedJob.open")
  static let managedRunOpen = t("managedJob.openRun")
  static func managedPROpen(_ number: Int) -> String {
    String(format: t("managedJob.openPR"), number)
  }
  static func managedJobNoPR(_ event: String) -> String {
    String(format: t("managedJob.noPR"), event)
  }
  static let stateLayerGitHubSilent = t("state.layer.gitHubSilent")
  static let stateUnknownGitLabNoToken = t("state.unknown.gitLabNoToken")
  static let stateUnknownGitLabNotAuthenticated = t("state.unknown.gitLabNotAuthenticated")
  static let stateUnknownGitLabRateLimited = t("state.unknown.gitLabRateLimited")
  static let stateUnknownGitLabSilent = t("state.unknown.gitLabSilent")
  static let stateLayerGitLabNotAsked = t("state.layer.gitLabNotAsked")
  static let stateLayerGitLabRefusedToken = t("state.layer.gitLabRefusedToken")
  static let stateLayerGitLabRateLimited = t("state.layer.gitLabRateLimited")
  static let stateLayerGitLabSilent = t("state.layer.gitLabSilent")
  static let stateLayerGitHubNotAsked = t("state.layer.gitHubNotAsked")
  static let stateLayerGitHubRateLimited = t("state.layer.gitHubRateLimited")
  static let stateLayerLocalUnreadable = t("state.layer.localUnreadable")
  static let stateLayerManagedFleetWaiting = t("state.layer.managedFleetWaiting")
  static let stateLayerManagedFleetUnavailable = t("state.layer.managedFleetUnavailable")
  static let foldCard = t("controlCenter.fold")
  static let unfoldCard = t("controlCenter.unfold")
  static let openWorkflowRuns = t("controlCenter.openWorkflowRuns")
  static let openRunnerSettings = t("controlCenter.openRunnerSettings")
  static let settingsNotifications = t("settings.notifications")
  static let settingsPower = t("settings.power")
  static let settingsStartup = t("settings.startup")
  static let settingsNotificationsFooter = t("settings.notifications.footer")
  static let settingsPowerFooter = t("settings.power.footer")
  static let settingsStartupFooter = t("settings.startup.footer")
  static let settingsRunners = t("settings.runners")
  static let settingsRunnersFooter = t("settings.runners.footer")
  static let settingsRunnersNone = t("settings.runners.none")
  static let settingsRunnersAdd = t("settings.runners.add")
  static func settingsRunnersRemove(_ name: String, in bundles: [Bundle]? = nil) -> String {
    String(format: t("settings.runners.remove", in: bundles), name)
  }
  static let settingsGitHub = t("settings.github")
  static let settingsGitLab = t("settings.gitlab")
  static let settingsGitLabFooter = t("settings.gitlab.footer")
  static let settingsGitLabStored = t("settings.gitlab.stored")
  static let settingsGitLabAbsent = t("settings.gitlab.absent")
  static let settingsGitLabPlaceholder = t("settings.gitlab.placeholder")
  static let settingsGitHubFooter = t("settings.github.footer")
  static let settingsGitHubStored = t("settings.github.stored")
  static let settingsGitHubAbsent = t("settings.github.absent")
  static let settingsGitHubUnreadable = t("settings.github.unreadable")
  static let settingsGitHubPlaceholder = t("settings.github.placeholder")
  static let settingsGitHubSave = t("settings.github.save")
  static let settingsGitHubRemove = t("settings.github.remove")
  static let settingsGitHubKeychainFailed = t("settings.github.keychainFailed")

  static func settingsVersion(
    _ suffix: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("settings.version", in: bundles), suffix)
  }

  static let start = t("menu.start")
  static let stop = t("menu.stop")
  static let restart = t("menu.restart")
  static let openOnGitHub = t("menu.openOnGitHub")
  static let refreshNow = t("menu.refreshNow")
  static let quit = t("menu.quit")
  static let controlCenter = t("menu.controlCenter")
  static let settings = t("menu.settings")
  static let recentJobs = t("menu.recentJobs")
  static let openAtLogin = t("menu.openAtLogin")
  static let openAtLoginFailed = t("menu.openAtLogin.failed")
  static let openAtLoginNeedsApproval = t("menu.openAtLogin.needsApproval")
  static let openAtLoginUnavailable = t("menu.openAtLogin.unavailable")

  static let notifyMe = t("menu.notify")
  static let notifyJobFailed = t("menu.notify.jobFailed")
  static let notifyDisconnected = t("menu.notify.disconnected")
  static let notifyStopped = t("menu.notify.stopped")
  static let notificationsBlocked = t("menu.notify.blocked")
  static let preventSleep = t("menu.preventSleep")
  static let preventSleepLidNotice = t("menu.preventSleep.lid")

  /// How long ago it ran and how long it took, in that order.
  ///
  /// The order is the whole fix: a bare `(2m 52s)` after an outcome reads as
  /// an age to anybody who did not write it, so the age goes first and the
  /// duration arrives with a verb attached.
  static func jobAgeAndDuration(
    _ age: String, _ duration: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("job.ageAndDuration", in: bundles), age, duration)
  }

  static let maintenance = t("menu.maintenance")
  static let measureDiskUse = t("menu.maintenance.measure")
  /// Why the biggest directory on the list has no button (D-R21). Listing it
  /// with a size and no action reads as a missing feature; the reason is that
  /// this app cannot tell a regenerable cache from work that exists nowhere
  /// else.
  static let checkoutNotOffered = t("cleanup.checkoutNotOffered")
  static let deletingOnlyWhenIdle = t("menu.maintenance.onlyWhenIdle")

  static let diskWorking = t("disk.working")
  static let diskNotMeasured = t("disk.notMeasured")
  static let diskMeasuredJustNow = t("disk.measuredJustNow")
  static let diskUnavailable = t("disk.unavailable")
  static let diskOutsideRunner = t("disk.outsideRunner")
  static let diskManagedFleet = t("disk.managedFleet")

  // The two buttons of the confirmation, and nothing else in it. Everything
  // above them names a directory, a size or a runner, which is what makes the
  // dialogue worth reading.
  static let cleanupDelete = t("cleanup.confirm.delete")
  static let cleanupCancel = t("cleanup.confirm.cancel")

  // What deleting each cache actually costs, said in the dialogue rather than
  // left to the user to know. Both answers are "one slower build", which is the
  // whole reason these two are the only things this app offers to delete.
  static let cleanupToolCacheEffect = t("cleanup.toolCache.effect")
  static let cleanupActionCacheEffect = t("cleanup.actionCache.effect")
  static let cleanupStandfastTrashEffect = t("cleanup.standfastTrash.effect")

  static let noRunnersFound = t("state.noRunners")
  static let checkingRunners = t("state.checking")
  static let launchAgentsUnreadable = t("state.launchAgentsUnreadable")
  static let someRunnersUnreadable = t("state.unreadable")
  static let moreUnreadable = t("state.unreadable.more")

  static let stateIdle = t("state.idle")
  static let stateBusy = t("state.busy")
  static let stateDisconnected = t("state.disconnected")
  static let stateStopped = t("state.stopped")
  static let stateStarting = t("state.starting")
  static let stateReadyShort = t("state.short.ready")
  static let stateRunningShort = t("state.short.running")
  static let stateDisconnectedShort = t("state.short.disconnected")
  static let stateStoppedShort = t("state.short.stopped")
  static let stateStartingShort = t("state.short.starting")
  static let stateUnknownManagedFleetWaiting = t("state.unknown.managedFleetWaiting")
  static let stateUnknownManagedFleetUnavailable = t(
    "state.unknown.managedFleetUnavailable")

  static func runnerAttention(
    _ count: Int, in bundles: [Bundle]? = nil
  ) -> String {
    let key = count == 1 ? "controlCenter.attention.one" : "controlCenter.attention"
    return String(format: t(key, in: bundles), Int64(count))
  }

  static func viewRuns(in bundles: [Bundle]? = nil) -> String {
    t("controlCenter.viewRuns", in: bundles)
  }

  static func viewSettings(in bundles: [Bundle]? = nil) -> String {
    t("controlCenter.viewSettings", in: bundles)
  }

  static func historyEmpty(in bundles: [Bundle]? = nil) -> String {
    t("controlCenter.history.empty", in: bundles)
  }

  static func historyUnavailable(in bundles: [Bundle]? = nil) -> String {
    t("controlCenter.history.unavailable", in: bundles)
  }

  static func maintenanceCompact(in bundles: [Bundle]? = nil) -> String {
    t("controlCenter.maintenance.compact", in: bundles)
  }

  static func startRunner(
    _ runner: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("controlCenter.action.start", in: bundles), runner)
  }

  static func stopRunner(
    _ runner: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("controlCenter.action.stop", in: bundles), runner)
  }

  static func restartRunner(
    _ runner: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("controlCenter.action.restart", in: bundles), runner)
  }

  // One line per `UnknownReason`, because each one has a different next step
  // and "unknown" on its own has none. This is the likeliest thing a new user
  // sees, so the line has to be the instruction.
  static let stateUnknownNoCLI = t("state.unknown.noCLI")
  static let queueWaitingOne = t("queue.waiting.one")
  static func queueWaiting(_ count: Int, in bundles: [Bundle]? = nil) -> String {
    String(format: t("queue.waiting", in: bundles), count)
  }
  static func queueWaitingPartial(_ count: Int, in bundles: [Bundle]? = nil) -> String {
    String(format: t("queue.waitingPartial", in: bundles), count)
  }
  static let queueEmpty = t("queue.empty")
  static let queueUnknownScope = t("queue.unknownScope")
  static let stateUnknownNoToken = t("state.unknown.noToken")
  static let stateUnknownRateLimited = t("state.unknown.rateLimited")
  static let stateUnknownNotAuthenticated = t("state.unknown.notAuthenticated")
  static let stateUnknownNoAnswer = t("state.unknown.noAnswer")
  static let stateUnknownNoLocalAnswer = t("state.unknown.noLocalAnswer")

  static let checkedJustNow = t("state.checkedJustNow")
  static let checkedNever = t("state.checkedNever")

  // Only the two states where macOS is actually holding the machine back.
  // There is no line for a cool Mac, because a row that is true every day is a
  // row nobody reads.
  static let thermalSerious = t("thermal.serious")
  static let thermalCritical = t("thermal.critical")
  static let thermalSlowingJobs = t("thermal.slowingJobs")

  // What a banner says. The title names the kind of trouble and the body names
  // which runner, because a notification is read out of the corner of an eye
  // and on a Mac with two runners the name is the only part that decides what
  // to do next.
  static let notificationJobFailedTitle = t("notification.jobFailed.title")
  static let notificationDisconnectedTitle = t("notification.disconnected.title")
  static let notificationStoppedTitle = t("notification.stopped.title")

  // The runner's own word for how a job ended, translated. `.other` is not
  // here on purpose: an outcome this version has never met is shown as GitHub
  // wrote it, since a translation of it would be one this app invented.
  static let jobSucceeded = t("job.result.succeeded")
  static let jobFailed = t("job.result.failed")
  static let jobCanceled = t("job.result.canceled")
  static let jobInterrupted = t("job.result.interrupted")

  static func serviceOperationInFlightTitle(_ action: String) -> String {
    String(format: t("operation.inFlight.title"), action)
  }

  static func serviceConfirmStopTitle(
    _ runner: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("service.confirm.stop.title", in: bundles), runner)
  }

  static func serviceConfirmRestartTitle(
    _ runner: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("service.confirm.restart.title", in: bundles), runner)
  }

  static func serviceConfirmStopBusy(
    _ runner: String, _ scope: String, _ job: String,
    in bundles: [Bundle]? = nil
  ) -> String {
    String(
      format: t("service.confirm.stop.busy", in: bundles), runner, scope, job)
  }

  static func serviceConfirmRestartBusy(
    _ runner: String, _ scope: String, _ job: String,
    in bundles: [Bundle]? = nil
  ) -> String {
    String(
      format: t("service.confirm.restart.busy", in: bundles), runner, scope, job)
  }

  static func serviceConfirmStopUncertain(
    _ runner: String, _ scope: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(
      format: t("service.confirm.stop.uncertain", in: bundles), runner, scope)
  }

  static func serviceConfirmRestartUncertain(
    _ runner: String, _ scope: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(
      format: t("service.confirm.restart.uncertain", in: bundles), runner, scope)
  }

  static func serviceConfirmCancel(in bundles: [Bundle]? = nil) -> String {
    t("service.confirm.cancel", in: bundles)
  }
  static func serviceOperationInFlightDetail(_ action: String) -> String {
    String(format: t("operation.inFlight.detail"), action)
  }
  static func serviceOperationAcceptedTitle(_ action: String) -> String {
    String(format: t("operation.accepted.title"), action)
  }
  static func serviceOperationAcceptedDetail(_ action: String) -> String {
    String(format: t("operation.accepted.detail"), action)
  }
  static func serviceOperationTimedOutTitle(_ action: String) -> String {
    String(format: t("operation.timedOut.title"), action)
  }
  static func serviceOperationTimedOutDetail(_ action: String) -> String {
    String(format: t("operation.timedOut.detail"), action)
  }
  static func serviceOperationScriptMissingTitle(_ action: String) -> String {
    String(format: t("operation.scriptMissing.title"), action)
  }
  static func serviceOperationScriptMissingDetail(_ action: String) -> String {
    String(format: t("operation.scriptMissing.detail"), action)
  }
  static func serviceOperationCouldNotLaunchTitle(_ action: String) -> String {
    String(format: t("operation.couldNotLaunch.title"), action)
  }
  static func serviceOperationCouldNotLaunchDetail(_ action: String) -> String {
    String(format: t("operation.couldNotLaunch.detail"), action)
  }
  static func serviceOperationUnexpectedFailureTitle(_ action: String) -> String {
    String(format: t("operation.unexpectedFailure.title"), action)
  }
  static func serviceOperationUnexpectedFailureDetail(_ action: String) -> String {
    String(format: t("operation.unexpectedFailure.detail"), action)
  }
  static func serviceOperationConfirmationUnavailableTitle(
    _ action: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(
      format: t("operation.confirmationUnavailable.title", in: bundles), action)
  }
  static func serviceOperationConfirmationUnavailableDetail(
    _ action: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(
      format: t("operation.confirmationUnavailable.detail", in: bundles), action)
  }
  static let serviceOperationRestartStartFailedTitle = t(
    "operation.restartStartFailed.title")
  static let serviceOperationRestartStartFailedDetail = t(
    "operation.restartStartFailed.detail")
  static let serviceOperationRestartStartTimedOutTitle = t(
    "operation.restartStartTimedOut.title")
  static let serviceOperationRestartStartTimedOutDetail = t(
    "operation.restartStartTimedOut.detail")

  /// A runner's name and its state on one line. Localised because the dash and
  /// the spacing around it are not punctuation every language writes the same.
  static func runnerRow(_ name: String, _ state: String) -> String {
    String(format: t("menu.runnerRow"), name, state)
  }

  static func quickMenuRunner(
    _ name: String, _ state: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("menu.quickRunner", in: bundles), name, state)
  }

  static func quickMenuRunnerInScope(
    _ name: String, _ scope: String, _ state: String,
    in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("menu.quickRunnerScoped", in: bundles), name, scope, state)
  }

  static func quickMenuScopeWithID(
    _ scope: String, _ id: Int, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("menu.quickRunnerScopeID", in: bundles), scope, Int64(id))
  }

  /// The job in flight and how long it has been going.
  static func jobRunning(_ name: String, _ elapsed: String) -> String {
    String(format: t("job.running"), name, elapsed)
  }

  /// The same, with what that job usually takes on this runner.
  static func jobRunningWithTypical(
    _ name: String, _ elapsed: String, _ typical: String
  ) -> String {
    String(format: t("job.runningWithTypical"), name, elapsed, typical)
  }

  /// One finished job: what it was, how it ended, how long it took.
  static func jobRow(_ name: String, _ result: String, _ duration: String) -> String {
    String(format: t("job.row"), name, result, duration)
  }

  /// The same for a job with no duration, which is a job that never finished.
  static func jobRowNoDuration(_ name: String, _ result: String) -> String {
    String(format: t("job.rowNoDuration"), name, result)
  }

  /// Which job broke, and on which runner.
  static func notificationJobFailedBody(_ job: String, _ runner: String) -> String {
    String(format: t("notification.jobFailed.body"), job, runner)
  }

  static func notificationDisconnectedBody(_ runner: String) -> String {
    String(format: t("notification.disconnected.body"), runner)
  }

  static func notificationStoppedBody(_ runner: String) -> String {
    String(format: t("notification.stopped.body"), runner)
  }

  /// How long ago the machine was last read.
  /// What the line says when the last attempt failed: the failure first,
  /// then how old the reading it is still showing actually is.
  static func checkFailedThenChecked(
    _ checked: String, in bundles: [Bundle]? = nil
  ) -> String {
    String(format: t("state.checkFailed", in: bundles), checked)
  }

  static func checkedAgo(_ elapsed: String) -> String {
    String(format: t("state.checkedAgo"), elapsed)
  }

  // Durations. Localised rather than assembled from digits and Latin letters:
  // "2m 47s" is an abbreviation, and abbreviations are words.
  static func durationHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
    String(format: t("duration.hoursMinutes"), hours, minutes)
  }

  static func durationMinutesSeconds(_ minutes: Int, _ seconds: Int) -> String {
    String(format: t("duration.minutesSeconds"), minutes, seconds)
  }

  /// `3 d` — the step `coarse` was missing. Without it a job from the day
  /// before yesterday read as "hace 53 h", which is a number, not an answer.
  static func durationDays(_ days: Int, in bundles: [Bundle]? = nil) -> String {
    String(format: t("duration.days", in: bundles), days)
  }

  static func durationHours(_ hours: Int) -> String {
    String(format: t("duration.hours"), hours)
  }

  static func durationMinutes(_ minutes: Int) -> String {
    String(format: t("duration.minutes"), minutes)
  }

  static func durationSeconds(_ seconds: Int) -> String {
    String(format: t("duration.seconds"), seconds)
  }

  // Disk rows. One format per kind rather than one with the heading passed in:
  // a heading is a sentence, and a language that puts the size first has to be
  // able to say so.
  static func diskToolCache(_ size: String) -> String {
    String(format: t("disk.toolCache"), size)
  }

  static func diskActionCache(_ size: String) -> String {
    String(format: t("disk.actionCache"), size)
  }

  static func diskCheckouts(_ size: String) -> String {
    String(format: t("disk.checkout"), size)
  }

  static func diskTemporary(_ size: String) -> String {
    String(format: t("disk.temporary"), size)
  }

  static func diskOther(_ size: String) -> String {
    String(format: t("disk.other"), size)
  }

  static func diskStandfastTrash(_ size: String) -> String {
    String(format: t("disk.standfastTrash"), size)
  }

  static func diskLogs(_ size: String) -> String {
    String(format: t("disk.logs"), size)
  }

  /// How long ago the disk was measured. Its own key rather than the one the
  /// fleet uses, because this number is minutes-to-hours old by design where
  /// that one is seconds.
  static func diskMeasuredAgo(_ elapsed: String) -> String {
    String(format: t("disk.measuredAgo"), elapsed)
  }

  // What each button offers, size and all. The size is in the label because it
  // is the reason to press it: "free up the tool cache" is a chore, and "free
  // up the tool cache (4.03 GB)" is a decision.
  static func freeToolCache(_ size: String) -> String {
    String(format: t("menu.maintenance.freeToolCache"), size)
  }

  static func freeActionCache(_ size: String) -> String {
    String(format: t("menu.maintenance.freeActionCache"), size)
  }

  static func cleanStandfastTrash(_ size: String) -> String {
    String(format: t("menu.maintenance.cleanStandfastTrash"), size)
  }

  static func deleteOldLogs(_ size: String) -> String {
    String(format: t("menu.maintenance.trimLogs"), size)
  }

  /// The runner's own version.
  static let runnerVersionUnreadable = t("menu.runnerVersion.unreadable")

  static func runnerVersion(_ version: String) -> String {
    String(format: t("menu.runnerVersion"), version)
  }

  /// The same, with the newer one GitHub has published.
  static func runnerVersionOutdated(_ installed: String, _ latest: String) -> String {
    String(format: t("menu.runnerVersion.update"), installed, latest)
  }

  /// What is about to be deleted, named by its path. A folder name on its own
  /// does not say which runner it belongs to, and this app is built for the Mac
  /// with two of them.
  static func cleanupConfirmTitle(_ path: String) -> String {
    String(format: t("cleanup.confirm.title"), path)
  }

  /// How much it frees and whose it is.
  static func cleanupConfirmBody(_ size: String, _ runner: String) -> String {
    String(format: t("cleanup.confirm.body"), size, runner)
  }

  static func cleanupStandfastTrashTitle(_ path: String) -> String {
    String(format: t("cleanup.standfastTrash.title"), path)
  }

  static func cleanupLogsTitle(
    _ count: Int, _ path: String, in bundles: [Bundle]? = nil
  ) -> String {
    if count == 1 {
      return String(format: t("cleanup.logs.title.one", in: bundles), count, path)
    }
    return String(format: t("cleanup.logs.title", in: bundles), count, path)
  }

  static func cleanupLogsEffect(
    _ count: Int, in bundles: [Bundle]? = nil
  ) -> String {
    let key = count == 1 ? "cleanup.logs.effect.one" : "cleanup.logs.effect"
    return String(format: t(key, in: bundles), count)
  }

  /// Said when the runner picked up work between the confirmation and the
  /// deletion. The one outcome that has to be reported, because the user asked
  /// for something and did not get it.
  /// Said when the delete dialogue could not be presented at all — a locked
  /// screen means no modal appears and the click does nothing (D-R20).
  static let cleanupConfirmationUnavailable = t("cleanup.confirmationUnavailable")
  static func cleanupRefused(_ runner: String) -> String {
    String(format: t("cleanup.refused"), runner)
  }

  static func cleanupFailed(_ path: String) -> String {
    String(format: t("cleanup.failed"), path)
  }

  static func cleanupPartiallyFailed(_ path: String) -> String {
    String(format: t("cleanup.partiallyFailed"), path)
  }

  /// A runner's name and the GitHub scope it is registered against, for the
  /// rows where the name alone appears twice. Localised for the same reason as
  /// the row itself: the brackets are punctuation, and punctuation is written
  /// differently in different languages.
  static func runnerInScope(_ name: String, _ scope: String) -> String {
    String(format: t("menu.runnerInScope"), name, scope)
  }

  /// The English this app carries inside its own binary, keyed the same way as
  /// the catalogues.
  ///
  /// A table rather than a literal beside each key, because this is the floor
  /// the menu lands on when no catalogue can be read, and a floor that cannot
  /// be enumerated cannot be tested. `Resources/en.lproj/Localizable.strings`
  /// has to say exactly this, and a test holds the two together.
  static let english: [String: String] = [
    "app.statusItem": "Standfast",
    "controlCenter.title": "Standfast Control Center",
    "controlCenter.installGuide": "How to install a runner",
    "controlCenter.noRunners.description":
      "Install a self-hosted GitHub Actions runner, then refresh.",
    "controlCenter.noRunners.manual":
      "Already started one with ./run.sh? Point Settings at its folder.",
    "settings.appearance": "Appearance",
    "settings.showInDock": "Show in the Dock",
    "settings.appearance.footer":
      "Standfast lives in the menu bar. Turn this on and it also takes a Dock "
      + "tile and appears in \u{2318}-Tab, which survives a restart.",
    "controlCenter.scope": "Scope",
    "controlCenter.status": "Status",
    "controlCenter.service": "Runner service",
    "controlCenter.openWorkflowRuns": "Open workflow runs",
    "controlCenter.openRunnerSettings": "Open runner settings",
    "controlCenter.attention.one": "%lld runner needs attention",
    "controlCenter.attention": "%lld runners need attention",
    "controlCenter.viewRuns": "View runs",
    "controlCenter.viewSettings": "View settings",
    "controlCenter.history.empty": "No jobs recorded",
    "controlCenter.history.unavailable": "Job history unavailable",
    "controlCenter.maintenance.compact": "Not measured",
    "controlCenter.service.start": "Start service",
    "controlCenter.service.stop": "Stop service",
    "controlCenter.service.restart": "Restart service",
    "runner.gitLabService":
      "Runs under gitlab-runner, one service for every GitLab runner here — start or stop it from a terminal",
    "runner.startedByHand":
      "Started by hand, so Standfast can watch it but not stop or restart it",
    "managedJob.open": "Open job on GitHub",
    "managedJob.openRun": "Open workflow run on GitHub",
    "managedJob.openPR": "Open PR #%d on GitHub",
    "managedJob.noPR": "%@ · No PR reported by GitHub",
    "runner.managedFleet":
      "Managed by the runner fleet supervisor — slots rotate automatically and Standfast watches them read-only",
    "state.layer.runningLocally": "Running locally",
    "state.layer.gitHubNotAsked": "GitHub not asked",
    "state.layer.gitHubRateLimited": "GitHub rate limit reached",
    "state.unknown.gitLabNoToken":
      "Running locally, GitLab not asked — add a GitLab token in Settings",
    "state.unknown.gitLabNotAuthenticated":
      "Running locally, GitLab refused the token — replace it in Settings",
    "state.unknown.gitLabRateLimited":
      "Running locally, GitLab rate limit reached — it answers again shortly",
    "state.unknown.gitLabSilent":
      "Running locally, GitLab not answering — check the network, or the token in Settings",
    "state.layer.gitLabNotAsked":
      "GitLab not asked",
    "state.layer.gitLabRefusedToken":
      "GitLab refused the token",
    "state.layer.gitLabRateLimited":
      "GitLab rate limit reached",
    "state.layer.gitLabSilent":
      "GitLab not answering",
    "state.layer.gitHubSilent": "GitHub not answering",
    "state.layer.localUnreadable": "Local service unreadable",
    "state.layer.managedFleetWaiting": "Fleet slot waiting",
    "state.layer.managedFleetUnavailable": "Fleet status unavailable",
    "controlCenter.fold": "Fold",
    "controlCenter.unfold": "Unfold",
    "controlCenter.action.start": "Start %@",
    "controlCenter.action.stop": "Stop %@",
    "controlCenter.action.restart": "Restart %@",
    "settings.notifications": "Notifications",
    "settings.power": "Power",
    "settings.startup": "Startup",
    "settings.notifications.footer": "Alerts use system notifications.",
    "settings.power.footer": "Closing the lid still puts this Mac to sleep.",
    "settings.gitlab":
      "GitLab access",
    "settings.gitlab.footer":
      "With a personal access token, Standfast asks your GitLab instance about its runners. The instance comes from each runner's own configuration.",
    "settings.gitlab.stored":
      "A token is stored. Standfast asks GitLab directly.",
    "settings.gitlab.absent":
      "No token stored. GitLab runners show as not asked.",
    "settings.gitlab.placeholder":
      "Paste a GitLab token",
    "settings.github":
      "GitHub access",
    "settings.github.footer":
      "With a token of its own, Standfast asks GitHub directly and needs no other tool installed. Without one it borrows the credentials of the gh CLI.",
    "settings.github.stored":
      "A token is stored. Standfast asks GitHub directly.",
    "settings.github.absent":
      "No token stored. Standfast asks through the gh CLI.",
    "settings.github.unreadable":
      "The Keychain would not say whether a token is stored.",
    "settings.github.placeholder":
      "Paste a GitHub token",
    "settings.github.save":
      "Save token",
    "settings.github.remove":
      "Remove token",
    "settings.github.keychainFailed":
      "The Keychain refused to store it. Nothing was changed.",
    "settings.runners":
      "Runners started by hand",
    "settings.runners.footer":
      "A runner installed as a service announces itself and Standfast finds it. One started with ./run.sh does not, so point Standfast at its folder. Standfast can watch these but cannot start or stop them.",
    "settings.runners.none":
      "None added. Only runners installed as a service are being watched.",
    "settings.runners.add":
      "Add a runner folder…",
    "settings.runners.remove":
      "Stop watching %@",
    "settings.startup.footer":
      "Standfast can open automatically when you log in.",
    "settings.version": "Standfast%@",
    "menu.start": "Start",
    "menu.stop": "Stop",
    "menu.restart": "Restart",
    "menu.openOnGitHub": "Open on GitHub",
    "menu.refreshNow": "Refresh now",
    "menu.quit": "Quit",
    "menu.controlCenter": "Open Standfast",
    "menu.settings": "Settings",
    "menu.recentJobs": "Recent jobs",
    "menu.openAtLogin": "Open at login",
    "menu.openAtLogin.failed": "Open at login could not be turned on",
    "menu.openAtLogin.needsApproval":
      "Allow Standfast in System Settings › General › Login Items",
    "menu.openAtLogin.unavailable":
      "Login item state unknown; check System Settings › General › Login Items",
    "menu.notify": "Notify me",
    "menu.notify.jobFailed": "When a job fails",
    "menu.notify.disconnected": "When a runner disconnects",
    "menu.notify.stopped": "When a runner stops on its own",
    "menu.notify.blocked":
      "Notifications are switched off for Standfast in System Settings › "
      + "Notifications",
    "menu.preventSleep": "Keep this Mac awake while a job runs",
    "menu.preventSleep.lid": "Closing the lid still sends it to sleep",
    "menu.maintenance": "Maintenance",
    "menu.maintenance.measure": "Measure disk use",
    "menu.maintenance.freeToolCache": "Free up the tool cache (%@)…",
    "menu.maintenance.freeActionCache": "Free up downloaded actions (%@)…",
    "menu.maintenance.cleanStandfastTrash":
      "Delete Standfast cleanup leftovers (%@)…",
    "menu.maintenance.trimLogs": "Delete old logs (%@)…",
    "cleanup.checkoutNotOffered":
      "Repository checkouts are not offered: they can hold build output that exists nowhere else.",
    "menu.maintenance.onlyWhenIdle":
      "Deleting is offered while this runner is idle or stopped",
    "menu.runnerVersion.unreadable": "Runner version could not be read",
    "menu.runnerVersion": "Runner %@",
    "menu.runnerVersion.update": "Runner %@ — %@ is available",
    "menu.runnerRow": "%@ — %@",
    "menu.runnerInScope": "%@ (%@)",
    "menu.quickRunner": "%@ · %@",
    "menu.quickRunnerScoped": "%@ · %@ · %@",
    "menu.quickRunnerScopeID": "%@ · #%lld",
    "disk.toolCache": "Tool cache — %@",
    "disk.actionCache": "Downloaded actions — %@",
    "disk.checkout": "Repository checkouts — %@",
    "disk.temporary": "Job scratch space — %@",
    "disk.other": "Other runner files — %@",
    "disk.standfastTrash": "Standfast cleanup leftovers — %@",
    "disk.logs": "Logs — %@",
    "disk.working": "Working…",
    "disk.notMeasured": "Disk use not measured yet",
    "controlCenter.scope.explained":
      "Registered in %@: it only receives work from that scope",
    "controlCenter.history.latest": "Latest %d",
    "disk.measuredJustNow": "Disk use measured just now",
    "disk.measuredAgo": "Disk use measured %@ ago",
    "disk.outsideRunner":
      "The checkout lives outside the runner's folder, so maintenance leaves it alone",
    "disk.managedFleet": "Maintenance is owned by the runner fleet supervisor",
    "disk.unavailable": "Disk use could not be measured",
    "cleanup.confirm.title": "Delete %@?",
    "cleanup.confirm.body": "This frees %@ on %@.",
    "cleanup.confirm.delete": "Delete",
    "cleanup.confirm.cancel": "Cancel",
    "service.confirm.stop.title": "Stop %@?",
    "service.confirm.restart.title": "Restart %@?",
    "service.confirm.stop.busy":
      "%@ in %@ is running “%@”. Stopping it interrupts this job.",
    "service.confirm.restart.busy":
      "%@ in %@ is running “%@”. Restarting interrupts this job. "
      + "If Start fails after Stop, the runner can remain stopped.",
    "service.confirm.stop.uncertain":
      "%@ in %@ may have work in progress. Stopping it can interrupt that work.",
    "service.confirm.restart.uncertain":
      "%@ in %@ may have work in progress. Restarting can interrupt that work. "
      + "If Start fails after Stop, the runner can remain stopped.",
    "service.confirm.cancel": "Cancel",
    "cleanup.toolCache.effect":
      "The tool cache holds the toolchains that setup steps downloaded. "
      + "The next job that needs one downloads it again.",
    "cleanup.actionCache.effect":
      "These are the actions your workflows use, checked out here. "
      + "The runner fetches back any it cannot find.",
    "cleanup.standfastTrash.title":
      "Delete Standfast cleanup leftovers from %@?",
    "cleanup.standfastTrash.effect":
      "These cache directories were moved aside by an earlier Standfast cleanup. "
      + "Their old names no longer say which cache they held. Only UUID-named "
      + "leftovers in Standfast's private trash are deleted; current caches and "
      + "other files stay.",
    "cleanup.logs.title.one": "Delete %d old log file from %@?",
    "cleanup.logs.title": "Delete %d old log files from %@?",
    "cleanup.logs.effect.one":
      "%d file nothing has written to in over a week. The log the runner is "
      + "writing now is never deleted, and neither is the history shown in the "
      + "Standfast Control Center.",
    "cleanup.logs.effect":
      "%d files nothing has written to in over a week. The log the runner is "
      + "writing now is never deleted, and neither is the history shown in the "
      + "Standfast Control Center.",
    "cleanup.confirmationUnavailable":
      "Could not ask for confirmation: the screen is locked. Unlock this Mac and try again.",
    "cleanup.refused": "Cleanup stopped: %@ picked up work",
    "cleanup.failed": "Nothing could be deleted; check that %@ is writable",
    "cleanup.partiallyFailed":
      "Some files may have been deleted, but cleanup did not finish; check that %@ is writable",
    "state.noRunners": "No runners installed on this Mac",
    "state.checking": "Checking runners",
    "state.launchAgentsUnreadable": "The LaunchAgents directory could not be read:",
    "state.unreadable": "Some runner files could not be read:",
    "state.unreadable.more": "…and more",
    "state.idle": "Ready — no job right now",
    "state.busy": "Running a job",
    "state.disconnected": "Running locally, but GitHub cannot see it",
    "state.stopped": "Stopped",
    "state.starting": "Starting — waiting for GitHub to see it",
    "state.short.ready": "Ready",
    "state.short.running": "Running",
    "state.short.disconnected": "Disconnected",
    "state.short.stopped": "Stopped",
    "state.short.starting": "Starting",
    "queue.waiting.one":
      "1 job is waiting for this machine",
    "queue.waiting":
      "%d jobs are waiting for this machine",
    "queue.waitingPartial":
      "%d or more jobs are waiting for this machine",
    "queue.empty":
      "No queued work is waiting for this machine",
    "queue.unknownScope":
      "GitHub cannot say what is queued for an organisation runner",
    "state.unknown.noToken":
      "Running locally, GitHub not asked — add a GitHub token in Settings",
    "state.unknown.rateLimited":
      "Running locally, GitHub rate limit reached — it answers again shortly",
    "state.unknown.noCLI":
      "Running locally, GitHub not answering — install the GitHub CLI (gh)",
    "state.unknown.notAuthenticated":
      "Running locally, GitHub not answering — run gh auth login in a terminal",
    "state.unknown.noAnswer":
      "Running locally, GitHub not answering — gh got no answer; check your network",
    "state.unknown.noLocalAnswer":
      "Local service unreadable — launchctl did not answer; try Refresh now",
    "state.unknown.managedFleetWaiting":
      "Fleet slot waiting — the supervisor is preparing its next ephemeral runner",
    "state.unknown.managedFleetUnavailable":
      "Fleet status unavailable — check the runner fleet supervisor on this Mac",
    "state.checkFailed": "Update failed · %@",
    "state.checkedAgo": "Checked %@ ago",
    "state.checkedJustNow": "Checked just now",
    "state.checkedNever": "Not checked yet",
    "job.running": "Running %@ — %@",
    "job.runningWithTypical": "Running %@ — %@, usually %@",
    "job.row": "%@ — %@ (%@)",
    "job.ageAndDuration": "%@ ago · took %@",
    "job.rowNoDuration": "%@ — %@",
    "job.result.succeeded": "Succeeded",
    "job.result.failed": "Failed",
    "job.result.canceled": "Canceled",
    "job.result.interrupted": "Interrupted",
    "operation.inFlight.title": "%@ request in progress",
    "operation.inFlight.detail": "Wait for %@ to return.",
    "operation.accepted.title": "%@ request sent",
    "operation.accepted.detail":
      "%@ returned, but the runner state is not confirmed. Refresh now.",
    "operation.timedOut.title": "%@ request timed out",
    "operation.timedOut.detail": "%@ may still have run. Wait, then Refresh now.",
    "operation.scriptMissing.title": "%@ request could not run",
    "operation.scriptMissing.detail":
      "svc.sh is missing. Reinstall the runner, then try %@ again.",
    "operation.couldNotLaunch.title": "%@ request could not launch",
    "operation.couldNotLaunch.detail": "Check the runner directory, then try %@ again.",
    "operation.unexpectedFailure.title": "%@ request failed",
    "operation.unexpectedFailure.detail": "Check the runner files, then try %@ again.",
    "operation.confirmationUnavailable.title": "%@ confirmation unavailable",
    "operation.confirmationUnavailable.detail":
      "Open the Standfast Control Center, then try %@ again.",
    "operation.restartStartFailed.title":
      "Restart stopped the runner, but could not start it",
    "operation.restartStartFailed.detail": "Check the runner files, then try Start.",
    "operation.restartStartTimedOut.title":
      "Restart stopped the runner, but start timed out",
    "operation.restartStartTimedOut.detail":
      "Start may still have run. Wait, then Refresh now.",
    "thermal.serious": "This Mac is hot and macOS is slowing it down",
    "thermal.critical": "This Mac is very hot and macOS is slowing it right down",
    "thermal.slowingJobs": "That is why the job is taking longer than usual",
    "notification.jobFailed.title": "Job failed",
    "notification.jobFailed.body": "%@ failed on %@",
    "notification.disconnected.title": "Runner disconnected",
    "notification.disconnected.body": "%@ is running here, but GitHub cannot see it",
    "notification.stopped.title": "Runner stopped",
    "notification.stopped.body": "%@ stopped on its own and is taking no jobs",
    "duration.hoursMinutes": "%dh %02dm",
    "duration.minutesSeconds": "%dm %02ds",
    "duration.days": "%dd",
    "duration.hours": "%dh",
    "duration.minutes": "%dm",
    "duration.seconds": "%ds",
  ]

  /// Looks the key up in one complete language pack, and falls back to the
  /// complete English table above.
  ///
  /// The fallback is not defensive padding: this app is assembled into its
  /// `.app` by a shell script, so the catalogues arriving in the wrong place —
  /// or not arriving at all — is a packaging mistake waiting to happen. It has
  /// to cost the user an untranslated menu, and never a blank one, a menu full
  /// of dotted keys, or a crash.
  ///
  /// A language is atomic here: lookups never fill holes in one `.lproj` from
  /// a second bundle that may have negotiated a different language. A damaged
  /// package therefore degrades wholly to built-in English instead of drawing
  /// English actions beside Spanish state copy.
  ///
  /// - Parameter bundles: where to look. Only tests pass this; nil uses the one
  ///   production pack selected at launch, while an empty array asks for the
  ///   no-catalogue fallback explicitly.
  static func t(_ key: String, in bundles: [Bundle]? = nil) -> String {
    let catalogue = bundles.map(completeCatalogue(in:)) ?? activeCatalogue
    return catalogue?[key] ?? english[key] ?? key
  }

  private static let activeCatalogue = completeCatalogue(in: bundles)

  private static func completeCatalogue(in bundles: [Bundle]) -> [String: String]? {
    bundles.lazy.compactMap(completeCatalogue(in:)).first
  }

  private static func completeCatalogue(in bundle: Bundle) -> [String: String]? {
    guard
      let path = bundle.path(forResource: "Localizable", ofType: "strings"),
      let catalogue = NSDictionary(contentsOfFile: path) as? [String: String],
      Set(catalogue.keys) == Set(english.keys),
      catalogue.allSatisfy({ $0.key != $0.value })
    else { return nil }
    return catalogue
  }

  /// SwiftPM's resource bundle, found by looking rather than by asking.
  ///
  /// Not `Bundle.module`. The accessor SwiftPM generates for it calls
  /// `fatalError` when the bundle is not where it expects, and one of the two
  /// places it looks is the absolute build directory the binary was compiled
  /// in. On the machine that built the app that path exists, so nothing ever
  /// goes wrong there; on anybody else's machine it does not, and the first
  /// string the menu asks for kills the process with SIGTRAP. Nothing runs
  /// after a trap, which made the promise in `t` above impossible to keep for
  /// exactly the users it was written for.
  ///
  /// Nil is a normal answer here rather than an error: it means this build
  /// carries no catalogue, and the English above is what the user gets.
  static let resourceBundle: Bundle? = {
    // SwiftPM names this `<package>_<target>.bundle`, so renaming either one
    // renames the file this looks for. The catalogue tests below fail when the
    // two drift, which is the only reason a silent fall back to English does
    // not become the permanent behaviour after a rename.
    let name = "Standfast_Standfast.bundle"
    // `Bundle(for:)` resolves to whatever image this code was loaded from —
    // the `.app` in production, the `.xctest` bundle under `swift test` — and
    // its enclosing directory is where SwiftPM leaves the resource bundle in
    // a plain build. `Bundle.main` covers the assembled `.app`, whose layout
    // Unit 6 decides. None of them is required to exist.
    let own = Bundle(for: BundleToken.self)
    let bases = [
      own.bundleURL, own.bundleURL.deletingLastPathComponent(), own.resourceURL,
      Bundle.main.bundleURL, Bundle.main.resourceURL,
      Bundle.main.executableURL?.deletingLastPathComponent(),
    ]
    return
      bases
      .compactMap { $0 }
      .lazy
      .compactMap { Bundle(url: $0.appendingPathComponent(name)) }
      .first
  }()

  /// Both shapes this app can be packaged in, each narrowed to the language
  /// this Mac asked for. `swift run` leaves the catalogues in the SwiftPM
  /// bundle beside the binary; a hand-assembled `.app` may instead carry them
  /// in `Contents/Resources`.
  static let bundles: [Bundle] = [resourceBundle, Bundle.main]
    .compactMap { $0 }
    .map(speaking)

  /// The same bundle, narrowed to one `.lproj`.
  ///
  /// Negotiated per bundle, and against the user's own preferences rather than
  /// left to `Bundle` — measured, not assumed: with `es-419` at the top of the
  /// user's list and both catalogues sitting in the bundle,
  /// `preferredLocalizations` answers `["en"]`. A bundle negotiates through the
  /// *main* bundle's language, and under `swift run` the main bundle is a bare
  /// executable that declares none, so the Spanish catalogue ships, is found,
  /// and is unreachable. Asking with the user's preferences gets `["es"]`,
  /// which is what they actually said, and still honours a per-app language
  /// override — macOS applies one by rewriting the app's own `AppleLanguages`,
  /// which is exactly what `Locale.preferredLanguages` reads.
  private static func speaking(_ bundle: Bundle) -> Bundle {
    guard
      let language = Bundle.preferredLocalizations(
        from: bundle.localizations, forPreferences: Locale.preferredLanguages
      ).first,
      let directory = bundle.path(forResource: language, ofType: "lproj"),
      let localised = Bundle(path: directory)
    else { return bundle }
    return localised
  }
}

/// Names the image this code was loaded from, which is the only portable way
/// to ask where the binary is without hard-coding a build path.
private final class BundleToken {}
