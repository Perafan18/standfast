import Foundation

/// What GitHub has queued in one scope, and whether that is all of it.
public struct QueuedWork: Equatable, Sendable {
  public let jobs: [QueuedJob]
  /// True when GitHub had more queued runs, or one run more jobs, than this
  /// client agreed to look at. Said out loud rather than swallowed: a capped
  /// count presented as a total is a silent truncation, and reads as "we
  /// covered everything" when it did not.
  public let isPartial: Bool

  public init(jobs: [QueuedJob], isPartial: Bool) {
    self.jobs = jobs
    self.isPartial = isPartial
  }

  /// The jobs waiting specifically for a runner carrying these labels.
  public func waiting(forRunnerLabelled labels: [String]) -> [QueuedJob] {
    jobs.filter { $0.waits(forRunnerLabelled: labels) }
  }
}

/// Asks what work is queued and unclaimed.
///
/// Its own protocol, beside `GitHubClient` and `RunnerReleaseChecking`, for the
/// same reason those are separate: it is a different question, asked at a
/// different rate, and it costs more than either — one call to list the runs
/// plus one per run to read its jobs.
public protocol QueuedWorkReading: Sendable {
  func blockingQueuedWork(in scope: RunnerScope) throws -> QueuedWork
}
