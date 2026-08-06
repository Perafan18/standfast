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
  /// Where the runner keeps its own logs. Not configurable and not recorded in
  /// `.runner`: the name is compiled into the runner, which is why this can be
  /// derived rather than discovered.
  public var diagnosticsDirectory: URL { directory.appendingPathComponent("_diag") }
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

extension DiscoveredRunner {
  /// Resolves the part of a work path that exists and proves the result stays
  /// under the runner. Returning the resolved spelling also means a later
  /// replacement of the configured symlink cannot redirect an operation that
  /// already crossed this boundary.
  var containedWorkDirectory: URL? {
    guard let resolvedRunner = Self.resolvingExistingPathComponents(in: directory),
      let resolvedWork = Self.resolvingExistingPathComponents(in: workDirectory)
    else { return nil }

    let runnerPath = resolvedRunner.path
    let workPath = resolvedWork.path
    guard workPath == runnerPath || workPath.hasPrefix(runnerPath + "/") else {
      return nil
    }
    return resolvedWork
  }

  /// `resolvingSymlinksInPath` leaves a wholly missing suffix unresolved. Walk
  /// upward until something exists, resolve that ancestor, then restore the
  /// suffix. A dangling symlink is not the same as a missing directory: its
  /// destination cannot be proved contained, so it fails closed.
  private static func resolvingExistingPathComponents(in url: URL) -> URL? {
    let standardized = url.standardizedFileURL
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: standardized.path)
      let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
      if attributes[.type] as? FileAttributeType == .typeSymbolicLink,
        resolved.path == standardized.path
      {
        return nil
      }
      return resolved
    } catch {
      guard Self.isNoSuchFile(error) else { return nil }
      let parent = standardized.deletingLastPathComponent()
      guard parent.path != standardized.path,
        let resolvedParent = Self.resolvingExistingPathComponents(in: parent)
      else { return nil }
      return resolvedParent.appendingPathComponent(standardized.lastPathComponent)
        .standardizedFileURL
    }
  }

  private static func isNoSuchFile(_ error: any Error) -> Bool {
    let error = error as NSError
    guard error.domain == NSCocoaErrorDomain else { return false }
    return error.code == CocoaError.Code.fileNoSuchFile.rawValue
      || error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
  }
}

/// The outcome of one scan.
///
/// The failures are kept instead of being folded into an empty list. "No
/// runner is installed" and "two are installed and neither could be read"
/// both come out as no runners, and only the second means something is
/// wrong — telling that user to install a runner is the one answer certain
/// to be useless.
public enum DiscoveryFailure: Equatable, Sendable {
  case launchAgentsUnreadable(URL)
}

public struct DiscoveryResult: Equatable, Sendable {
  public let runners: [DiscoveredRunner]
  /// LaunchAgents that announced themselves as runners and could not be
  /// resolved: unreadable plist, missing or corrupt `.runner`, permissions.
  /// Paths rather than errors — enough to name the file that needs looking
  /// at, without a diagnosis this version could not act on anyway.
  public let unreadable: [URL]
  /// Why the scan itself could not start, rather than why one runner candidate
  /// could not be resolved.
  public let failure: DiscoveryFailure?
  /// Labels that may still be installed even though their runner could not be
  /// resolved, and nil when the scan could not identify every possible label.
  ///
  /// An empty set is meaningful: it says the directory was enumerated and no
  /// unresolved candidate can own a label. Callers may use that as removal
  /// evidence. Nil says absence from `runners` proves nothing.
  public let possiblyInstalledLabels: Set<String>?

  public init(
    runners: [DiscoveredRunner], unreadable: [URL] = [],
    failure: DiscoveryFailure? = nil,
    possiblyInstalledLabels: Set<String>? = nil
  ) {
    self.runners = runners
    self.unreadable = unreadable
    self.failure = failure
    if failure != nil {
      self.possiblyInstalledLabels = nil
    } else if unreadable.isEmpty {
      self.possiblyInstalledLabels = []
    } else {
      self.possiblyInstalledLabels = possiblyInstalledLabels
    }
  }
}

/// Finds every self-hosted runner on this machine without asking the user
/// anything. Runners installed as a service leave a LaunchAgent behind, and
/// that plist points at the runner directory, which describes itself in
/// `.runner`.
public struct RunnerDiscovery: Sendable {
  private let launchAgentsDirectory: URL
  private let listDirectory: @Sendable (URL) throws -> [URL]

  public init(launchAgentsDirectory: URL? = nil) {
    self.launchAgentsDirectory =
      launchAgentsDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents")
    self.listDirectory = { directory in
      try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    }
  }

  init(
    launchAgentsDirectory: URL,
    listDirectory: @escaping @Sendable (URL) throws -> [URL]
  ) {
    self.launchAgentsDirectory = launchAgentsDirectory
    self.listDirectory = listDirectory
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
    let entries: [URL]
    do {
      entries = try listDirectory(launchAgentsDirectory)
    } catch {
      if Self.isNoSuchFile(error) {
        return DiscoveryResult(runners: [])
      }
      return DiscoveryResult(
        runners: [], failure: .launchAgentsUnreadable(launchAgentsDirectory))
    }

    let candidates =
      entries
      .filter { $0.lastPathComponent.hasPrefix(DiscoveredRunner.labelPrefix) }
      .filter { $0.pathExtension == "plist" }

    var runners: [DiscoveredRunner] = []
    var unreadable: [URL] = []
    var possiblyInstalledLabels: Set<String> = []
    var hasUnidentifiedCandidate = false
    for candidate in candidates {
      let resolved = runner(fromPlistAt: candidate)
      if let runner = resolved.runner {
        runners.append(runner)
      } else {
        unreadable.append(candidate)
        if let label = resolved.label {
          possiblyInstalledLabels.insert(label)
        } else {
          hasUnidentifiedCandidate = true
        }
      }
    }

    return DiscoveryResult(
      runners: deduplicatedByLabel(runners),
      unreadable: unreadable.sorted { $0.path < $1.path },
      possiblyInstalledLabels: hasUnidentifiedCandidate ? nil : possiblyInstalledLabels)
  }

  private static func isNoSuchFile(_ error: any Error) -> Bool {
    let error = error as NSError
    guard error.domain == NSCocoaErrorDomain else { return false }
    return error.code == CocoaError.Code.fileNoSuchFile.rawValue
      || error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
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

  private func runner(
    fromPlistAt url: URL
  ) -> (
    runner: DiscoveredRunner?, label: String?
  ) {
    guard let agent = try? LaunchAgentDescriptor(contentsOf: url) else {
      return (nil, nil)
    }
    let runnerFile = agent.workingDirectory.appendingPathComponent(".runner")
    // A plist whose runner directory is gone is a half-finished uninstall.
    // Surfacing it would only add a permanently broken row to the menu.
    guard let config = try? RunnerConfig(contentsOf: runnerFile),
      let scope = RunnerScope(gitHubURL: config.gitHubUrl)
    else { return (nil, agent.label) }

    let runner = DiscoveredRunner(
      label: agent.label,
      directory: agent.workingDirectory,
      agentId: config.agentId,
      agentName: config.agentName,
      scope: scope,
      workFolder: config.workFolder)
    guard runner.containedWorkDirectory != nil else { return (nil, agent.label) }
    return (runner, agent.label)
  }
}
