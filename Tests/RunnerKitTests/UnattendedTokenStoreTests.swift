import Foundation
import Security
import Testing

@testable import RunnerKit

/// A Keychain read that can be held open, the way a real one is while a dialog
/// waits for somebody to unlock the keychain or allow the app.
private final class HeldTokenStore: GitHubTokenStoring, @unchecked Sendable {
  private let lock = NSLock()
  private let released = DispatchSemaphore(value: 0)
  private var held: Bool
  private var answer: Result<String?, any Error>
  private var reads = 0

  init(_ answer: Result<String?, any Error> = .success("ghp_x"), held: Bool = false) {
    self.answer = answer
    self.held = held
  }

  var readCount: Int { lock.withLock { reads } }

  func token() throws -> String? {
    let (isHeld, answer) = lock.withLock {
      reads += 1
      return (held, self.answer)
    }
    // Bounded, so a store that waits on it fails the test instead of hanging
    // the suite.
    if isHeld { _ = released.wait(timeout: .now() + 5) }
    return try answer.get()
  }

  func release() {
    lock.withLock { held = false }
    released.signal()
  }

  func store(_ token: String) throws {}
  func clear() throws {}
}

/// Keychain reads that each wait on a dialog of their own, so a test can say
/// which of two dialogs on screen somebody answered first.
private final class OneDialogPerRead: GitHubTokenStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var dialogs: [DispatchSemaphore] = []

  var readCount: Int { lock.withLock { dialogs.count } }

  func token() throws -> String? {
    let dialog = DispatchSemaphore(value: 0)
    lock.withLock { dialogs.append(dialog) }
    // Bounded, so a store that waits on it fails the test instead of hanging
    // the suite.
    _ = dialog.wait(timeout: .now() + 5)
    return "ghp_x"
  }

  func answer(_ read: Int) { lock.withLock { dialogs[read] }.signal() }

  func store(_ token: String) throws {}
  func clear() throws {}
}

private let turnedAway = KeychainTokenStore.KeychainFailure(
  status: errSecInteractionNotAllowed)

/// A read made on another thread, kept until the test asks how it went.
private final class Outcome: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<String?, any Error>?

  var token: String? {
    lock.withLock {
      guard case .success(let token) = result else { return nil }
      return token
    }
  }

  var failure: KeychainTokenStore.KeychainFailure? {
    lock.withLock {
      guard case .failure(let failure) = result else { return nil }
      return failure as? KeychainTokenStore.KeychainFailure
    }
  }

  func record(_ read: () throws -> String?) {
    let result = Result { try read() }
    lock.withLock { self.result = result }
  }
}

/// Polls instead of sleeping a fixed time, so a slow machine costs a slower
/// test rather than a wrong verdict.
private func eventually(_ condition: () -> Bool) -> Bool {
  for _ in 0..<500 {
    if condition() { return true }
    Thread.sleep(forTimeInterval: 0.01)
  }
  return condition()
}

private func child(_ subject: Any, _ label: String) -> Any? {
  Mirror(reflecting: subject).children.first { $0.label == label }?.value
}

@Test func aKeychainWaitingOnADialogDoesNotHoldTheRefreshBehindIt() {
  // A locked login keychain, or an access list that no longer names this
  // binary, parks the read until somebody answers. Every runner after this one
  // would go unread, and no notification would fire, for as long as that takes.
  let keychain = HeldTokenStore(held: true)
  defer { keychain.release() }
  let store = UnattendedTokenStore(keychain, patience: .milliseconds(100))

  #expect(throws: turnedAway) { try store.token() }
}

@Test func aSecondReadWhileTheFirstWaitsIsTurnedAwayWithoutAskingTheKeychain() {
  // Each read that reaches the Keychain can raise a dialog of its own: one per
  // runner per refresh, stacked behind the first.
  let keychain = HeldTokenStore(held: true)
  defer { keychain.release() }
  let store = UnattendedTokenStore(keychain, patience: .milliseconds(300))
  Thread.detachNewThread { _ = try? store.token() }
  #expect(eventually { keychain.readCount == 1 })

  #expect(throws: turnedAway) { try store.token() }
  #expect(keychain.readCount == 1)
}

