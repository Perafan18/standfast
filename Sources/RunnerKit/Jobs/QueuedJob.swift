import Foundation

/// A job GitHub has accepted and not yet given to any runner.
///
/// The other half of the question this app exists to answer. `RemoteStatus`
/// says whether a runner *can* receive work; this says whether there is any
/// work to receive. A machine that is idle because nothing is queued and a
/// machine that is idle while a job waits for it look identical today, and only
/// one of them is fine.
public struct QueuedJob: Equatable, Sendable {
  public let id: Int
  public let name: String
  public let workflowName: String
  /// What the job's `runs-on` asked for.
  public let labels: [String]
  /// When GitHub queued it, and nil when it did not say. Kept optional rather
  /// than defaulted to now: "waiting 0s" is a claim, and an absent timestamp is
  /// not evidence for it.
  public let queuedAt: Date?
  public let url: URL?

  public init(
    id: Int, name: String, workflowName: String, labels: [String],
    queuedAt: Date?, url: URL?
  ) {
    self.id = id
    self.name = name
    self.workflowName = workflowName
    self.labels = labels
    self.queuedAt = queuedAt
    self.url = url
  }

  /// Whether GitHub would hand this job to a runner carrying `runnerLabels`.
  ///
  /// GitHub's rule, which this reproduces rather than approximates: the job
  /// goes to a runner that carries **every** label the job asked for, and the
  /// runner may carry more. Getting this wrong in the generous direction is the
  /// expensive one — two runners on the same repository would both claim the
  /// same queued job, and the menu would say "1 waiting" over a machine that
  /// will never be sent it.
  ///
  /// Case-insensitive, because GitHub is. Both sides are typed by hand — the
  /// label at runner registration and the `runs-on:` in a workflow file — so
  /// `macos` and `macOS` are the same runner to GitHub, and a case-sensitive
  /// comparison here would report an idle machine as having nothing to do while
  /// a job sat waiting for it.
  public func waits(forRunnerLabelled runnerLabels: [String]) -> Bool {
    // A job that asked for nothing is not this runner's to claim. There is no
    // matching guard for a runner with no labels, and adding one was dead code:
    // an empty set satisfies nothing, so the rule below already refuses to give
    // work to a runner this app could not read the labels of.
    guard !labels.isEmpty else { return false }
    let carried = Set(runnerLabels.map { $0.lowercased() })
    return labels.allSatisfy { carried.contains($0.lowercased()) }
  }
}
