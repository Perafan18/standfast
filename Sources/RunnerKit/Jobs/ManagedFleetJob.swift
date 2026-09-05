import Foundation

/// Optional current-work evidence from the supervisor, not local job history.
/// URLs are constructed from validated identifiers, never accepted as commands
/// or arbitrary URL schemes from a snapshot.
public struct ManagedFleetJob: Decodable, Equatable, Sendable {
  public let id: Int
  public let runID: Int
  public let runAttempt: Int
  public let runnerID: Int
  public let runnerName: String
  public let repository: String
  public let hostname: String
  public let workflowName: String
  public let name: String
  public let event: String
  public let pullRequestNumbers: [Int]
  public let observedAt: Date

  enum CodingKeys: String, CodingKey {
    case id, repository, hostname, name, event
    case runID = "run_id"
    case runAttempt = "run_attempt"
    case runnerID = "runner_id"
    case runnerName = "runner_name"
    case workflowName = "workflow_name"
    case pullRequestNumbers = "pull_request_numbers"
    case observedAt = "observed_at"
  }

  public var jobURL: URL? { link("actions/runs/\(runID)/job/\(id)") }
  public var runURL: URL? { link("actions/runs/\(runID)/attempts/\(runAttempt)") }
  public func pullRequestURL(_ number: Int) -> URL? {
    guard pullRequestNumbers.contains(number) else { return nil }
    return link("pull/\(number)")
  }

  private func link(_ suffix: String) -> URL? {
    guard isValid else { return nil }
    return URL(string: "https://\(hostname)/\(repository)/\(suffix)")
  }

  var isValid: Bool {
    id > 0 && runID > 0 && runAttempt > 0 && runnerID > 0
      && hostname.range(
        of: #"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*\z"#, options: .regularExpression) != nil
      && repository.range(
        of: #"^[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*\z"#,
        options: .regularExpression) != nil
      && [runnerName, workflowName, name, event].allSatisfy {
        !$0.isEmpty && $0.count <= 500
          && $0.rangeOfCharacter(from: .controlCharacters) == nil
      }
      && pullRequestNumbers.count <= 100
      && pullRequestNumbers.allSatisfy { $0 > 0 }
      && Set(pullRequestNumbers).count == pullRequestNumbers.count
  }
}
