import Foundation

/// Reads a runner's job history out of the log its listener already writes.
///
/// No API call, no configuration and no token. The runner prints every job it
/// picks up and every result it hands back, and `_diag/Runner_<start>.log` is
/// that terminal written down — so the answer to "what is it building, and how
/// long does that usually take" is already on disk before this app asks
/// anything.
///
/// A value type carrying its own cache, so a caller can hold one per runner and
/// hand it back and forth across a thread hop the way `SettlingWindow` is held.
/// The cache is not an optimisation on top of a correct implementation: reading
/// `_diag` whole every fifteen seconds is what this type exists to avoid. The
/// directory is megabytes and grows by roughly ten a day, nearly all of it
/// worker logs this never opens.
public struct JobLogReader: Sendable {
  /// How many jobs are kept.
  ///
  /// Neither of the two numbers that seem to decide it. The menu lists five,
  /// and an estimate looks at five runs *of one job name* — so what this has to
  /// cover is how far back you go on a machine that interleaves several
  /// workflows before five runs of the same one have gone by. Twenty is about
  /// two days on a runner that builds all day, and it is bounded rather than
  /// generous on purpose: every record is held for the life of the process.
  public static let maxRecords = 20

  /// How much of each log a cold start reads, from the end.
  ///
  /// A listener writes about 24 KB per job and, measured on a real runner,
  /// *nothing at all* while it is idle — so half a megabyte reaches back about
  /// twenty jobs. It is a ceiling and not a target: a listener that has been up
  /// for a month has a log this must never read whole.
  static let tailWindow = 512 * 1024

  /// How much a cold start may read across all the logs it walks.
  ///
  /// The stopping condition is having enough jobs, not having opened enough
  /// files — measured, after a fixed count of four got this wrong on the very
  /// machine it was calibrated against. That runner had rotated five times in
  /// two days, four of those without running anything, so the sixteen jobs it
  /// had run all sat in the fifth file back and the menu showed one. What a
  /// file count was standing in for is a bound on work, so this is that bound
  /// said directly. It is a ceiling that is almost never reached: the walk
  /// stops at `maxRecords` long before, and on that machine it read 388 KB.
  static let coldReadBudget = 4 * 1024 * 1024

  /// A backstop on the number of logs walked, for a `_diag` nobody has ever
  /// cleared out. The budget above is the real limit.
  static let maxFiles = 24

  /// How many listener logs anything that clears out `_diag` has to leave
  /// behind.
  ///
  /// Named here because this is the type that decides it. After a rotation the
  /// history in the menu is rebuilt by walking back through these files, so a
  /// sweep that left fewer would shorten the history the next time the listener
  /// rotates — silently, and the sweep is the last place anybody would go
  /// looking for the reason.
  ///
  /// `maxFiles` *plus one*, and the one is not a margin. `coldStart` reads the
  /// active log and then walks `maxFiles` further files back, so the reach is
  /// `maxFiles + 1` files and a floor of `maxFiles` is exactly one short: on a
  /// `_diag` with that many rotations in it, the sweep takes the file the walk
  /// would have ended on. That is not a corner case on a laptop, where every
  /// sleep and wake rotates the log without running a single job.
  ///
  /// It costs about a megabyte: a listener log is tens of kilobytes, where the
  /// worker logs a sweep is actually after are half a megabyte each.
  public static var retainedListenerLogs: Int { maxFiles + 1 }

  /// Every listener log is `Runner_<utc>.log`. The worker logs beside them are
  /// `Worker_…`, are ten times the size, and hold nothing this needs.
  static let logPrefix = "Runner_"

  /// What has already been read, and how much of the active log it covers.
  private struct Cache: Equatable, Sendable {
    /// The log the listener is writing to now.
    let activeLog: URL
    /// Bytes of it already parsed. Everything past this is the delta, and the
    /// delta is all a refresh reads.
    var consumed: Int
    /// Records from logs older than the active one, oldest first. Those files
    /// are finished — the listener only ever appends to the newest — so they
    /// are read once and never opened again.
    var older: [JobRecord]
    /// Records from the active log, oldest first.
    var active: [JobRecord]
  }

  private var cache: Cache?

  /// One history read and whether `_diag` actually answered this time.
  ///
  /// Availability is deliberately separate from `history`: on a transient
  /// failure the latter contains the last evidence this reader could preserve,
  /// while a cold reader has no evidence and therefore returns an empty
  /// history. Neither case is the same as successfully reading an empty
  /// directory.
  public struct Reading: Equatable, Sendable {
    public let history: JobHistory
    public let isAvailable: Bool
  }

  /// A successful empty listing is evidence that the history is gone. A
  /// failed listing is no evidence about the directory's contents at all.
  private enum LogListing {
    case available([URL])
    case unavailable
  }

  public init() {}

