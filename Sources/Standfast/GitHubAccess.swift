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

  init(store: any GitHubTokenStoring = KeychainTokenStore()) {
    self.store = store
    state = Self.reading(store)
  }

  private static func reading(_ store: any GitHubTokenStoring) -> GitHubAccessState {
    do {
      return try store.token() == nil ? .absent : .stored
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
    do {
      try store.store(trimmed)
      notice = nil
      state = .stored
    } catch {
      notice = L10n.settingsGitHubKeychainFailed
      state = Self.reading(store)
    }
  }

  func remove() {
    do {
      try store.clear()
      notice = nil
    } catch {
      notice = L10n.settingsGitHubKeychainFailed
    }
    state = Self.reading(store)
  }
}
