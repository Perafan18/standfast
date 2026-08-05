import Foundation

/// The two fields of a runner's LaunchAgent that matter: the label
/// `launchctl` answers to, and where the runner is installed.
struct LaunchAgentDescriptor: Equatable, Sendable {
  let label: String
  let workingDirectory: URL

  private struct Payload: Decodable {
    let label: String
    let workingDirectory: String
    enum CodingKeys: String, CodingKey {
      case label = "Label"
      case workingDirectory = "WorkingDirectory"
    }
  }

  init(contentsOf url: URL) throws {
    let payload = try PropertyListDecoder().decode(
      Payload.self, from: Data(contentsOf: url))
    self.label = payload.label
    self.workingDirectory = URL(fileURLWithPath: payload.workingDirectory)
  }
}