  /// The log the listener had open at the last read, and nil until something
  /// has been read.
  ///
  /// Exposed so that the one other thing which needs this file — the runner's
  /// version, which is written in its header — does not list `_diag` a second
  /// time to find the file this type has just found. That listing is the work
  /// the cache above exists to avoid, and doing it twice per runner per refresh
  /// grows with exactly the number of files the sweep is there to bound.
  public var activeLog: URL? { cache?.activeLog }

  /// Blocks the calling thread on file I/O.
  ///
  /// The same rule as `RunnerDiscovery.discover()`: safe only from a thread
  /// that is yours to block, which rules out the main actor and the cooperative
  /// pool. Usually it is a directory listing and one `stat`, but "usually" is
  /// not something a concurrency model can be built on, and the cold read is
  /// hundreds of kilobytes off a home directory that may be on a network
  /// volume.
  ///
  /// - Parameter directory: the runner's `_diag`.
  public mutating func read(diagnosticsIn directory: URL) -> JobHistory {
    reading(diagnosticsIn: directory).history
  }

  /// Reads history while preserving whether the filesystem supplied evidence.
  ///
  /// Callers that compare readings over time must use this overload. An empty
  /// available history is a real baseline; an empty unavailable one is only an
  /// admission that a cold reader could not inspect `_diag` yet.
  public mutating func reading(diagnosticsIn directory: URL) -> Reading {
    let logs: [URL]
    switch Self.listenerLogs(in: directory) {
    case .available(let listed): logs = listed
    case .unavailable:
      // A transient permissions, volume or filesystem error cannot prove that
      // jobs ended or logs disappeared. Preserve both the last history and the
      // offset needed to resume incrementally when `_diag` answers again.
      return Reading(history: history(), isAvailable: false)
    }
    guard let active = logs.last else {
      // No listener has ever run here, or `_diag` has been cleared out. Either
      // way there is no history, and holding on to the one from before would
      // be showing jobs whose evidence is gone.
      cache = nil
      return Reading(history: .empty, isAvailable: true)
    }
    guard let size = Self.size(of: active) else {
      // The file was there a moment ago and would not answer now. Whatever is
      // already known is better than an empty menu, and the next refresh is
      // fifteen seconds away.
      return Reading(history: history(), isAvailable: false)
    }

    if var cached = cache, cached.activeLog == active, cached.consumed <= size {
      // The steady state, and the reason this is worth its cache: an idle
      // listener writes nothing at all, so a refresh that finds the same size
      // reads not one byte.
      if cached.consumed < size {
        // Nothing is skipped here: the delta starts exactly where the last
        // whole line ended, so its first line is a whole one.
        guard
          let delta = Self.events(
            in: active, from: cached.consumed, to: size, skippingFirstLine: false)
        else {
          return Reading(history: history(), isAvailable: false)
        }
        cached.active = Self.trimmed(Self.fold(delta.events, into: cached.active))
        cached.consumed = delta.consumed
      }
      cache = cached
      return Reading(history: history(), isAvailable: true)
    }

    // Either nothing has been read yet, or the listener has rotated. A rotation
    // is not a special case worth handling in place: the new log is short, and
    // re-deriving the history from the files on disk needs no offset to have
    // survived anything.
    guard let refreshed = Self.coldStart(logs, active: active, activeSize: size)
    else {
      // Do not install a partial cache. In particular, a cold reader must try
      // the historical logs again rather than remember an I/O failure as a
      // successfully empty history.
      return Reading(history: history(), isAvailable: false)
    }
    cache = refreshed
    return Reading(history: history(), isAvailable: true)
  }

  private func history() -> JobHistory {
    guard let cache else { return .empty }
    let combined = Self.trimmed(cache.older + cache.active)
    // Only the active log can hold a job that is still running. An unfinished
    // job in a log the listener has stopped writing to is one that was cut off
    // when the listener went down — the same missing line, for opposite
    // reasons, and reporting the second as the first would leave "Running
    // testflight — 14h" over an idle machine.
    let running = cache.active.last.flatMap { $0.finishedAt == nil ? $0 : nil }
    return JobHistory(records: combined.reversed(), running: running)
  }

  // MARK: - Reading

