import Foundation
import Security
import Testing

@testable import RunnerKit
@testable import Standfast

/// A token in memory, and a way to make it refuse. The real store is the
/// Keychain, which a suite must never touch.
private final class MemoryTokenStore: GitHubTokenStoring, @unchecked Sendable {
  struct Refused: Error {}

  private let lock = NSLock()
  private let answered = DispatchSemaphore(value: 0)
  private var stored: String?
  private var reads = 0
  private var readsOnMain = 0
  private(set) var writes: [String] = []
  var refusesToRead = false
  var refusesToWrite = false
  /// Holds every read until `answer()`, the way a Keychain dialog holds one
  /// until somebody clicks.
  var holdsReads = false

  init(_ token: String? = nil) { stored = token }

  var readCount: Int { lock.withLock { reads } }
  var readsOnTheMainThread: Int { lock.withLock { readsOnMain } }

  func token() throws -> String? {
    let found = lock.withLock {
      reads += 1
      if Thread.isMainThread { readsOnMain += 1 }
      return stored
    }
    // Bounded, so a read held on the main thread fails the test instead of
    // hanging the suite.
    if holdsReads { _ = answered.wait(timeout: .now() + 5) }
    if refusesToRead { throw Refused() }
    return found
  }

  func answer() { answered.signal() }

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

/// The Keychain after somebody pressed Deny, as the refresh loop's gate sees it.
private final class DeniedKeychain: GitHubTokenStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0

  var readCount: Int { lock.withLock { reads } }

  func token() throws -> String? {
    lock.withLock { reads += 1 }
    throw KeychainTokenStore.KeychainFailure(status: errSecAuthFailed)
  }

  func store(_ token: String) throws {}
  func clear() throws {}
}

@MainActor
@Test func aMachineWithNoTokenSaysSoRatherThanLookingBroken() async {
  // The state every existing user is in. It is not a failure and must not be
  // drawn as one: the app still works, through `gh`.
  let access = GitHubAccess(store: MemoryTokenStore())
  await access.quiesce()

  #expect(access.state == GitHubAccessState.absent)
}

@MainActor
@Test func aTokenAlreadyInTheKeychainIsFoundAtLaunch() async {
  let access = GitHubAccess(store: MemoryTokenStore("ghp_x"))
  await access.quiesce()

  #expect(access.state == .stored)
}

@MainActor
@Test func theKeychainIsNeverReadOnTheMainThread() async {
  // A read can wait on a Keychain dialog until somebody answers it. On the
  // main thread that is a menu bar app frozen behind the dialog at launch.
  let store = MemoryTokenStore("ghp_x")
  let access = GitHubAccess(store: store)
  await access.quiesce()
  store.refusesToWrite = true
  access.save("ghp_y")
  access.remove()
  await access.quiesce()

  #expect(store.readCount >= 2)
  #expect(store.readsOnTheMainThread == 0)
}

@MainActor
@Test func aTokenSavedWhileTheLaunchReadWaitsIsNotUndoneByIt() async {
  // The launch read can sit behind a Keychain dialog for minutes. A token
  // saved meanwhile is newer than whatever that read finds when it returns.
  let store = MemoryTokenStore()
  store.holdsReads = true
  let access = GitHubAccess(store: store)
  // Into the store first, or the read would start after the save and find it.
  for _ in 0..<500 where store.readCount == 0 {
    try? await Task.sleep(for: .milliseconds(10))
  }

  access.save("ghp_x")
  store.answer()
  await access.quiesce()

  #expect(access.state == .stored)
}

@MainActor
@Test func savingATokenLetsTheRefreshAskTheKeychainAgain() {
  // After a Deny the refresh loop stops asking, or the dialog would be back
  // every fifteen seconds. A token saved in Settings is somebody answering.
  let keychain = DeniedKeychain()
  let gate = UnattendedTokenStore(keychain)
  _ = try? gate.token()
  let access = GitHubAccess(store: MemoryTokenStore(), unattended: gate)

  access.save("ghp_x")
  _ = try? gate.token()

  #expect(keychain.readCount == 2)
}

@MainActor
@Test func removingATokenLetsTheRefreshFallBackToGh() {
  // Still holding the Deny, the loop would report a Keychain refusal about a
  // token that is gone, instead of finding nothing and asking `gh`.
  let keychain = DeniedKeychain()
  let gate = UnattendedTokenStore(keychain)
  _ = try? gate.token()
  let access = GitHubAccess(store: MemoryTokenStore("ghp_x"), unattended: gate)

  access.remove()
  _ = try? gate.token()

  #expect(keychain.readCount == 2)
}

