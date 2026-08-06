import Foundation

/// Every user-facing string, in one place.
///
/// Call sites say `L10n.start`, so replacing `.strings` with a String Catalog,
/// or dropping the catalogue entirely, touches this file and nothing else.
enum L10n {
  static let start = t("menu.start")
  static let stop = t("menu.stop")
  static let restart = t("menu.restart")
  static let openOnGitHub = t("menu.openOnGitHub")
  static let refreshNow = t("menu.refreshNow")
  static let quit = t("menu.quit")
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

  static let maintenance = t("menu.maintenance")
  static let measureDiskUse = t("menu.maintenance.measure")
  static let deletingOnlyWhenIdle = t("menu.maintenance.onlyWhenIdle")

  static let diskWorking = t("disk.working")
  static let diskNotMeasured = t("disk.notMeasured")
  static let diskMeasuredJustNow = t("disk.measuredJustNow")
  static let diskUnavailable = t("disk.unavailable")

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
  static let launchAgentsUnreadable = t("state.launchAgentsUnreadable")
  static let someRunnersUnreadable = t("state.unreadable")
  static let moreUnreadable = t("state.unreadable.more")

  static let stateIdle = t("state.idle")
  static let stateBusy = t("state.busy")
  static let stateDisconnected = t("state.disconnected")
  static let stateStopped = t("state.stopped")
  static let stateStarting = t("state.starting")

  // One line per `UnknownReason`, because each one has a different next step
  // and "unknown" on its own has none. This is the likeliest thing a new user
  // sees, so the line has to be the instruction.
  static let stateUnknownNoCLI = t("state.unknown.noCLI")
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

  /// A runner's name and its state on one line. Localised because the dash and
  /// the spacing around it are not punctuation every language writes the same.
  static func runnerRow(_ name: String, _ state: String) -> String {
    String(format: t("menu.runnerRow"), name, state)
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

  static func cleanupLogsTitle(_ count: Int, _ path: String) -> String {
    String(format: t("cleanup.logs.title"), count, path)
  }

  static func cleanupLogsEffect(_ count: Int) -> String {
    String(format: t("cleanup.logs.effect"), count)
  }

  /// Said when the runner picked up work between the confirmation and the
  /// deletion. The one outcome that has to be reported, because the user asked
  /// for something and did not get it.
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
    "menu.start": "Start",
    "menu.stop": "Stop",
    "menu.restart": "Restart",
    "menu.openOnGitHub": "Open on GitHub",
    "menu.refreshNow": "Refresh now",
    "menu.quit": "Quit",
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
    "menu.maintenance.onlyWhenIdle":
      "Deleting is offered while this runner is idle or stopped",
    "menu.runnerVersion": "Runner %@",
    "menu.runnerVersion.update": "Runner %@ — %@ is available",
    "menu.runnerRow": "%@ — %@",
    "menu.runnerInScope": "%@ (%@)",
    "disk.toolCache": "Tool cache — %@",
    "disk.actionCache": "Downloaded actions — %@",
    "disk.checkout": "Repository checkouts — %@",
    "disk.temporary": "Job scratch space — %@",
    "disk.other": "Other runner files — %@",
    "disk.standfastTrash": "Standfast cleanup leftovers — %@",
    "disk.logs": "Logs — %@",
    "disk.working": "Working…",
    "disk.notMeasured": "Disk use not measured yet",
    "disk.measuredJustNow": "Measured just now",
    "disk.measuredAgo": "Measured %@ ago",
    "disk.unavailable": "Disk use could not be measured",
    "cleanup.confirm.title": "Delete %@?",
    "cleanup.confirm.body": "This frees %@ on %@.",
    "cleanup.confirm.delete": "Delete",
    "cleanup.confirm.cancel": "Cancel",
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
    "cleanup.logs.title": "Delete %d old log files from %@?",
    "cleanup.logs.effect":
      "%d files nothing has written to in over a week. The log the runner is "
      + "writing now is never deleted, and neither is the history this menu shows.",
    "cleanup.refused": "Cleanup stopped: %@ picked up work",
    "cleanup.failed": "Nothing could be deleted; check that %@ is writable",
    "cleanup.partiallyFailed":
      "Some files were deleted, but cleanup did not finish; check that %@ is writable",
    "state.noRunners": "No runners installed on this Mac",
    "state.launchAgentsUnreadable": "The LaunchAgents directory could not be read:",
    "state.unreadable": "Some runner files could not be read:",
    "state.unreadable.more": "…and more",
    "state.idle": "Idle — ready for jobs",
    "state.busy": "Running a job",
    "state.disconnected": "Running locally, but GitHub cannot see it",
    "state.stopped": "Stopped",
    "state.starting": "Starting — waiting for GitHub to see it",
    "state.unknown.noCLI": "Unknown — install the GitHub CLI (gh)",
    "state.unknown.notAuthenticated": "Unknown — run gh auth login in a terminal",
    "state.unknown.noAnswer": "Unknown — gh got no answer; check your network",
    "state.unknown.noLocalAnswer": "Unknown — launchctl did not answer; try Refresh now",
    "state.checkedAgo": "Checked %@ ago",
    "state.checkedJustNow": "Checked just now",
    "state.checkedNever": "Not checked yet",
    "job.running": "Running %@ — %@",
    "job.runningWithTypical": "Running %@ — %@, usually %@",
    "job.row": "%@ — %@ (%@)",
    "job.rowNoDuration": "%@ — %@",
    "job.result.succeeded": "Succeeded",
    "job.result.failed": "Failed",
    "job.result.canceled": "Canceled",
    "job.result.interrupted": "Interrupted",
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
    "duration.hours": "%dh",
    "duration.minutes": "%dm",
    "duration.seconds": "%ds",
  ]

  /// Looks the key up in the catalogues, and falls back to the English above.
  ///
  /// The fallback is not defensive padding: this app is assembled into its
  /// `.app` by a shell script, so the catalogues arriving in the wrong place —
  /// or not arriving at all — is a packaging mistake waiting to happen. It has
  /// to cost the user an untranslated menu, and never a blank one, a menu full
  /// of dotted keys, or a crash.
  ///
  /// - Parameter bundles: where to look. Only a test passes this, and it is
  ///   the one way to ask what the menu says with no catalogue whatsoever.
  static func t(_ key: String, in bundles: [Bundle] = L10n.bundles) -> String {
    for bundle in bundles {
      // A sentinel rather than the key: `localizedString` echoes the key back
      // when the lookup misses *and* when a catalogue genuinely maps the key
      // to itself, and those need telling apart.
      let found = bundle.localizedString(forKey: key, value: missing, table: nil)
      if found != missing { return found }
    }
    return english[key] ?? key
  }

  private static let missing = "\u{0}no such key"

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
