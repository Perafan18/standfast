import Foundation
import Testing

@testable import RunnerKit

/// The real Keychain, behind a flag.
///
/// Not in CI on purpose, and the same trade the render harness makes. These
/// tests write a real item to the login keychain of whoever runs them: on a
/// machine where that keychain is locked — a runner started by launchd, a
/// headless agent — they would fail for a reason that has nothing to do with
/// this code, and a gate that fails for the wrong reason is worse than no gate.
/// Everything above this class is tested against `FakeTokenStore`.
///
/// Run them:
///
/// ```sh
/// STANDFAST_KEYCHAIN_TESTS=1 swift test --filter Keychain
/// ```
private let keychainTestsEnabled =
  ProcessInfo.processInfo.environment["STANDFAST_KEYCHAIN_TESTS"] == "1"

/// A service nobody else uses, so a failed run cannot leave anything behind
/// that a later run would read as its own.
private func throwawayStore() -> KeychainTokenStore {
  KeychainTokenStore(service: "dev.standfast.tests.\(UUID().uuidString)")
}

@Test(.enabled(if: keychainTestsEnabled))
func nothingStoredReadsAsNothingRatherThanAsAFailure() throws {
  // The distinction the whole fallback rests on: an empty Keychain is a
  // machine that has not been set up, and it must not look like one whose
  // Keychain refused to answer.
  #expect(try throwawayStore().token() == nil)
}

@Test(.enabled(if: keychainTestsEnabled))
func aStoredTokenComesBackWhole() throws {
  let store = throwawayStore()
  defer { try? store.clear() }

  try store.store("ghp_example_token")

  #expect(try store.token() == "ghp_example_token")
}

@Test(.enabled(if: keychainTestsEnabled))
func storingTwiceReplacesRatherThanDuplicates() throws {
  // `SecItemAdd` on an item that exists fails with a duplicate error. Pasting
  // a second token has to work: it is precisely what someone does when the
  // first one expired.
  let store = throwawayStore()
  defer { try? store.clear() }

  try store.store("first")
  try store.store("second")

  #expect(try store.token() == "second")
}

@Test(.enabled(if: keychainTestsEnabled))
func clearingLeavesNothingBehind() throws {
  let store = throwawayStore()
  try store.store("ghp_example_token")

  try store.clear()

  #expect(try store.token() == nil)
}

@Test(.enabled(if: keychainTestsEnabled))
func clearingSomethingThatWasNeverThereIsNotAFailure() throws {
  // Otherwise the Settings button that removes a token would report an error
  // to anyone who pressed it twice.
  #expect(throws: Never.self) { try throwawayStore().clear() }
}
