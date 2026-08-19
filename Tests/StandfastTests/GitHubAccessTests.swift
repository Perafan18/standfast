import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// A token in memory, and a way to make it refuse. The real store is the
/// Keychain, which a suite must never touch.
private final class MemoryTokenStore: GitHubTokenStoring, @unchecked Sendable {
  struct Refused: Error {}

  private let lock = NSLock()
  private var stored: String?
  private(set) var writes: [String] = []
  var refusesToRead = false
  var refusesToWrite = false

  init(_ token: String? = nil) { stored = token }

  func token() throws -> String? {
    if refusesToRead { throw Refused() }
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func store(_ token: String) throws {
    if refusesToWrite { throw Refused() }
    lock.lock()
    defer { lock.unlock() }
    writes.append(token)
    stored = token
  }

  func clear() throws {
    if refusesToWrite { throw Refused() }
    lock.lock()
    defer { lock.unlock() }
    stored = nil
  }
}

@MainActor
@Test func aMachineWithNoTokenSaysSoRatherThanLookingBroken() {
  // The state every existing user is in. It is not a failure and must not be
  // drawn as one: the app still works, through `gh`.
  #expect(GitHubAccess(store: MemoryTokenStore()).state == GitHubAccessState.absent)
}

@MainActor
@Test func aTokenAlreadyInTheKeychainIsFoundAtLaunch() {
  #expect(GitHubAccess(store: MemoryTokenStore("ghp_x")).state == .stored)
}

@MainActor
@Test func savingATokenStoresItAndSaysItIsStored() {
  let store = MemoryTokenStore()
  let access = GitHubAccess(store: store)

  access.save("ghp_x")

  #expect(store.writes == ["ghp_x"])
  #expect(access.state == .stored)
}

@MainActor
@Test func aPastedTokenIsTrimmedBeforeItIsStored() {
  // Copying a token out of a browser or a terminal brings whitespace and a
  // newline with it, and GitHub refuses the header that results. The failure
  // would arrive as "token refused", which is exactly the wrong thing to tell
  // someone who pasted the right token.
  let store = MemoryTokenStore()

  GitHubAccess(store: store).save("  ghp_x\n")

  #expect(store.writes == ["ghp_x"])
}

@MainActor
@Test func anEmptyFieldIsNotStoredAsAToken() {
  // Otherwise pressing Save on an empty field replaces a working credential
  // with a blank one, and every later request is refused.
  let store = MemoryTokenStore("ghp_existing")
  let access = GitHubAccess(store: store)

  access.save("   ")

  #expect(store.writes.isEmpty)
  #expect(access.state == .stored)
}

@MainActor
@Test func removingATokenLeavesTheMachineOnTheCliPath() {
  let access = GitHubAccess(store: MemoryTokenStore("ghp_x"))

  access.remove()

  #expect(access.state == .absent)
}

@MainActor
@Test func aKeychainThatWillNotAnswerIsNotAnEmptyKeychain() {
  // Reading `.absent` from a refusal would send the app quietly down the `gh`
  // path and tell the user nothing was configured, when something was.
  let store = MemoryTokenStore("ghp_x")
  store.refusesToRead = true

  #expect(GitHubAccess(store: store).state == .unreadable)
}

@MainActor
@Test func aRefusedWriteIsReportedRatherThanShownAsSuccess() {
  let store = MemoryTokenStore()
  store.refusesToWrite = true
  let access = GitHubAccess(store: store)

  access.save("ghp_x")

  #expect(access.state == .absent)
  #expect(access.notice != nil)
}

@MainActor
@Test func aSuccessfulSaveClearsAnEarlierComplaint() {
  let store = MemoryTokenStore()
  store.refusesToWrite = true
  let access = GitHubAccess(store: store)
  access.save("ghp_x")

  store.refusesToWrite = false
  access.save("ghp_x")

  #expect(access.notice == nil)
  #expect(access.state == .stored)
}
