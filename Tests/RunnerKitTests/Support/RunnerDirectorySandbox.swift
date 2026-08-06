import Foundation

@testable import RunnerKit

/// A throwaway runner directory: a `_work` with the folders a real one grows in
/// it, and a `_diag` whose logs a test can age by hand.
///
/// Everything destructive in this package is pointed at one of these and never
/// at a path a person owns. The suite runs on machines with a real runner on
/// them, and the difference between the two is one wrong string.
final class RunnerDirectorySandbox {
  let root: URL

  init() throws {
    let created = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("housekeeping-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
    // Through `realpath`, because the temporary directory lives under `/var`,
    // which on macOS is a symlink to `/private/var` — and `contentsOfDirectory`
    // hands back the resolved spelling while `appendingPathComponent` keeps the
    // short one. Foundation's own `resolvingSymlinksInPath` will not help: it
    // strips the `/private` prefix straight back off again. A sandbox that kept
    // both spellings would make every path comparison in these tests a
    // comparison of two names for one directory, which no real runner directory
    // has — nothing symlinks a home directory.
    root = Self.canonical(created)
  }

  private static func canonical(_ url: URL) -> URL {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &buffer) != nil else { return url }
    guard
      let path = buffer.withUnsafeBufferPointer({ pointer -> String? in
        guard let baseAddress = pointer.baseAddress else { return nil }
        return String(validatingCString: baseAddress)
      })
    else { return url }
    return URL(fileURLWithPath: path)
  }

  func cleanUp() { try? FileManager.default.removeItem(at: root) }

  var runner: DiscoveredRunner {
    DiscoveredRunner(
      label: "actions.runner.acme-widget.build-mac", directory: root, agentId: 7,
      agentName: "build-mac", scope: .repository(owner: "acme", name: "widget"))
  }

  var work: URL { root.appendingPathComponent("_work") }
  var diagnostics: URL { root.appendingPathComponent("_diag") }

  /// One directory under `_work`, with a file of roughly the given size in it.
  ///
  /// - Parameter kilobytes: written for real, because the whole point of the
  ///   measurement under test is that it asks the filesystem rather than being
  ///   told. `du` counts allocated blocks, so anything here rounds up.
  @discardableResult
  func makeWorkFolder(_ name: String, kilobytes: Int = 0) throws -> URL {
    let directory = work.appendingPathComponent(name)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    if kilobytes > 0 {
      try Data(repeating: UInt8(ascii: "x"), count: kilobytes * 1024)
        .write(to: directory.appendingPathComponent("payload"))
    }
    return directory
  }

  /// A log in `_diag`, with a modification date of this test's choosing.
  ///
  /// The date is what ages it, and setting it is the only way to write a test
  /// about a week-old file that does not take a week.
  /// - Parameter lines: what the log says, for the tests that read it back.
  ///   Written before the date is set, because writing to a file is what a
  ///   modification date records.
  @discardableResult
  func makeLog(
    _ name: String, bytes: Int = 16, lines: [String] = [], modified: Date
  ) throws -> URL {
    try FileManager.default.createDirectory(
      at: diagnostics, withIntermediateDirectories: true)
    let url = diagnostics.appendingPathComponent(name)
    let data =
      lines.isEmpty
      ? Data(repeating: UInt8(ascii: "x"), count: bytes)
      : Data(lines.map { $0 + "\n" }.joined().utf8)
    try data.write(to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: modified], ofItemAtPath: url.path)
    return url
  }

  func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  func names(in directory: URL) -> Set<String> {
    let entries =
      (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return Set(entries)
  }
}

/// Records what was asked of the filesystem without touching it.
///
/// The one assertion a real `FileManager` cannot support: that a refusal called
/// *nothing*. "The directory is still there" is satisfied by a delete that
/// failed as well as by one that never ran, and only one of those is this code
/// working.
final class RecordingFileOperations: DestructiveFileOperations, @unchecked Sendable {
  /// Also written to by tests that need to place another event in the same
  /// sequence — see `theCheckIsTheLastThingBeforeTheRename`.
  private let lock = NSLock()
  private var entries: [String] = []

  struct Refusal: Error {}
  /// Set to have every mutation throw, which is what a directory the app cannot
  /// write to looks like from here.
  var failing = false

  var calls: [String] {
    lock.lock()
    defer { lock.unlock() }
    return entries
  }

  func note(_ entry: String) {
    lock.lock()
    entries.append(entry)
    lock.unlock()
  }

  func createDirectory(at url: URL) throws {
    note("create \(url.lastPathComponent)")
    if failing { throw Refusal() }
  }

  func move(_ url: URL, to destination: URL) throws {
    note("move \(url.lastPathComponent)")
    if failing { throw Refusal() }
  }

  func remove(_ url: URL) throws {
    note("remove \(url.lastPathComponent)")
    if failing { throw Refusal() }
  }
}
