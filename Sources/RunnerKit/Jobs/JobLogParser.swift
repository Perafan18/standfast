import Foundation

/// The two things a listener log says about a job.
enum JobLogEvent: Equatable {
  case started(name: String, at: Date)
  /// Carries no name. The completion line spells one out, but a job called
  /// `deploy completed with result: Succeeded` — legal, since job display
  /// names come from the workflow — makes it ambiguous, and the start line's
  /// name never is. One self-hosted runner runs one job at a time, so the job
  /// this closes is not in question either way.
  case finished(result: JobResult, at: Date)
}

/// Reads the runner's own terminal output back out of its trace log.
///
/// The listener writes every line it prints to the terminal into
/// `_diag/Runner_<start>.log`, prefixed with the trace timestamp. Wrapped here
/// to fit; each is one line in the file:
///
/// ```
/// [2026-08-05 20:36:14Z INFO Terminal] WRITE LINE:
///     2026-08-05 20:36:14Z: Running job: testflight
/// [2026-08-05 20:38:59Z INFO Terminal] WRITE LINE:
///     2026-08-05 20:38:59Z: Job testflight completed with result: Succeeded
/// ```
///
/// Two timestamps, always the same one twice — the trace's and the terminal's,
/// written by the same call. The one after `WRITE LINE:` is used, because it is
/// the one whose position is fixed by the message rather than by the trace
/// format around it.
enum JobLogParser {
  /// Everything before this belongs to the trace, not to the runner's message.
  private static let terminalMarker = "] WRITE LINE: "
  private static let startMarker = ": Running job: "
  private static let finishPrefix = ": Job "
  private static let finishMarker = " completed with result: "
  /// `2026-08-05 20:36:14Z`
  private static let stampLength = 20

  static func event(in line: Substring) -> JobLogEvent? {
    // Tried first because it fails on almost every line, and everything below
    // it costs more.
    guard let marker = line.range(of: terminalMarker) else { return nil }
    let message = line[marker.upperBound...]
    guard message.count > stampLength else { return nil }
    let body = message.dropFirst(stampLength)
    // Parsed only once one of the two shapes has matched: the timestamp sits
    // at a fixed offset in every terminal line, and most of them are neither.
    if body.hasPrefix(startMarker) {
      let name = body.dropFirst(startMarker.count)
      guard !name.isEmpty, let at = timestamp(message.prefix(stampLength)) else {
        return nil
      }
      return .started(name: String(name), at: at)
    }
    guard body.hasPrefix(finishPrefix),
      // Searched backwards so the job name keeps the words: a job named
      // `deploy completed with result: Succeeded` produces a line with two
      // matches, and the real outcome is after the last of them.
      let split = body.range(of: finishMarker, options: .backwards)
    else { return nil }
    let word = body[split.upperBound...]
    guard !word.isEmpty, let at = timestamp(message.prefix(stampLength)) else {
      return nil
    }
    return .finished(result: JobResult(logWord: String(word)), at: at)
  }

  /// `yyyy-MM-dd HH:mm:ssZ`, always UTC — the `Z` is written by the runner, not
  /// assumed here, and a line without it is not one of these lines.
  ///
  /// Parsed by hand rather than with a `DateFormatter`: the format is fixed by
  /// the runner rather than by a locale, and a formatter would drag the host's
  /// calendar and time zone into an answer that has neither.
  static func timestamp(_ text: Substring) -> Date? {
    guard text.count == stampLength, text.hasSuffix("Z") else { return nil }
    let halves = text.dropLast().split(separator: " ")
    guard halves.count == 2 else { return nil }
    let date = halves[0].split(separator: "-")
    let time = halves[1].split(separator: ":")
    guard date.count == 3, time.count == 3,
      let year = Int(date[0]), let month = Int(date[1]), let day = Int(date[2]),
      let hour = Int(time[0]), let minute = Int(time[1]), let second = Int(time[2]),
      // Checked rather than left to the calendar, which normalises rather than
      // refuses: month 13 becomes next January, and a garbage line shaped like
      // a timestamp would be filed as a job that ran in a year nobody has
      // reached.
      (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
      (0...59).contains(minute), (0...59).contains(second)
    else { return nil }
    return utc.date(
      from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute,
        second: second))
  }

  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()
}