  private static func coldStart(
    _ logs: [URL], active: URL, activeSize: Int
  ) -> Cache? {
    let from = max(0, activeSize - tailWindow)
    guard
      let read = events(
        in: active, from: from, to: activeSize, skippingFirstLine: from > 0)
    else { return nil }
    let current = trimmed(fold(read.events, into: []))

    // Backwards through the rotations until there is enough history or enough
    // has been read. A listener opens a new log every time it starts, so a Mac
    // that sleeps and wakes — or a runner restarted from this very menu —
    // rotates without running a single job, and the jobs can be several files
    // back.
    var older: [[JobRecord]] = []
    var known = current.count
    var budget = coldReadBudget
    for log in logs.dropLast().suffix(maxFiles).reversed() {
      guard known < maxRecords, budget > 0 else { break }
      // Folded on its own. Each listener log is a closed world: a job never
      // spans two of them, because the process that would have written the
      // second line is the one that ended. Folding them together would let a
      // completion at the top of one log close a job left dangling at the
      // bottom of the log before it, and hand it hours of somebody else's time.
      // A rotated log is historical evidence, not the source of the current
      // state. If one remains unreadable, stop at that boundary: older history
      // may be incomplete, but poisoning the readable active log would hide
      // current jobs, version and future notifications on every refresh. The
      // active log above still fails closed because it alone can describe work
      // happening now.
      guard let events = tailEvents(of: log) else { break }
      let records = fold(events, into: [])
      budget -= min(size(of: log) ?? 0, tailWindow)
      known += records.count
      older.append(records)
    }

    return Cache(
      activeLog: active,
      // Never less than where the window opened: the bytes before it were
      // skipped deliberately and re-reading them would undo the ceiling.
      consumed: max(read.consumed, from),
      older: trimmed(older.reversed().flatMap { $0 }),
      active: current)
  }

  private static func tailEvents(of log: URL) -> [JobLogEvent]? {
    guard let size = size(of: log) else { return nil }
    let from = max(0, size - tailWindow)
    return events(in: log, from: from, to: size, skippingFirstLine: from > 0)?.events
  }

  /// The events in the whole lines of `[from, to)`, and the offset one past the
  /// last of them.
  ///
  /// Whole lines only at the end. The listener may be halfway through writing
  /// one when this reads, and a line consumed in halves is a job start seen as
  /// neither. What is left over stays unconsumed and is read again next time.
  ///
  /// - Parameter skippingFirstLine: for a window opened partway into a file,
  ///   which almost certainly opened partway into a line. False for a delta,
  ///   whose first line is whole by construction — dropping it there costs one
  ///   real line per refresh, which is a job start or a job result.
  private static func events(
    in log: URL, from: Int, to end: Int, skippingFirstLine: Bool
  ) -> (events: [JobLogEvent], consumed: Int)? {
    guard end > from else { return ([], from) }
    guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
    defer { try? handle.close() }
    guard (try? handle.seek(toOffset: UInt64(from))) != nil else { return nil }
    guard let data = try? handle.read(upToCount: end - from), !data.isEmpty
    else { return nil }
    // A successful read with no complete line is still an available reading.
    // Leave the bytes unconsumed so the next append can complete the line.
    guard let lastBreak = data.lastIndex(of: UInt8(ascii: "\n")) else {
      return ([], from)
    }

    let whole = data[data.startIndex...lastBreak]
    // Counted in bytes rather than in characters. Lossy UTF-8 decoding turns
    // one bad byte into a three-byte replacement, and an offset off by two is
    // a line replayed or skipped on every refresh from then on.
    let consumed = from + whole.count
    var lines = String(decoding: whole, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: false)
    if skippingFirstLine, !lines.isEmpty { lines.removeFirst() }
    return (lines.compactMap(JobLogParser.event(in:)), consumed)
  }

  // MARK: - Folding events into jobs

  static func fold(_ events: [JobLogEvent], into records: [JobRecord]) -> [JobRecord] {
    var records = records
    for event in events {
      switch event {
      case .started(let name, let at):
        records.append(JobRecord(name: name, startedAt: at))
      case .finished(let result, let at):
        // Closes the newest job still open. A completion with nothing open is
        // a job whose start line fell outside the window that was read, and
        // inventing a record for it would put a job of unknown name and
        // unknowable duration in the menu.
        guard let last = records.indices.last, records[last].finishedAt == nil
        else { continue }
        records[last] = JobRecord(
          name: records[last].name, startedAt: records[last].startedAt,
          finishedAt: at, result: result)
      }
    }
    return records
  }

  private static func trimmed(_ records: [JobRecord]) -> [JobRecord] {
    records.count <= maxRecords ? records : Array(records.suffix(maxRecords))
  }

  // MARK: - Finding the logs

  private static func listenerLogs(in directory: URL) -> LogListing {
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    } catch {
      let failure = error as NSError
      // A runner directory can disappear between discovery and this read. That
      // is confirmed absence, not an outage, and retains the established
      // behavior of presenting no history for a missing `_diag`.
      if failure.domain == NSCocoaErrorDomain,
        failure.code == CocoaError.Code.fileReadNoSuchFile.rawValue
          || failure.code == CocoaError.Code.fileNoSuchFile.rawValue
      {
        return .available([])
      }
      return .unavailable
    }
    return .available(
      entries
        .filter { $0.lastPathComponent.hasPrefix(logPrefix) && $0.pathExtension == "log" }
        // Sorted by name, not by modification date. The name carries the UTC
        // instant the listener started, fixed-width so it sorts as text, and it
        // is written once and never touched again — where an mtime is rewritten
        // by anything that copies the directory, a backup restore included.
        .sorted { $0.lastPathComponent < $1.lastPathComponent })
  }

  private static func size(of url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
  }
}
