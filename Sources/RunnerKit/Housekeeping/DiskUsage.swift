import Foundation

/// One directory under `_work`, and what it costs.
public struct DiskEntry: Equatable, Sendable {
  public let name: String
  public let kind: DiskEntryKind
  public let bytes: Int64

  public init(name: String, kind: DiskEntryKind, bytes: Int64) {
    self.name = name
    self.kind = kind
    self.bytes = bytes
  }
}

/// What one runner is costing this Mac, broken down far enough to act on.
///
/// The breakdown is the point, not the total. Four and a half gigabytes is a
/// number to be alarmed by; four gigabytes of *tool cache* is a number to press
/// a button about, because a cache is the one thing on a disk that can be
/// deleted without losing anything.
public struct DiskReport: Equatable, Sendable {
  /// Biggest first, which is the order anybody reads this in.
  public let entries: [DiskEntry]
  /// The whole of `_diag`.
  public let logBytes: Int64
  public let rotation: DiagnosticsRotationPlan

  public init(entries: [DiskEntry], logBytes: Int64, rotation: DiagnosticsRotationPlan) {
    self.entries = entries
    self.logBytes = logBytes
    self.rotation = rotation
  }

  public static let empty = DiskReport(entries: [], logBytes: 0, rotation: .empty)

  /// Everything of one kind added up. `_work` holds one checkout per repository
  /// this runner builds, and the menu has no room for a row each.
  public func bytes(of kind: DiskEntryKind) -> Int64 {
    entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes }
  }
}

/// Measures a runner's footprint with `du`, one child process at a time.
///
/// `du` rather than `FileManager.enumerator`. Not a preference: `_work` was
/// 4.5 GB across a couple of hundred thousand files on the Mac this was built
/// against, and walking that from Foundation is one `stat` per file through
/// several layers of bridging. `du -sk` is what the system optimises for
/// exactly this question and it answered in 0.16 s warm, with the whole of
/// `blockingReport` — the listings, the child process and the rotation plan —
/// taking 0.24 s. It also goes through `CommandRunning` like every other
/// external command here, which is what makes this testable on a machine with
/// no runner on it.
///
/// Nothing calls this on a timer. Even warm it is a full metadata walk of every
/// file the runner owns, and the cold number on a Mac that has just woken — or
/// a home directory on a network volume — is seconds, not milliseconds. The
/// refresh loop runs every fifteen seconds all day; this runs when somebody
/// asks.
public struct DiskUsage: Sendable {
  /// The absolute path, not `/usr/bin/env du`. `du` is in the base system, so
  /// there is no PATH to search and nothing a user could have installed
  /// somewhere else — unlike `gh`, which is why that one gets a search and this
  /// one does not.
  public static let du = "/usr/bin/du"

  /// `-s` for one line per argument, `-k` for 1024-byte blocks whatever
  /// `BLOCKSIZE` is set to in the environment this app inherited.
  static let arguments = ["-sk"]

  private let commandRunner: any CommandRunning

  public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
    self.commandRunner = commandRunner
  }

  /// Blocks the calling thread on `du` and a couple of directory listings, for
  /// up to the command runner's timeout. Same rule as everything else here:
  /// safe only from a thread that is yours to block, which rules out the main
  /// actor and the cooperative pool. See `offCooperativePool`.
  ///
  /// - Returns: nil when nothing could be measured at all, which the menu has
  ///   to be able to say rather than draw as an empty disk.
  public func blockingReport(
    for runner: DiscoveredRunner, retention: DiagnosticsRetention, now: Date
  ) -> DiskReport? {
    guard let workDirectory = runner.containedWorkDirectory,
      let diagnostics = runner.containedDiagnosticsDirectory
    else { return nil }
    let children = Self.children(of: workDirectory)
    let logs = DiagnosticsFile.listing(in: diagnostics)
    var paths = children
    if FileManager.default.fileExists(atPath: diagnostics.path) {
      paths.append(diagnostics)
    }
    // A runner that has never taken a job has neither directory, and that is an
    // answer rather than a failure. It is also the guard that keeps `du` from
    // being run with no arguments at all, which is not a no-op: bare `du`
    // measures the working directory it was launched in.
    guard !paths.isEmpty else { return .empty }

    guard let sizes = blockingSizes(of: paths) else { return nil }
    let entries =
      children
      .map {
        DiskEntry(
          name: $0.lastPathComponent,
          kind: DiskEntryKind(folderName: $0.lastPathComponent),
          bytes: sizes[$0] ?? 0)
      }
      .sorted(by: Self.biggestFirst)

    return DiskReport(
      entries: entries,
      logBytes: sizes[diagnostics] ?? 0,
      rotation: DiagnosticsRotation.plan(logs, retention: retention, now: now))
  }

  /// Biggest first, and by name where two are the same size — so a menu redrawn
  /// a second later does not reshuffle two empty directories.
  ///
  /// A named function rather than a closure in the chain above, where the type
  /// checker gives up on it.
  static func biggestFirst(_ lhs: DiskEntry, _ rhs: DiskEntry) -> Bool {
    if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
    return lhs.name < rhs.name
  }

  /// One `du` for every path, rather than one each.
  ///
  /// Both because N spawns for N directories is N times the cost, and because a
  /// single run is the only way the hard links between two of them are counted
  /// once — `du` remembers the inodes it has already seen, but only within one
  /// invocation.
  private func blockingSizes(of paths: [URL]) -> [URL: Int64]? {
    guard
      let result = try? commandRunner.run(
        Self.du, Self.arguments + paths.map(\.path))
    else { return nil }
    let sizes = Self.sizes(in: result.standardOutput, from: paths)
    // The exit code is not the test. `du` exits non-zero when a single argument
    // was unreadable and still reports every other one, and a directory
    // disappearing under a measurement is ordinary on a machine with a runner
    // on it. Having no line at all for anything is what means it did not run.
    return sizes.isEmpty ? nil : sizes
  }

  /// `4229008\t<runner directory>/_work/_tool`, one line per argument.
  ///
  /// Matched against the paths that were asked for rather than parsed as a
  /// path, because a path is the one field that can contain anything at all.
  /// `du` echoes each argument back verbatim, so this needs no guess about
  /// where the field ends.
  static func sizes(in output: String, from paths: [URL]) -> [URL: Int64] {
    var wanted: [String: URL] = [:]
    for path in paths { wanted[path.path] = path }
    var found: [URL: Int64] = [:]
    for line in output.split(separator: "\n") {
      guard let tab = line.firstIndex(of: "\t"),
        let kilobytes = Int64(line[line.startIndex..<tab]),
        let url = wanted[String(line[line.index(after: tab)...])]
      else { continue }
      found[url] = kilobytes * 1024
    }
    return found
  }

  /// What is directly inside `_work`, sorted so the answer does not depend on
  /// the order the filesystem happened to hand back.
  static func children(of directory: URL) -> [URL] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}
