import Foundation

@testable import Standfast

/// Records what would have been selected in Finder. The real one brings Finder
/// forward on whoever's machine runs the suite.
final class FakeFileRevealer: FileRevealing, @unchecked Sendable {
  private let lock = NSLock()
  private var revealed: [URL] = []

  var urls: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return revealed
  }

  func reveal(_ url: URL) {
    lock.lock()
    defer { lock.unlock() }
    revealed.append(url)
  }
}
