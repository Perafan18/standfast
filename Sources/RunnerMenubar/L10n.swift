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

  /// A runner's name and its state on one line. Localised because the dash and
  /// the spacing around it are not punctuation every language writes the same.
  static func runnerRow(_ name: String, _ state: String) -> String {
    String(format: t("menu.runnerRow"), name, state)
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
    "menu.runnerRow": "%@ — %@",
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
    let name = "RunnerMenubar_RunnerMenubar.bundle"
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

  /// The language this Mac asked for, out of the ones this app ships.
  ///
  /// Measured, not assumed: with `es-419` at the top of the user's list and
  /// both catalogues sitting in the bundle, `preferredLocalizations` answers
  /// `["en"]`. A bundle negotiates through the *main* bundle's language, and
  /// under `swift run` the main bundle is a bare executable that declares
  /// none — so the Spanish catalogue ships, is found, and is unreachable.
  ///
  /// Asking with the user's own preferences skips that negotiation and gets
  /// `["es"]`, which is what the user actually said. It still honours a
  /// per-app language override, because macOS applies one by rewriting the
  /// app's own `AppleLanguages`, which is what `Locale.preferredLanguages`
  /// reads. Inside a properly assembled `.app` the negotiation would work by
  /// itself; this keeps it working everywhere else as well.
  static let localization = Bundle.preferredLocalizations(
    from: resourceBundle?.localizations ?? [], forPreferences: Locale.preferredLanguages
  ).first

  /// Both shapes this app can be packaged in, each narrowed to the chosen
  /// language. `swift run` leaves the catalogues in the SwiftPM bundle beside
  /// the binary; a hand-assembled `.app` may instead carry them in
  /// `Contents/Resources`.
  static let bundles: [Bundle] = [resourceBundle, Bundle.main]
    .compactMap { $0 }
    .map(speaking)

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
