import Foundation

/// The runner directories the operator pointed this app at.
///
/// A runner started with `./run.sh` leaves no LaunchAgent, so discovery has
/// nothing to find it by — the app would claim to discover your runners and
/// quietly show half of them. This is the other half, and it is a list somebody
/// typed rather than a guess: walking the disk looking for `.runner` files
/// would read directories nobody asked this app to read, and would turn up
/// other people's runners in shared folders.
@MainActor
final class ManualRunnerDirectories: ObservableObject {
  nonisolated static let defaultsKey = "manualRunnerDirectories"

  @Published private(set) var directories: [URL]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    directories = Self.stored(in: defaults)
  }

  /// The same list, without the main actor.
  ///
  /// The scan reads this rather than the observable object above, for two
  /// reasons: it runs off the main actor on a thread it is allowed to block,
  /// and it must see what is stored *now* — a folder added while a scan was in
  /// flight should be found by the next one, not by the next launch.
  ///
  /// Anything that is not a string is somebody's `defaults write` gone wrong,
  /// and it must not take the fleet down with it.
  nonisolated static func stored(in defaults: UserDefaults = .standard) -> [URL] {
    (defaults.array(forKey: Self.defaultsKey) ?? [])
      .compactMap { $0 as? String }
      .map { URL(fileURLWithPath: $0).standardizedFileURL }
  }

  func add(_ directory: URL) {
    let directory = directory.standardizedFileURL
    // Adding it again is what somebody does when they are not sure it took.
    guard !directories.contains(where: { $0.path == directory.path }) else { return }
    directories.append(directory)
    save()
  }

  func remove(_ directory: URL) {
    let directory = directory.standardizedFileURL
    directories.removeAll { $0.path == directory.path }
    save()
  }

  private func save() {
    // Order is kept as added, not sorted: the operator put them in an order
    // that meant something to them.
    defaults.set(directories.map(\.path), forKey: Self.defaultsKey)
  }
}
