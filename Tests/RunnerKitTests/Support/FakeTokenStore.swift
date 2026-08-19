import Foundation

@testable import RunnerKit

/// A token in memory. The real one lives in the Keychain, which a test suite
/// must never touch: it would prompt, or persist, on the machine running it.
final class FakeTokenStore: GitHubTokenStoring, @unchecked Sendable {
  struct ReadFailure: Error {}

  private let lock = NSLock()
  private var stored: String?
  /// Thrown instead of answering — a locked Keychain, or a denied item.
  var failsToRead = false

  init(_ token: String? = nil) { stored = token }

  func token() throws -> String? {
    if failsToRead { throw ReadFailure() }
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func store(_ token: String) throws {
    lock.lock()
    defer { lock.unlock() }
    stored = token
  }

  func clear() throws {
    lock.lock()
    defer { lock.unlock() }
    stored = nil
  }
}