@Test func aReadThatLandsWhileAnotherIsAnsweredGetsTheSameToken() throws {
  // The release check runs beside the first scan of every launch. Turned away
  // from a Keychain about to answer, the loser reads as GitHub not answering,
  // and a Mac with no token never reaches `gh`.
  let keychain = HeldTokenStore(held: true)
  let store = UnattendedTokenStore(keychain, patience: .seconds(5))
  let first = Outcome()
  Thread.detachNewThread { first.record { try store.token() } }
  #expect(eventually { keychain.readCount == 1 })

  DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
    keychain.release()
  }

  #expect(try store.token() == "ghp_x")
  #expect(eventually { first.token == "ghp_x" })
}

@Test func aReadThatOutlastedItsWaitTurnsTheRestOfTheScanAwayAtOnce() {
  // The scan reads runner by runner. Each of them waiting out the same dialog
  // in turn would hold a refresh for the wait times the number of runners.
  let keychain = HeldTokenStore(held: true)
  defer { keychain.release() }
  let store = UnattendedTokenStore(keychain, patience: .milliseconds(500))
  _ = try? store.token()

  let rest = ContinuousClock().measure {
    for _ in 0..<3 { _ = try? store.token() }
  }

  #expect(rest < .milliseconds(500))
}

@Test func theKeychainIsAskedAgainOnceTheDialogIsAnswered() {
  let keychain = HeldTokenStore(held: true)
  let store = UnattendedTokenStore(keychain, patience: .milliseconds(50))
  _ = try? store.token()

  keychain.release()

  #expect(eventually { (try? store.token()) == "ghp_x" })
}

@Test func aKeychainThatAnswersIsPassedStraightThrough() throws {
  // Nil included: an empty Keychain is what sends the GitHub client to `gh`.
  #expect(try UnattendedTokenStore(HeldTokenStore(.success("ghp_x"))).token() == "ghp_x")
  #expect(try UnattendedTokenStore(HeldTokenStore(.success(nil))).token() == nil)
}

@Test func theClientsTheAppPollsWithReadThroughTheGate() throws {
  // The refresh loop reads once per runner. Handed a raw Keychain store, each
  // of those reads can raise its own dialog and hold the scan behind it.
  let gitHubTokens = child(TokenFirstGitHubClient.standard, "token").flatMap {
    child($0, "tokens")
  }
  let instance = try #require(GitLabInstance(url: "https://gitlab.example.com"))
  let gitLabTokens =
    child(GitLabAPIClient.standard, "tokens")
    as? @Sendable (GitLabInstance) -> any GitHubTokenStoring

  #expect((gitHubTokens as? UnattendedTokenStore) === UnattendedTokenStore.gitHub)
  #expect(
    (gitLabTokens?(instance) as? UnattendedTokenStore)
      === UnattendedTokenStore.gitLab(for: instance))
}

@Test func eachGateReadsItsOwnProvidersAndInstancesToken() throws {
  // Crossed, the GitLab client would send the GitHub token to a GitLab host,
  // or one instance's token to another instance.
  let first = try #require(GitLabInstance(url: "https://gitlab.example.com"))
  let second = try #require(GitLabInstance(url: "https://git.example.org:8443/gitlab"))
  let account = { (gate: UnattendedTokenStore) in
    child(gate, "underlying").flatMap { child($0, "account") } as? String
  }

  #expect(account(UnattendedTokenStore.gitHub) == "github-token")
  #expect(account(.gitLab(for: first)) == GitLabAPIClient.keychainAccount(for: first))
  #expect(account(.gitLab(for: second)) == GitLabAPIClient.keychainAccount(for: second))
  #expect(
    UnattendedTokenStore.gitLab(for: first) !== UnattendedTokenStore.gitLab(for: second))
  // One gate per Keychain item, however often it is asked for: a second gate
  // on the same item would raise a second dialog.
  #expect(
    UnattendedTokenStore.gitLab(for: first) === UnattendedTokenStore.gitLab(for: first))
}

