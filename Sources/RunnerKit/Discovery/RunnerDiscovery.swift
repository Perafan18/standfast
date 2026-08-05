import Foundation

/// One runner installed on this machine, as found on disk.
public struct DiscoveredRunner: Equatable, Sendable, Identifiable {
  public let label: String
  public let directory: URL
  public let agentId: Int
  public let agentName: String
  public let scope: RunnerScope

  public var id: String { label }
  public var workDirectory: URL { directory.appendingPathComponent(workFolder) }
  let workFolder: String
}

/// Finds every self-hosted runner on this machine without asking the user
/// anything. Runners installed as a service leave a LaunchAgent behind, and
/// that plist points at the runner directory, which describes itself in
/// `.runner`.
public struct RunnerDiscovery: Sendable {
  private let launchAgentsDirectory: URL

  public init(launchAgentsDirectory: URL? = nil) {
    self.launchAgentsDirectory =
      launchAgentsDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
  }

  public func discover() -> [DiscoveredRunner] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: launchAgentsDirectory,
        includingPropertiesForKeys: nil)) ?? []

    return
      entries
      .filter { $0.lastPathComponent.hasPrefix("actions.runner.") }
      .filter { $0.pathExtension == "plist" }
      .compactMap(runner(fromPlistAt:))
      .sorted { $0.label < $1.label }
  }

  private func runner(fromPlistAt url: URL) -> DiscoveredRunner? {
    guard let agent = try? LaunchAgentDescriptor(contentsOf: url) else { return nil }
    let runnerFile = agent.workingDirectory.appendingPathComponent(".runner")
    // A plist whose runner directory is gone is a half-finished uninstall.
    // Surfacing it would only add a permanently broken row to the menu.
    guard let config = try? RunnerConfig(contentsOf: runnerFile),
      let scope = RunnerScope(gitHubURL: config.gitHubUrl)
    else { return nil }

    return DiscoveredRunner(
      label: agent.label,
      directory: agent.workingDirectory,
      agentId: config.agentId,
      agentName: config.agentName,
      scope: scope,
      workFolder: config.workFolder)
  }
}
