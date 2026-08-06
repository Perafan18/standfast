import Foundation

/// One runner installed on this machine, as found on disk.
public struct DiscoveredRunner: Equatable, Sendable, Identifiable {
  public let label: String
  public let directory: URL
  public let agentId: Int
  /// What the runner calls itself, empty when `.runner` carries no usable
  /// name. Left as found: a caller that wants to mark a nameless runner as
  /// such needs to be able to tell.
  public let agentName: String
  public let scope: RunnerScope

  public var id: String { label }
  public var workDirectory: URL { directory.appendingPathComponent(workFolder) }
  let workFolder: String

  /// A name that is never blank, for callers that just need to render one.
  ///
  /// The label is the only fallback available, minus the prefix every runner
  /// agent carries — fifteen characters of noise in front of every row. What
  /// remains still holds the scope slug, so this reads
  /// `acme-widget.build-mac` rather than the machine name alone. Recovering
  /// just the latter would mean splitting the slug back apart, and that
  /// undocumented naming convention is exactly what discovery avoids relying
  /// on everywhere else.
  public var displayName: String {
    if !agentName.isEmpty { return agentName }
    guard label.hasPrefix(Self.labelPrefix) else { return label }
    return String(label.dropFirst(Self.labelPrefix.count))
  }

  /// Every runner LaunchAgent is labelled `actions.runner.<scope>.<name>`,
  /// which is also how discovery picks them out of the directory.
  static let labelPrefix = "actions.runner."

  /// `workFolder` is internal, so the memberwise init is too, which would put
  /// this type out of reach of the app target — SwiftUI previews need to build
  /// one without a runner installed.
  public init(
    label: String, directory: URL, agentId: Int, agentName: String,
    scope: RunnerScope, workFolder: String = "_work"
  ) {
    self.label = label
    self.directory = directory
    self.agentId = agentId
    self.agentName = agentName
    self.scope = scope
    self.workFolder = workFolder
  }
}

/// The outcome of one scan.
///
/// The failures are kept instead of being folded into an empty list. "No
/// runner is installed" and "two are installed and neither could be read"
/// both come out as no runners, and only the second means something is
/// wrong — telling that user to install a runner is the one answer certain
/// to be useless.
public struct DiscoveryResult: Equatable, Sendable {
  public let runners: [DiscoveredRunner]
  /// LaunchAgents that announced themselves as runners and could not be
  /// resolved: unreadable plist, missing or corrupt `.runner`, permissions.
  /// Paths rather than errors — enough to name the file that needs looking
  /// at, without a diagnosis this version could not act on anyway.
  public let unreadable: [URL]

  public init(runners: [DiscoveredRunner], unreadable: [URL] = []) {
    self.runners = runners
    self.unreadable = unreadable
  }
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

  /// Reads the whole LaunchAgents directory and a file from each runner, on the
  /// calling thread and synchronously.
  ///
  /// That is one `contentsOfDirectory` plus two file reads per runner, and a
  /// home directory on a network volume makes every one of them a round trip.
  /// So the same rule applies here as to `RunnerStateResolver.blockingState`:
  /// safe to call only from a thread that is yours to block, which rules out
  /// the main actor *and* the cooperative pool behind every `Task` — the pool
  /// has one thread per core and runs everything else in the app. Off the main
  /// actor is not enough; see `offCooperativePool`, which is what the menu bar
  /// app wraps this call in.
  public func discover() -> DiscoveryResult {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: launchAgentsDirectory,
        includingPropertiesForKeys: nil)) ?? []

    let candidates =
      entries
      .filter { $0.lastPathComponent.hasPrefix(DiscoveredRunner.labelPrefix) }
      .filter { $0.pathExtension == "plist" }

    var runners: [DiscoveredRunner] = []
    var unreadable: [URL] = []
    for candidate in candidates {
      if let runner = runner(fromPlistAt: candidate) {
        runners.append(runner)
      } else {
        unreadable.append(candidate)
      }
    }

    return DiscoveryResult(
      runners: deduplicatedByLabel(runners),
      unreadable: unreadable.sorted { $0.path < $1.path })
  }

  /// One entry per label. Duplicating a plist in Finder yields "… copy.plist",
  /// which keeps the prefix and the extension while describing the same
  /// runner; the label is what launchd registers and what `id` is built from,
  /// and a repeated `id` is undefined behaviour in the menu's `ForEach`.
  ///
  /// Sorting before the sweep does double duty: the menu is ordered by the
  /// name it shows, and which duplicate survives stops depending on the order
  /// the filesystem happened to hand back.
  private func deduplicatedByLabel(_ runners: [DiscoveredRunner]) -> [DiscoveredRunner] {
    runners
      .sorted { ($0.label, $0.directory.path) < ($1.label, $1.directory.path) }
      .reduce(into: [DiscoveredRunner]()) { unique, runner in
        if unique.last?.label != runner.label { unique.append(runner) }
      }
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
