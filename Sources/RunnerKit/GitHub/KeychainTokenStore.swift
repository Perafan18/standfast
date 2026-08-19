import Foundation
import Security

/// The GitHub token, in the login keychain.
///
/// The keychain rather than `UserDefaults` or a file in Application Support:
/// a GitHub token can start workflow runs and read private repositories, and
/// the other two put it in plain text where Time Machine, a backup, and any
/// process running as this user can read it.
public struct KeychainTokenStore: GitHubTokenStoring {
  /// The app's bundle identifier, so the item shows up in Keychain Access
  /// under a name whoever finds it can act on.
  public static let defaultService = "dev.standfast.app"
  /// One token, one account. There is no second GitHub this app talks to yet;
  /// when there is, the host belongs here.
  public static let account = "github-token"

  private let service: String

  public init(service: String = KeychainTokenStore.defaultService) {
    self.service = service
  }

  public struct KeychainFailure: Error, Equatable {
    public let status: OSStatus
    /// What the Keychain called it, when it has a name. Worth carrying: the
    /// numbers are meaningless on their own and this is the only place the
    /// reason survives.
    public var explanation: String? {
      SecCopyErrorMessageString(status, nil) as String?
    }
  }

  private var query: [String: Any] {
    [
      // The file-based keychain, not the data-protection one: this app is not
      // sandboxed and has no keychain-sharing entitlement, and the data
      // protection keychain requires one.
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: Self.account,
    ]
  }

  public func token() throws -> String? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne

    var found: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &found)
    // Nothing stored is an answer, not a failure. It is the state every
    // machine starts in, and the one the `gh` fallback exists for.
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    guard let data = found as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func store(_ token: String) throws {
    let secret = Data(token.utf8)
    // Update first, because `SecItemAdd` refuses an item that already exists —
    // and pasting a second token is exactly what someone does when the first
    // one expired.
    let updated = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else {
      throw KeychainFailure(status: updated)
    }

    var addition = query
    addition[kSecValueData as String] = secret
    // Readable whenever this Mac is unlocked, and never off it. The app reads
    // this on every refresh, so anything stricter would mean a prompt every
    // fifteen seconds; anything looser would put a live GitHub credential on
    // another machine.
    addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    let added = SecItemAdd(addition as CFDictionary, nil)
    guard added == errSecSuccess else { throw KeychainFailure(status: added) }
  }

  public func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    // Deleting what was never there is the outcome the caller wanted. Anything
    // else would make the Settings button report an error to whoever pressed
    // it twice.
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainFailure(status: status)
    }
  }
}