@MainActor
@Test func aWriteTheKeychainRefusesStillLetsTheRefreshAskAgain() async {
  // After an upgrade the Keychain can refuse this binary the write as well as
  // the read. Holding the Deny then leaves a relaunch as the only way back, and
  // whoever pressed the button is there to answer a new dialog.
  let keychain = DeniedKeychain()
  let gate = UnattendedTokenStore(keychain)
  _ = try? gate.token()
  let store = MemoryTokenStore("ghp_x")
  store.refusesToWrite = true
  let access = GitHubAccess(store: store, unattended: gate)
  await access.quiesce()

  access.save("ghp_y")
  _ = try? gate.token()
  #expect(keychain.readCount == 2)

  access.remove()
  _ = try? gate.token()
  #expect(keychain.readCount == 3)
}

@MainActor
@Test func theLaunchReadAndTheRefreshRaiseOneKeychainDialogBetweenThem() async {
  // After an upgrade the Keychain asks about the new binary once per read, and
  // Always Allow on one dialog does not dismiss another. Settings and the first
  // refresh both read the item at launch.
  let keychain = MemoryTokenStore("ghp_x")
  keychain.holdsReads = true
  let gate = UnattendedTokenStore(keychain, patience: .milliseconds(50))
  let access = GitHubAccess(store: keychain, unattended: gate)
  for _ in 0..<500 where keychain.readCount == 0 {
    try? await Task.sleep(for: .milliseconds(10))
  }

  _ = try? gate.token()
  keychain.answer()
  await access.quiesce()

  #expect(keychain.readCount == 1)
  // Past the refresh loop's patience, and still answered: nothing queues behind
  // this read, so it waits for whoever is at the dialog.
  #expect(access.state == .stored)
}

@Test func theAppHandsEachSettingsCardTheGateOnItsOwnToken() {
  // Without its gate, a card cannot lift a Deny and only a relaunch can.
  // Crossed, the GitLab card would share a dialog with the GitHub token.
  let app = standfastSource("App.swift").filter { !$0.isWhitespace }
  let gitLab = standfastSource("GitLabInstanceAccess.swift").filter { !$0.isWhitespace }

  #expect(app.contains("GitHubAccess(unattended:.gitHub)"))
  #expect(
    gitLab.contains(
      "GitHubAccess(store:GitLabAPIClient.tokenStore(for:instance),"
        + "unattended:.gitLab(for:instance))"))
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
@Test func anEmptyFieldIsNotStoredAsAToken() async {
  // Otherwise pressing Save on an empty field replaces a working credential
  // with a blank one, and every later request is refused.
  let store = MemoryTokenStore("ghp_existing")
  let access = GitHubAccess(store: store)

  access.save("   ")
  await access.quiesce()

  #expect(store.writes.isEmpty)
  #expect(access.state == .stored)
}

@MainActor
@Test func removingATokenLeavesTheMachineOnTheCliPath() async {
  let access = GitHubAccess(store: MemoryTokenStore("ghp_x"))

  access.remove()
  await access.quiesce()

  #expect(access.state == .absent)
}

@MainActor
@Test func aKeychainThatWillNotAnswerIsNotAnEmptyKeychain() async {
  // Reading `.absent` from a refusal would send the app quietly down the `gh`
  // path and tell the user nothing was configured, when something was.
  let store = MemoryTokenStore("ghp_x")
  store.refusesToRead = true
  let access = GitHubAccess(store: store)
  await access.quiesce()

  #expect(access.state == .unreadable)
}

@MainActor
@Test func aRefusedWriteIsReportedRatherThanShownAsSuccess() async {
  let store = MemoryTokenStore()
  store.refusesToWrite = true
  let access = GitHubAccess(store: store)

  access.save("ghp_x")
  await access.quiesce()

  #expect(access.state == .absent)
  #expect(access.notice != nil)
}

@MainActor
@Test func aRefusedRemovalSaysTheTokenIsStillThere() async {
  // The save failure's sentence describes the other button. Under Remove it
  // reads as a new token that failed to save, and never says the old one is
  // still stored.
  let store = MemoryTokenStore("ghp_x")
  let access = GitHubAccess(store: store)
  store.refusesToWrite = true

  access.remove()
  await access.quiesce()

  #expect(access.state == .stored)
  #expect(access.notice != L10n.settingsGitHubKeychainFailed)
  #expect(access.notice == L10n.settingsGitHubKeychainRemoveFailed)
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
