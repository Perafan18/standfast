import Foundation
import Security

/// The token as the refresh loop reads it: one shared Keychain read at a time,
/// waited on briefly, and not repeated once refused. A locked keychain, or one
/// whose access list no longer names this binary, asks somebody first.
public final class UnattendedTokenStore: GitHubTokenStoring, @unchecked Sendable {
  /// Shared, because a read in flight and a refusal both belong to the Keychain
  /// item, not to whichever client happened to ask.
  public static let gitHub = UnattendedTokenStore(KeychainTokenStore())
  /// One per GitLab instance, for the same reason: each instance's token is
  /// its own Keychain item, with its own access list and its own refusal.
  public static func gitLab(for instance: GitLabInstance) -> UnattendedTokenStore {
    gitLabStores.withLock { stores in
      let account = GitLabAPIClient.keychainAccount(for: instance)
      if let store = stores[account] { return store }
      let store = UnattendedTokenStore(GitLabAPIClient.tokenStore(for: instance))
      stores[account] = store
      return store
    }
  }

  private static let gitLabStores = Guarded<[String: UnattendedTokenStore]>([:])

  /// The Keychain's own word for a request that needed somebody to answer it,
  /// so a caller cannot tell this gate's refusal from the Keychain's.
  static let turnedAway = KeychainTokenStore.KeychainFailure(
    status: errSecInteractionNotAllowed)
  /// What the Keychain answers once somebody chose: Deny on the access dialog,
  /// Cancel on the unlock one. Asking again only raises the same dialog.
  static let refusals: Set<OSStatus> = [errSecAuthFailed, errSecUserCanceled]

  private let underlying: any GitHubTokenStoring
  private let patience: DispatchTimeInterval
  private let lock = NSLock()
  /// Whoever asks while the Keychain is working waits on this read rather
  /// than starting another. On an unlocked Keychain that costs milliseconds; on
  /// a locked one, a second read would be a second dialog.
  private var inFlight: PendingRead?
  private var refusal: KeychainTokenStore.KeychainFailure?
  /// Moved on by every Save or Remove. A read that began before one answers
  /// for the Keychain as it was then, and a Deny on its dialog, clicked after
  /// the button, would otherwise outlive the button meant to lift it.
  private var generation = 0

  /// Long enough for an unlocked Keychain on a busy Mac, short enough that a
  /// refresh with a dialog on screen still reaches every other runner.
  public init(
    _ underlying: any GitHubTokenStoring, patience: DispatchTimeInterval = .seconds(2)
  ) {
    self.underlying = underlying
    self.patience = patience
  }

  public func token() throws -> String? {
    let read = try sharedRead()
    return try read.token(by: read.deadline)
  }

  /// The shared read, waited on for as long as the Keychain takes. Settings
  /// reads this way so that its launch read and the first refresh raise one
  /// dialog between them, not one each.
  public func tokenOnceAnswered() throws -> String? {
    try sharedRead().token(by: .distantFuture)
  }

  private func sharedRead() throws -> PendingRead {
    let (read, isNew, startedIn) = try lock.withLock {
      () throws -> (PendingRead, Bool, Int) in
      if let refusal { throw refusal }
      if let inFlight { return (inFlight, false, generation) }
      // From when the read began, not from when each caller joined it: the
      // scan asks runner by runner, and each waiting out the same dialog in
      // turn would hold a refresh for the wait times the number of runners.
      let read = PendingRead(deadline: .now() + patience)
      inFlight = read
      return (read, true, generation)
    }
    guard isNew else { return read }

    Thread.detachNewThread { [self] in
      let outcome = Result { try underlying.token() }
      lock.withLock {
        // A Save or Remove since may have started the read in flight now.
        if inFlight === read { inFlight = nil }
        if startedIn == generation,
          case .failure(let failure as KeychainTokenStore.KeychainFailure) = outcome,
          Self.refusals.contains(failure.status)
        {
          refusal = failure
        }
      }
      read.finish(outcome)
    }
    return read
  }

  /// Straight through: writes come from Settings, where whoever pressed the
  /// button is there to answer a dialog.
  public func store(_ token: String) throws { try underlying.store(token) }
  public func clear() throws { try underlying.clear() }

  /// For Settings when somebody presses Save or Remove: they are there to answer
  /// the Keychain, so the refusal remembered here is no longer the last word.
  /// Nor is a read still in flight: whoever asks next gets a read of the item
  /// as the button leaves it, and whoever already waits gets the answer they
  /// waited for.
  public func forgetRefusal() {
    lock.withLock {
      refusal = nil
      inFlight = nil
      generation += 1
    }
  }

  /// One read's answer, handed from the thread parked in the Keychain to every
  /// caller waiting on it, some of which may have stopped waiting.
  private final class PendingRead: @unchecked Sendable {
    let deadline: DispatchTime
    /// A group rather than a semaphore: a signal wakes one waiter, and every
    /// caller that joined this read is owed its answer.
    private let answered = DispatchGroup()
    private let lock = NSLock()
    private var outcome: Result<String?, any Error>?

    init(deadline: DispatchTime) {
      self.deadline = deadline
      answered.enter()
    }

    func finish(_ outcome: Result<String?, any Error>) {
      lock.withLock { self.outcome = outcome }
      answered.leave()
    }

    func token(by deadline: DispatchTime) throws -> String? {
      guard answered.wait(timeout: deadline) == .success,
        let outcome = lock.withLock({ outcome })
      else { throw UnattendedTokenStore.turnedAway }
      return try outcome.get()
    }
  }
}

/// A value behind a lock, for the static registry above.
final class Guarded<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
}
