import Foundation
import RunnerKit

// What the menu says about work: the job in flight, the ones before it, and
// when any of it was last looked at. Values a test can read, like everything
// else in `FleetPresentation.swift`.

struct JobOutcomePresentation: Equatable, Sendable {
  let label: String
  let symbolName: String
  let tone: StateTone
}

struct JobRow: Equatable, Identifiable, Sendable {
  struct ID: Equatable, Hashable, Sendable {
    let startedAt: Date
    let occurrence: Int
  }

  let id: ID
  let name: String
  let outcome: JobOutcomePresentation
  let duration: String?
  let startedAt: Date
  let finishedAt: Date?

  static func building(_ record: JobRecord) -> Self {
    building(record, occurrence: 0)
  }

  private static func building(_ record: JobRecord, occurrence: Int) -> Self {
    Self(
      id: ID(startedAt: record.startedAt, occurrence: occurrence), name: record.name,
      outcome: record.outcomePresentation,
      duration: record.duration.map(DurationText.precise),
      startedAt: record.startedAt, finishedAt: record.finishedAt)
  }

  static func building(_ records: [JobRecord]) -> [Self] {
    var occurrences: [Date: Int] = [:]

    return records.map { record in
      let occurrence = occurrences[record.startedAt, default: 0]
      occurrences[record.startedAt] = occurrence + 1
      return building(record, occurrence: occurrence)
    }
  }

  var text: String {
    guard let duration else { return L10n.jobRowNoDuration(name, outcome.label) }
    return L10n.jobRow(name, outcome.label, duration)
  }
}

/// Durations as the menu writes them.
enum DurationText {
  /// `2m 47s` — for a job, where the seconds are the whole point: the machine
  /// this was built against runs the same job in 2m45s to 2m57s, and a
  /// difference that small is the only signal there is.
  static func precise(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total >= 3600 {
      return L10n.durationHoursMinutes(total / 3600, (total % 3600) / 60)
    }
    if total >= 60 { return L10n.durationMinutesSeconds(total / 60, total % 60) }
    // Never negative. A clock that went backwards between a job starting and
    // this being asked — a manual change, an NTP correction — must not print a
    // minus sign into the menu bar.
    return L10n.durationSeconds(max(0, total))
  }

  /// `3m` — for how long ago something happened, where the seconds are noise.
  static func coarse(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    if total >= 3600 { return L10n.durationHours(total / 3600) }
    if total >= 60 { return L10n.durationMinutes(total / 60) }
    return L10n.durationSeconds(max(0, total))
  }
}

/// The line over a runner that is working.
struct JobProgress: Equatable {
  let name: String
  let elapsed: TimeInterval
  /// What this job usually takes, and nil when there is not enough history of
  /// the same job to say. See `JobHistory.typicalDuration(ofJobNamed:)`.
  let typical: TimeInterval?

  /// Whether this job has already taken longer than it usually does, and false
  /// when there is no estimate to be longer than. What makes a thermal warning
  /// worth showing: without an overrun the temperature explains nothing.
  var isOverTypical: Bool {
    guard let typical else { return false }
    return elapsed > typical
  }

  /// Elapsed time and a reference, never a countdown.
  ///
  /// "1m20s, usually 2m50s" stays true and stays useful at 4m20s, where "1m30s
  /// remaining" would have gone negative — and the moment a job overruns is
  /// precisely the moment somebody wants to look at this.
  var line: String {
    guard let typical else {
      return L10n.jobRunning(name, DurationText.precise(elapsed))
    }
    return L10n.jobRunningWithTypical(
      name, DurationText.precise(elapsed), DurationText.precise(typical))
  }
}

extension JobProgress {
  /// Nil unless this runner is actually busy.
  ///
  /// Two sources, and the log is not allowed to speak on its own. A listener
  /// killed mid-job — power cut, `svc.sh stop`, a crash — leaves a start line
  /// that no completion ever follows, and reading that alone would put
  /// "Running testflight — 14h" over a machine that has been idle since
  /// breakfast. GitHub answers whether work is happening; the log only names
  /// what it is.
  ///
  /// - Parameter now: the moment the state was read, not the moment this is
  ///   rendered, so every number in one row describes the same instant.
  static func reading(
    _ history: JobHistory, display: DisplayState, at now: Date
  ) -> JobProgress? {
    guard display.resolvedState == .busy, let running = history.running else {
      return nil
    }
    return JobProgress(
      name: running.name,
      elapsed: now.timeIntervalSince(running.startedAt),
      typical: history.typicalDuration(ofJobNamed: running.name))
  }
}

extension JobRecord {
  var resultText: String {
    switch result {
    case .succeeded: L10n.jobSucceeded
    case .failed: L10n.jobFailed
    case .canceled: L10n.jobCanceled
    // Verbatim. GitHub's word for an outcome this version has not met is still
    // readable; a translation of it would be one this app made up, and folding
    // it into "failed" would be a claim nobody checked.
    case .other(let word): word
    // No completion line was ever written. The listener went down with the job
    // still running, which is worth saying — it is the one outcome that means
    // the machine, rather than the code, is what went wrong.
    case nil: L10n.jobInterrupted
    }
  }

  var historyLine: String {
    guard let duration else { return L10n.jobRowNoDuration(name, resultText) }
    return L10n.jobRow(name, resultText, DurationText.precise(duration))
  }

  var outcomePresentation: JobOutcomePresentation {
    switch result {
    case .succeeded:
      .init(
        label: L10n.jobSucceeded, symbolName: "checkmark.circle.fill",
        tone: .healthy)
    case .failed:
      .init(label: L10n.jobFailed, symbolName: "xmark.circle.fill", tone: .attention)
    case .canceled:
      .init(label: L10n.jobCanceled, symbolName: "minus.circle.fill", tone: .neutral)
    case .other(let word):
      .init(label: word, symbolName: "questionmark.circle", tone: .neutral)
    case nil:
      .init(
        label: L10n.jobInterrupted,
        symbolName: "exclamationmark.triangle.fill", tone: .attention)
    }
  }
}

/// What the menu says about itself.
enum FleetStatus {
  /// Under this, "just now". A menu bar app that reports "Checked 2s ago" is
  /// answering a question nobody has yet; the number only starts meaning
  /// something once it might be a problem.
  static let justNow: TimeInterval = 10

  /// When the machine was last read.
  ///
  /// - Parameter readAt: when the scan behind what is on screen *started*
  ///   reading, which is deliberately not when it finished. A `gh` that hangs
  ///   for thirty seconds leaves a stale menu, and this is the line that has to
  ///   say so — stamping it on arrival would report freshly-read data that is
  ///   half a minute old.
  /// - Parameter isScanning: whether a reading is in flight right now. A `gh`
  ///   call has a 30s ceiling per runner, so Refresh can leave an unchanged
  ///   window on screen for most of a minute; this line is where that belongs,
  ///   because it is already the one answering how current the window is.
  static func lastCheckedLine(readAt: Date?, now: Date, isScanning: Bool) -> String {
    if isScanning { return L10n.checkingRunners }
    guard let readAt else { return L10n.checkedNever }
    let elapsed = now.timeIntervalSince(readAt)
    guard elapsed >= justNow else { return L10n.checkedJustNow }
    return L10n.checkedAgo(DurationText.coarse(elapsed))
  }
}
