import Foundation
import RunnerKit

struct ManagedFleetJobPresentation: Equatable {
  struct Link: Equatable, Identifiable {
    let title: String
    let url: URL
    var id: URL { url }
  }

  let context: String
  let detail: String
  let association: String
  let links: [Link]

  static func building(_ snapshot: RunnerSnapshot, now: Date) -> Self? {
    guard snapshot.runner.installation == .managedFleet,
      snapshot.display == .resolved(.busy),
      let job = snapshot.runner.currentJob,
      now.timeIntervalSince(job.observedAt) >= -5,
      now.timeIntervalSince(job.observedAt) <= 120,
      let jobURL = job.jobURL, let runURL = job.runURL
    else { return nil }
    let references = job.pullRequestNumbers.map { "#\($0)" }.joined(separator: ", ")
    let context = references.isEmpty ? job.repository : "\(job.repository) \(references)"
    var links = [
      Link(title: L10n.managedJobOpen, url: jobURL),
      Link(title: L10n.managedRunOpen, url: runURL),
    ]
    links += job.pullRequestNumbers.compactMap { number in
      job.pullRequestURL(number).map {
        Link(title: L10n.managedPROpen(number), url: $0)
      }
    }
    return Self(
      context: context,
      detail: "\(job.workflowName) · \(job.name)",
      association: references.isEmpty ? L10n.managedJobNoPR(job.event) : references,
      links: links)
  }
}
