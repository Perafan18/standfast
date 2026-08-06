import Foundation

/// How a job ended, in the runner's own words.
public enum JobResult: Equatable, Sendable {
  case succeeded
  case failed
  case canceled
  /// An outcome this version has not met. The runner serialises the name of an
  /// enum case it may add to, so the list above is what has been observed
  /// rather than what exists — and a word kept whole is still readable, where
  /// one folded into "failed" would be wrong.
  case other(String)
}

extension JobResult {
  /// The listener writes these in English whatever the runner's culture is:
  /// the only resources shipped in `bin/<language>` are a third-party
  /// validation library's, and this line is a serialised enum case rather than
  /// a message. A localised runner on this machine (`Culture: es-419`) still
  /// writes `Succeeded`.
  public init(logWord: String) {
    switch logWord {
    case "Succeeded": self = .succeeded
    case "Failed": self = .failed
    case "Canceled": self = .canceled
    default: self = .other(logWord)
    }
  }
}

/// One job this runner was given, as its own log describes it.
public struct JobRecord: Equatable, Sendable {
  /// The workflow job's display name — `testflight`, not the workflow file.
  public let name: String
  public let startedAt: Date
  /// Nil for a job with no completion line: either it is running now, or the
  /// listener went down before it could write one. Which of the two it is
  /// depends on the log file the record came from, and only the reader knows
  /// that — see `JobHistory.running`.
  public let finishedAt: Date?
  public let result: JobResult?

  public init(
    name: String, startedAt: Date, finishedAt: Date? = nil, result: JobResult? = nil
  ) {
    self.name = name
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.result = result
  }

  public var duration: TimeInterval? {
    finishedAt.map { $0.timeIntervalSince(startedAt) }
  }
}

/// What one runner has been doing, newest first.
public struct JobHistory: Equatable, Sendable {
  /// Newest first, running job included.
  public let records: [JobRecord]
  /// The job this runner is executing right now, according to its log alone.
  ///
  /// The log is not the last word on this, and the menu does not treat it as
  /// one: a listener killed mid-job leaves a start line no completion ever
  /// follows, and that record would otherwise read as a job still going hours
  /// after the machine rebooted. GitHub's `busy` is the answer to whether work
  /// is happening; this only names it.
  public let running: JobRecord?

  public init(records: [JobRecord], running: JobRecord? = nil) {
    self.records = records
    self.running = running
  }

  /// Named rather than `.none`, which in an optional context means the
  /// optional's own case.
  public static let empty = JobHistory(records: [], running: nil)
}

extension JobHistory {
  /// How many past runs an estimate is built from.
  ///
  /// The most recent ones only: a runner's job gets slower when the project
  /// grows and faster when somebody adds a cache, and a month-old run is
  /// evidence about a build that no longer exists.
  public static let samplesForEstimate = 5

  /// Below this, no estimate at all.
  ///
  /// Two samples do not have a median — the middle of them is their mean, and
  /// the mean is exactly what this is here to avoid. Three is the smallest
  /// number where one bad sample cannot move the answer, and a runner that has
  /// only ever run a job twice is one whose "usually" would be a guess wearing
  /// a number's clothes. Showing nothing is the honest report.
  public static let minimumSamplesForEstimate = 3

  /// How long this job usually takes on this runner, and nil when there is not
  /// enough of the same job to say.
  ///
  /// The median of the last few *successful* runs, and every word there was
  /// chosen against a measured way of being wrong:
  ///
  /// - **Of the same job.** A machine that builds an iOS app and lints a
  ///   README has no meaningful average job.
  /// - **Successful.** On this machine a cancelled run lasted 49 seconds and a
  ///   failed one 17, against a real duration just under three minutes:
  ///   failures usually stop at the first broken step, so their durations
  ///   measure how early something broke rather than how long the work takes.
  /// - **The median.** One of those 17-second runs is enough to pull a mean
  ///   down by half a minute and keep it there for five builds. The median
  ///   ignores it entirely, which is the whole reason to pay for a sort.
  public func typicalDuration(ofJobNamed name: String) -> TimeInterval? {
    let samples =
      records
      .filter { $0.name == name && $0.result == .succeeded }
      .compactMap(\.duration)
      .prefix(Self.samplesForEstimate)
      .sorted()
    guard samples.count >= Self.minimumSamplesForEstimate else { return nil }
    let middle = samples.count / 2
    guard samples.count.isMultiple(of: 2) else { return samples[middle] }
    return (samples[middle - 1] + samples[middle]) / 2
  }
}
