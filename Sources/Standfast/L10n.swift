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

  static let noRunnersFound = t("state.noRunners")
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
    "menu.runnerRow": "%@ — %@",
    "menu.runnerInScope": "%@ (%@)",
    "state.noRunners": "No runners installed on this Mac",
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
