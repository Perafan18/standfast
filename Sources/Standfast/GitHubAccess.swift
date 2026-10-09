import Foundation
import RunnerKit

/// Whether this Mac has a GitHub token of its own, as the Keychain has it.
enum GitHubAccessState: Equatable {
  /// A token is there. The app asks GitHub directly and needs no `gh`.
  case stored
  /// Nothing stored. Not a failure: it is the state every machine starts in
  /// and every existing user is already in, and the app still works through
  /// the `gh` CLI.
  case absent
  /// The Keychain exists and would not say. Deliberately not folded into
  /// `.absent` — reading a refusal as "nothing configured" would send the app
  /// quietly down the CLI path and tell the user nothing was set up, when
  /// something was.
  case unreadable
}

/// Owns the GitHub token the way `LoginItem` owns the login registration: one
/// long-lived object, observed by Settings, that never hands the secret back
/// out.
///
/// There is no accessor for the token itself, and that is the point. The
/// Settings surface needs to know whether one exists, not what it says, and a
/// property returning it would be a live GitHub credential one screenshot away
/// from being published.
@MainActor
final class GitHubAccess: ObservableObject {
  @Published private(set) var state: GitHubAccessState
  /// What went wrong the last time this app tried to write to the Keychain,
  /// and nil when nothing did.
  @Published private(set) var notice: String?

  private let store: any GitHubTokenStoring
  /// The refresh loop's gate on the same item. It stops asking once somebody
  /// refuses, and only Save or Remove here says to ask again.
  private let unattended: UnattendedTokenStore?
  private var pendingRead: Task<Void, Never>?

  init(
    store: any GitHubTokenStoring = KeychainTokenStore(),
    unattended: UnattendedTokenStore? = nil
  ) {
    self.store = store
    self.unattended = unattended
    // Until the Keychain answers it has not said, and calling that `.absent`
    // would claim nothing is stored.
    state = .unreadable
    reread()
  }

  /// Waits for the Keychain read in flight. Nothing in the app needs this; a
  /// test does.
  func quiesce() async { await pendingRead?.value }

  /// Off the main actor, because a read can wait on a Keychain dialog for as
  /// long as nobody answers it, and the menu bar would freeze behind it.
  private func reread() {
    pendingRead?.cancel()
    let store = store
    let unattended = unattended
    pendingRead = Task {
      let found = await offCooperativePool { Self.reading(store, through: unattended) }
      // Superseded by a write that finished first, or by a later read.
      guard !Task.isCancelled else { return }
      state = found
    }
  }

  nonisolated private static func reading(
    _ store: any GitHubTokenStoring, through unattended: UnattendedTokenStore?
  ) -> GitHubAccessState {
    do {
      // Through the refresh loop's read where there is one: after an upgrade
      // each read raises its own dialog, and Always Allow on one does not
      // dismiss the other.
      let token =
        if let unattended { try unattended.tokenOnceAnswered() } else { try store.token() }
      return token == nil ? .absent : .stored
    } catch {
      return .unreadable
    }
  }

  func save(_ token: String) {
    // Copying a token out of a browser or a terminal brings whitespace and a
    // newline with it, and GitHub refuses the header that results. The failure
    // would arrive worded as "token refused", which is the wrong thing to tell
    // someone who pasted exactly the right token.
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    // An empty field is not an instruction to erase a working credential.
    guard !trimmed.isEmpty else { return }
    // Whether or not the write lands: whoever pressed the button can answer a
    // new dialog, and after an upgrade the Keychain may refuse this binary the
    // write too, leaving nothing else to lift a Deny.
    unattended?.forgetRefusal()
    do {
      try store.store(trimmed)
      pendingRead?.cancel()
      notice = nil
      state = .stored
    } catch {
      notice = L10n.settingsGitHubKeychainFailed
      reread()
    }
  }

  func remove() {
    unattended?.forgetRefusal()
    do {
      try store.clear()
      notice = nil
    } catch {
      notice = L10n.settingsGitHubKeychainRemoveFailed
    }
    reread()
  }
}
