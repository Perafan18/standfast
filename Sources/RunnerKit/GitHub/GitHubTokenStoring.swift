import Foundation

/// Where the GitHub token lives.
///
/// A protocol rather than a Keychain call at the point of use, because a test
/// suite must never touch the real Keychain: it would prompt on the machine
/// running it, or leave a credential behind on a build agent.
public protocol GitHubTokenStoring: Sendable {
  /// Nil when nothing has been stored. Throwing is a different answer: the
  /// Keychain exists and would not say, which is not the same as empty.
  func token() throws -> String?
  func store(_ token: String) throws
  func clear() throws
}
