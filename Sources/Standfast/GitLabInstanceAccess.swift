import Foundation
import RunnerKit

/// The token for one GitLab instance. A personal access token is issued by one
/// instance, so each instance `config.toml` names gets its own Keychain account
/// and its own Settings card, and none is offered another's token.
struct GitLabInstanceAccess: Identifiable {
  let instance: GitLabInstance
  let access: GitHubAccess

  var id: String { instance.name }

  /// Read at launch, like the rest of Settings' view of gitlab-runner. A
  /// missing or unreadable file is a Mac with nothing to hold a token for.
  ///
  /// With no `store`, each card writes through the client's own Keychain item
  /// and reads through the same unattended gate the refresh loop uses, so a
  /// launch read and the first scan raise one dialog between them. Tests pass
  /// memory instead, and then nothing reaches the Keychain at all.
  @MainActor
  static func forInstances(
    in configFile: URL,
    store: ((GitLabInstance) -> any GitHubTokenStoring)? = nil
  ) -> [Self] {
    instances(in: configFile).map { card(for: $0, store: store) }
  }

  /// One card, and with it one Keychain read: building the access object is
  /// what starts the read.
  @MainActor
  static func card(
    for instance: GitLabInstance, store: ((GitLabInstance) -> any GitHubTokenStoring)?
  ) -> Self {
    let access =
      store.map { GitHubAccess(store: $0(instance)) }
      ?? GitHubAccess(
        store: GitLabAPIClient.tokenStore(for: instance),
        unattended: .gitLab(for: instance))
    return Self(instance: instance, access: access)
  }

  static func instances(in configFile: URL) -> [GitLabInstance] {
    let text = (try? String(contentsOf: configFile, encoding: .utf8)) ?? ""
    return GitLabRunnerConfigFile.instances(in: text)
  }
}

/// The GitLab cards Settings shows, re-read whenever Settings could be looked
/// at. Standfast opens at login and runs for weeks: a gitlab-runner registered
/// meanwhile appears at the next scan telling the user to add a token in
/// Settings, and Settings has to have the card to add it to.
@MainActor
final class GitLabInstanceCards: ObservableObject {
  /// The instances that have had a card, by name and never with a token.
  /// Nothing else lists the Keychain items this app wrote: without it, an
  /// instance `config.toml` stops naming loses its card at the next launch,
  /// and the token stored for it its only Remove button.
  static let defaultsKey = "gitLab.knownInstances"

  @Published private(set) var cards: [GitLabInstanceAccess]
  private let configFile: URL?
  private let store: ((GitLabInstance) -> any GitHubTokenStoring)?
  private let defaults: UserDefaults?

  init(
    configFile: URL, store: ((GitLabInstance) -> any GitHubTokenStoring)? = nil,
    defaults: UserDefaults = .standard
  ) {
    self.configFile = configFile
    self.store = store
    self.defaults = defaults
    cards = GitLabInstanceAccess.forInstances(in: configFile, store: store)
    // And the instances an earlier launch showed, which the file may no
    // longer name.
    reload()
  }

  /// Fixed cards and no file, for a test or a render.
  init(cards: [GitLabInstanceAccess]) {
    configFile = nil
    store = nil
    defaults = nil
    self.cards = cards
  }

  /// Adds a card for every instance `config.toml` now names, and for every
  /// one an earlier launch showed. Never removes one: an instance dropped from
  /// the file can still have a token stored, and its card is the only place to
  /// remove it. Only a new instance gets an access object: this runs every
  /// time the app comes to the front, and each one built is a Keychain read.
  func reload() {
    guard let configFile else { return }
    let named = GitLabInstanceAccess.instances(in: configFile)
    var shown = Set(cards.map(\.id))
    let added = (named + remembered)
      .filter { shown.insert($0.name).inserted }
      .map { GitLabInstanceAccess.card(for: $0, store: store) }
    if !added.isEmpty { cards += added }
    remember(besides: Set(named.map(\.name)))
  }

  private var remembered: [GitLabInstance] {
    (defaults?.array(forKey: Self.defaultsKey) ?? [])
      .compactMap { $0 as? String }
      // A name carries its scheme only when it is not https.
      .compactMap { GitLabInstance(url: $0.hasPrefix("http://") ? $0 : "https://" + $0) }
  }

  /// Forgets an instance only once the file no longer names it and its card
  /// has read that nothing is stored: a Remove that landed, or nothing ever
  /// saved. Until that read settles the card cannot tell, and a refusal is not
  /// an empty Keychain.
  private func remember(besides named: Set<String>) {
    let kept = cards.filter { named.contains($0.id) || $0.access.state != .absent }
    defaults?.set(kept.map(\.id), forKey: Self.defaultsKey)
  }
}
