import Foundation

@testable import Standfast

/// Records what would have been handed to the browser.
///
/// The suite ran for a while with the real opener wired in, and every run threw
/// a browser tab at a fixture repository on whoever's machine was running it.
/// Nothing failed, which is why it survived: the test asserted that no command
/// had been spawned, and opening a URL spawns none.
final class FakeURLOpener: URLOpening, @unchecked Sendable {
  private let lock = NSLock()
  private var opened: [URL] = []

  var urls: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return opened
  }

  func open(_ url: URL) {
    lock.lock()
    defer { lock.unlock() }
    opened.append(url)
  }
}