// MARK: - After somebody said no

@Test(arguments: [errSecAuthFailed, errSecUserCanceled])
func aKeychainThatWasToldNoIsNotAskedAgainEveryRefresh(status: OSStatus) {
  // Deny on the access dialog, Cancel on the unlock one. Asking again raises
  // the same dialog, every fifteen seconds, for every runner.
  let refusal = KeychainTokenStore.KeychainFailure(status: status)
  let keychain = HeldTokenStore(.failure(refusal))
  let store = UnattendedTokenStore(keychain)

  for _ in 0..<3 {
    #expect(throws: refusal) { try store.token() }
  }
  #expect(keychain.readCount == 1)
}

@Test func aFailureNobodyAnsweredIsAskedAboutAgain() {
  // No dialog came with it, so asking again bothers nobody, and remembering
  // it would leave the token unread after the Keychain recovered.
  let keychain = HeldTokenStore(.failure(turnedAway))
  let store = UnattendedTokenStore(keychain)

  _ = try? store.token()
  _ = try? store.token()

  #expect(keychain.readCount == 2)
}

@Test func settingsWritingTheTokenLetsTheRefreshAskAgain() {
  // Settings is where somebody is there to answer; a token saved or removed
  // there is that answer.
  let keychain = HeldTokenStore(
    .failure(KeychainTokenStore.KeychainFailure(status: errSecAuthFailed)))
  let store = UnattendedTokenStore(keychain)
  _ = try? store.token()

  store.forgetRefusal()
  _ = try? store.token()

  #expect(keychain.readCount == 2)
}

@Test func aDenyOnADialogFromBeforeASaveDoesNotOutliveTheSave() {
  // A dialog raised at launch can still be on screen when somebody saves or
  // removes the token in Settings. Deny on it afterwards answers for the
  // Keychain as it was before the write, and remembered, it would turn every
  // refresh away from the token Settings has just said is stored.
  let denied = KeychainTokenStore.KeychainFailure(status: errSecAuthFailed)
  let keychain = HeldTokenStore(.failure(denied), held: true)
  let store = UnattendedTokenStore(keychain, patience: .milliseconds(50))
  let launch = Outcome()
  Thread.detachNewThread { launch.record { try store.tokenOnceAnswered() } }
  #expect(eventually { keychain.readCount == 1 })

  store.forgetRefusal()
  keychain.release()

  // Whoever was waiting on that dialog still hears how it was answered.
  #expect(eventually { launch.failure == denied })
  _ = try? store.token()
  #expect(keychain.readCount == 2)
}

@Test func aReadAfterASaveDoesNotWaitOnTheDialogFromBeforeIt() {
  // Joined to the read from before the write, the first read after it would
  // answer for a Keychain item the write has since replaced or removed. That
  // leaves two dialogs on screen, and the old one answered first must not
  // leave the next refresh starting a third.
  let keychain = OneDialogPerRead()
  defer { for read in 0..<keychain.readCount { keychain.answer(read) } }
  let store = UnattendedTokenStore(keychain, patience: .milliseconds(50))
  let launch = Outcome()
  Thread.detachNewThread { launch.record { try store.tokenOnceAnswered() } }
  #expect(eventually { keychain.readCount == 1 })
  store.forgetRefusal()
  _ = try? store.token()
  #expect(keychain.readCount == 2)

  keychain.answer(0)
  #expect(eventually { launch.token == "ghp_x" })
  _ = try? store.token()

  #expect(keychain.readCount == 2)
}
