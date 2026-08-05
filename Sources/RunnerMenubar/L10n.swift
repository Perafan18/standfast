import Foundation

/// Every user-facing string, in one place.
///
/// Call sites say `L10n.start`, so replacing `.strings` with a String Catalog,
/// or dropping the catalogue entirely, touches this file and nothing else.
enum L10n {
  static let start = t("menu.start", "Start")
  static let stop = t("menu.stop", "Stop")
  static let restart = t("menu.restart", "Restart")
  static let openOnGitHub = t("menu.openOnGitHub", "Open on GitHub")
  static let refreshNow = t("menu.refreshNow", "Refresh now")
  static let quit = t("menu.quit", "Quit")

  static let noRunnersFound = t("state.noRunners", "No runners installed on this Mac")
  static let someRunnersUnreadable =
    t("state.unreadable", "Some runner files could not be read:")

  static let stateIdle = t("state.idle", "Idle — ready for jobs")
  static let stateBusy = t("state.busy", "Running a job")
  static let stateDisconnected =
    t("state.disconnected", "Running locally, but GitHub cannot see it")
  static let stateStopped = t("state.stopped", "Stopped")
  static let stateStarting =
    t("state.starting", "Starting — waiting for GitHub to see it")

  // One line per `UnknownReason`, because each one has a different next step
  // and "unknown" on its own has none. This is the likeliest thing a new user
  // sees, so the line has to be the instruction.
  static let stateUnknownNoCLI =
    t("state.unknown.noCLI", "Unknown — install the GitHub CLI (gh)")
  static let stateUnknownNotAuthenticated =
    t("state.unknown.notAuthenticated", "Unknown — run gh auth login in a terminal")
  static let stateUnknownNoAnswer =
    t("state.unknown.noAnswer", "Unknown — gh got no answer; check your network")

  /// Looks the key up, and falls back to the English written above.
  ///
  /// The fallback is not defensive padding: this app is assembled into its
  /// `.app` by a shell script, so the `.lproj` directories arriving in the
  /// wrong place is a packaging mistake waiting to happen. It must cost the
  /// user an untranslated menu, never a blank one or a menu full of dotted
  /// keys.
  ///
  /// Two bundles because there are two shapes. `swift run` leaves the
  /// resources in the SwiftPM bundle beside the binary, which is
  /// `Bundle.module`; a real `.app` may instead carry them in
  /// `Contents/Resources`, which is `Bundle.main`.
  /// Not private: the fallback is the part that has to keep working when the
  /// catalogues do not ship, and no key reachable through the constants above
  /// can ever miss, so a test has to be able to ask for one that does.
  static func t(_ key: String, _ fallback: String) -> String {
    for bundle in bundles {
      // A sentinel rather than the key: `localizedString` echoes the key back
      // when the lookup misses *and* when a catalogue genuinely maps the key
      // to itself, and those need telling apart.
      let found = bundle.localizedString(forKey: key, value: missing, table: nil)
      if found != missing { return found }
    }
    return fallback
  }

  private static let missing = "\u{0}no such key"

  /// Where SwiftPM puts the `.lproj` directories. Not private so a test can
  /// read the catalogues directly — going through `L10n` would only report
  /// which language the test host happens to boot in.
  static let resourceBundle = Bundle.module

  /// The language this Mac asked for, out of the ones this app ships.
  ///
  /// Measured, not assumed: with `es-419` at the top of the user's list and
  /// both catalogues present, `Bundle.module.preferredLocalizations` answers
  /// `["en"]`. A bundle negotiates through the *main* bundle's language, and
  /// this app's main bundle declares no localizations at all — a bare
  /// executable under `swift run`, and a hand-assembled `.app` in Unit 6
  /// unless somebody remembers to list them. So the Spanish catalogue ships,
  /// is found, and is never reachable.
  ///
  /// Asking with the user's own preferences skips that negotiation and gets
  /// `["es"]`, which is what the user actually said. It still honours a
  /// per-app language override, because macOS applies that by rewriting the
  /// app's own `AppleLanguages`, which is what `Locale.preferredLanguages`
  /// reads.
  static let localization = Bundle.preferredLocalizations(
    from: resourceBundle.localizations, forPreferences: Locale.preferredLanguages
  ).first

  /// Both shapes this app can be packaged in, each narrowed to the chosen
  /// language. `swift run` leaves the catalogues in the SwiftPM bundle beside
  /// the binary; a hand-assembled `.app` may instead carry them in
  /// `Contents/Resources`.
  private static let bundles: [Bundle] = [resourceBundle, Bundle.main].map(speaking)

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
