import Foundation

/// A throwaway `_diag`, written the way a runner writes one.
///
/// The lines are copies of real ones off a runner on a real Mac, down to the
/// double timestamp and the `WRITE LINE:` prefix. CI has no runner, so this is
/// the only place the format is pinned — which makes a fixture that drifts from
/// the real thing the one failure this suite could not see. Keep it verbatim.
struct ListenerLogSandbox {
  let root: URL

  init() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("diag-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: diagnostics, withIntermediateDirectories: true)
  }

  var diagnostics: URL { root.appendingPathComponent("_diag") }

  func cleanUp() { try? FileManager.default.removeItem(at: root) }

  /// - Parameter startedAt: the UTC instant in the file name, which is how the
  ///   runner records when this listener started — `20260805-215453`.
  @discardableResult
  func writeLog(startedAt: String, _ lines: [String]) throws -> URL {
    let url = diagnostics.appendingPathComponent("Runner_\(startedAt)-utc.log")
    try write(lines.map { $0 + "\n" }.joined(), to: url)
    return url
  }

  /// A worker log, which sits in the same directory, is ten times the size and
  /// holds nothing this reads.
  @discardableResult
  func writeWorkerLog(startedAt: String, _ lines: [String]) throws -> URL {
    let url = diagnostics.appendingPathComponent("Worker_\(startedAt)-utc.log")
    try write(lines.map { $0 + "\n" }.joined(), to: url)
    return url
  }

  func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }

  /// Rewrites bytes already on disk without changing the file's length.
  ///
  /// How a test asks "did you read this again?". Everything the reader has
  /// already consumed is supposed to stay consumed, so replacing it with noise
  /// must change nothing at all.
  func overwrite(_ url: URL, at offset: Int, with text: String) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(offset))
    try handle.write(contentsOf: Data(text.utf8))
  }

  private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
  }
}

// MARK: - The lines themselves

/// `[2026-08-05 20:36:14Z INFO Terminal] WRITE LINE: 2026-08-05 20:36:14Z: …`
private func terminalLine(_ stamp: String, _ message: String) -> String {
  "[\(stamp) INFO Terminal] WRITE LINE: \(stamp): \(message)"
}

func startedJob(_ name: String, at stamp: String) -> String {
  terminalLine(stamp, "Running job: \(name)")
}

func finishedJob(_ name: String, _ result: String, at stamp: String) -> String {
  terminalLine(stamp, "Job \(name) completed with result: \(result)")
}

/// The rest of what a listener says, and the overwhelming majority of the file.
func listenerChatter(at stamp: String) -> [String] {
  [
    "[\(stamp) INFO Listener] Version: 2.336.0",
    "[\(stamp) INFO HostContext] Well known directory 'Root': '/Users/x/actions-runner'",
    terminalLine(stamp, "Listening for Jobs"),
    "[\(stamp) INFO JobDispatcher] Set runner/worker IPC timeout to 30 seconds.",
  ]
}

/// Parsed with Foundation rather than with the parser under test, so a
/// hand-rolled reader that got the time zone or the field order wrong has
/// something independent to disagree with.
func utcInstant(_ text: String) -> Date {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss'Z'"
  guard let date = formatter.date(from: text) else {
    fatalError("not a UTC instant: \(text)")
  }
  return date
}
