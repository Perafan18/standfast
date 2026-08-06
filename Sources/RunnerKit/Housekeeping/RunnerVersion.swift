import Foundation

/// A runner version, as three numbers rather than as the text they were written
/// in.
///
/// Compared numerically, which is the entire reason this is not a `String`:
/// `2.336.0` and `2.99.0` sort the wrong way round as text, and the runner is
/// well past the minor version where that stops being hypothetical.
public struct RunnerVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(_ major: Int, _ minor: Int, _ patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  /// Nil for anything that is not three numbers.
  ///
  /// - Parameter text: `2.336.0` as the runner prints it, or `v2.336.0` as
  ///   GitHub tags it. Both spellings arrive here, from the two halves of the
  ///   same question.
  public init?(_ text: String) {
    var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("v") { text.removeFirst() }
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, let major = Int(parts[0]), let minor = Int(parts[1]),
      let patch = Int(parts[2])
    else { return nil }
    self.init(major, minor, patch)
  }

  public static func < (lhs: RunnerVersion, rhs: RunnerVersion) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }

  public var description: String { "\(major).\(minor).\(patch)" }
}

/// Reads which runner is installed, out of the listener's own log.
///
/// The version is not recorded anywhere a runner is documented to publish it.
/// `.runner` does not carry it, and the only two places on disk that do are
/// `bin/Runner.Listener.deps.json` — a hundred kilobytes of .NET dependency
/// graph — and the header the listener writes at the top of every log it opens.
/// The log wins on both counts: it is four kilobytes into a file this app
/// already knows how to find, and it says which runner *ran*, where the
/// dependency file only says which one is unpacked.
///
/// A protocol as well as a type, because *where* this runs is as much a part of
/// its contract as what it reads — it opens a file off a home directory that may
/// be on a network volume — and only a seam a test can wrap makes that
/// checkable.
public protocol RunnerVersionReading: Sendable {
  /// Blocks the calling thread on one short read. Safe only from a thread that
  /// is yours to block; see `offCooperativePool`.
  ///
  /// - Parameter log: a listener log, which the caller already has: see
  ///   `JobLogReader.activeLog`.
  func blockingVersion(inLog log: URL) -> RunnerVersion?
}

public struct RunnerVersionReader: RunnerVersionReading {
  /// How much of a log is read looking for it. The listener writes the version
  /// in its first half-dozen lines, before it has done anything at all; this is
  /// a ceiling on a mistake, not a target.
  static let headWindow = 8 * 1024

  /// `[2026-08-06 05:17:18Z INFO Listener] Version: 2.336.0`.
  ///
  /// The bracket is part of the marker, and it is what keeps this off the rest
  /// of the file. The listener echoes every job's name into the same log, and a
  /// release workflow with a job called `Release Version: 9.9.9` writes a line
  /// that a match on `Version: ` alone finds first — reporting the workflow's
  /// number as the runner's, wrongly, and in a way nobody would question. Three
  /// lines under the real one the same file also says `Flag 'version':
  /// 'False'`.
  static let marker = "] Version: "

  public init() {}

  /// Blocks the calling thread on one short read. Safe only from a thread that
  /// is yours to block; see `offCooperativePool`.
  ///
  /// - Parameter log: which listener log to read it out of. Passed in rather
  ///   than looked up, because the caller has just listed `_diag` to find this
  ///   very file and listing it again is the work `JobLogReader`'s cache exists
  ///   to avoid.
  /// - Returns: nil for a log that says nothing this recognises. Not an error
  ///   worth a row in a menu — the version is a nice-to-know beside a runner
  ///   that is working.
  public func blockingVersion(inLog log: URL) -> RunnerVersion? {
    guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: Self.headWindow) else { return nil }
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      guard let marker = line.range(of: Self.marker) else { continue }
      if let version = RunnerVersion(String(line[marker.upperBound...])) { return version }
    }
    return nil
  }
}

/// Asks what the newest published runner is.
///
/// Its own protocol rather than another requirement on `GitHubClient`. The two
/// questions have nothing in common but the transport: one is about a runner on
/// this Mac and is asked every fifteen seconds, the other is about a release on
/// the internet, changes every few weeks, and must not be asked at anything
/// like that rate.
public protocol RunnerReleaseChecking: Sendable {
  /// Blocks the calling thread while it asks GitHub, exactly as
  /// `GitHubClient.blockingRunnerStatus` does, and with the same rule about
  /// which threads may call it.
  func blockingLatestRunnerRelease() throws -> RunnerVersion
}
