import Foundation

/// One file in a runner's `_diag`, as the sweeper sees it.
public struct DiagnosticsFile: Equatable, Sendable {
  public let url: URL
  /// When it was last written to. See `DiagnosticsRotation.plan` for why the
  /// instant in the name is not what decides an age here.
  public let modifiedAt: Date
  public let bytes: Int64

  public init(url: URL, modifiedAt: Date, bytes: Int64) {
    self.url = url
    self.modifiedAt = modifiedAt
    self.bytes = bytes
  }

  var name: String { url.lastPathComponent }
  /// The logs `JobLogReader` builds the menu's job history out of. The
  /// `Worker_…` files beside them are ten times the size and are read by
  /// nothing in this app.
  var isListenerLog: Bool { name.hasPrefix(JobLogReader.logPrefix) }

  /// Every `.log` directly inside `_diag`, in no particular order.
  ///
  /// Files only. `_diag` also holds `blocks/` and `pages/`, which are the
  /// runner's own store rather than logs, and a sweep that recursed into them
  /// would be deleting something it has no rule for.
  public static func listing(in directory: URL) -> [DiagnosticsFile] {
    let keys: [URLResourceKey] = [
      .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
    ]
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: keys)) ?? []
    return entries.compactMap { url in
      guard url.pathExtension == "log",
        let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true,
        let modified = values.contentModificationDate
      else { return nil }
      return DiagnosticsFile(
        url: url, modifiedAt: modified, bytes: Int64(values.fileSize ?? 0))
    }
  }
}

/// How much of `_diag` survives a sweep.
public struct DiagnosticsRetention: Equatable, Sendable {
  /// Logs younger than this are never touched.
  public let keepFor: TimeInterval
  /// How many listener logs are kept whatever their age.
  public let listenerLogsKept: Int

  public init(keepFor: TimeInterval, listenerLogsKept: Int) {
    self.keepFor = keepFor
    self.listenerLogsKept = listenerLogsKept
  }

  /// A week, and as many listener logs as the job history can reach back over.
  ///
  /// A week because `_diag` grows by about ten megabytes a day and nobody has
  /// ever opened a worker log from last Tuesday; the sweep has to be worth
  /// running, and keeping a month would leave three hundred megabytes of text
  /// behind. The listener count is not a second opinion about age — it is the
  /// floor `JobLogReader` needs, and it comes from that type rather than from a
  /// number chosen here.
  public static let standard = DiagnosticsRetention(
    keepFor: 7 * 24 * 60 * 60, listenerLogsKept: JobLogReader.retainedListenerLogs)
}

/// Which files a sweep would take, and what that would free.
public struct DiagnosticsRotationPlan: Equatable, Sendable {
  /// Oldest first, so a sweep interrupted halfway has still done the useful
  /// half.
  public let doomed: [URL]
  public let bytes: Int64

  public init(doomed: [URL], bytes: Int64) {
    self.doomed = doomed
    self.bytes = bytes
  }

  public static let empty = DiagnosticsRotationPlan(doomed: [], bytes: 0)
  public var isEmpty: Bool { doomed.isEmpty }
  public var count: Int { doomed.count }
}

/// Decides what leaves `_diag`, separately from anything that deletes it.
///
/// A pure function over a listing, because this is the half that can be wrong
/// in a way nobody notices for weeks — the menu's job history going short after
/// a sweep is not a crash, it is five rows quietly becoming two — and a plan is
/// something a test can read without a single file being removed.
public enum DiagnosticsRotation {
  /// - Parameters:
  ///   - now: the moment the sweep is being asked about, so a test can put a
  ///     file a fortnight in the past without waiting a fortnight.
  ///   - allowed: the files a plan may name, or nil for no such limit. How a
  ///     caller holds a sweep to what somebody agreed to while still deciding
  ///     what leaves against the directory as it is now — the sizes come from
  ///     this listing rather than from the older one, so the answer is exact
  ///     rather than merely smaller.
  public static func plan(
    _ files: [DiagnosticsFile], retention: DiagnosticsRetention, now: Date,
    limitedTo allowed: Set<URL>? = nil
  ) -> DiagnosticsRotationPlan {
    // Sorted by name, exactly as `JobLogReader.listenerLogs` sorts them. The
    // name carries the UTC instant the listener started, fixed width so it
    // sorts as text — and the file this app must never delete is the one that
    // reader calls `logs.last`. Ordering these any other way is how the two
    // disagree about which file that is.
    let listener = files.filter(\.isListenerLog).sorted { $0.name < $1.name }
    // Never fewer than one, whatever a caller asks for. The last listener log
    // is the one being appended to right now: deleting it costs the menu its
    // whole history, and costs the runner the file its process has open.
    let kept = Set(listener.suffix(max(1, retention.listenerLogsKept)).map(\.url))

    let doomed =
      files
      .filter { !kept.contains($0.url) }
      .filter { allowed?.contains($0.url) ?? true }
      // Aged by the modification date rather than by the instant in the name.
      // A listener that has been up for a fortnight has an old name and a log
      // it wrote to a second ago, and the two answers are two weeks apart. The
      // failure this direction is also the safe one: a `_diag` restored from a
      // backup arrives with every mtime set to the restore, so nothing is old
      // enough to sweep and nothing is deleted.
      .filter { now.timeIntervalSince($0.modifiedAt) > retention.keepFor }
      .sorted(by: Self.oldestFirst)

    return DiagnosticsRotationPlan(
      doomed: doomed.map(\.url), bytes: doomed.reduce(0) { $0 + $1.bytes })
  }

  /// Oldest first, and by name where two were written at the same instant — the
  /// same tie-break `DiskUsage.biggestFirst` carries, for the same reason.
  ///
  /// `sorted(by:)` is not stable, so without this a `_diag` whose files share a
  /// modification date comes back in an order that is neither chronological nor
  /// repeatable. That is not a hypothetical directory: it is what a `_diag`
  /// copied or restored from a backup looks like, which this file already warns
  /// about two comments below — and `DiagnosticsRotationPlan` is `Equatable`
  /// and travels into `@Published` state, where a reshuffle reads as a change.
  static func oldestFirst(_ lhs: DiagnosticsFile, _ rhs: DiagnosticsFile) -> Bool {
    if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
    return lhs.name < rhs.name
  }
}
