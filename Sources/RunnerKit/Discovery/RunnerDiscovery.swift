import Foundation

/// One runner installed on this machine, as found on disk.
/// How this runner got onto the machine, which decides what can be done to it.
public enum RunnerInstallation: Equatable, Sendable {
  /// Installed as a service. launchd registered it under `label`, `svc.sh` can
  /// start and stop it, and the local probe can say whether it is loaded.
  case launchAgent
  /// Started by hand with `./run.sh`, and found only because somebody pointed
  /// this app at its directory. Nothing registered it, so nothing here can
  /// stop it — and there is no launchd job to ask about.
  case manual
  /// A GitLab runner, served by the machine-wide gitlab-runner process. No
  /// per-runner control exists: stopping that process stops every runner in
  /// `config.toml`, which is a decision for a terminal, not for one card's
  /// button.
  case gitLabService
}

public struct DiscoveredRunner: Equatable, Sendable, Identifiable {
  /// launchd's label for a serviced runner. For one started by hand there is
  /// no such thing, so this is built from its directory — see
  /// `manualLabel(for:)`. Either way it is the identity everything else keys
  /// on: folding, in-flight operations, the settling window.
  public let label: String
  public let directory: URL
  public let agentId: Int
  /// What the runner calls itself, empty when `.runner` carries no usable
  /// name. Left as found: a caller that wants to mark a nameless runner as
  /// such needs to be able to tell.
  public let agentName: String
  public let scope: RunnerScope
  public let installation: RunnerInstallation

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
    scope: RunnerScope, workFolder: String = "_work",
    installation: RunnerInstallation = .launchAgent
  ) {
    self.label = label
    self.directory = directory
    self.agentId = agentId
    self.agentName = agentName
    self.scope = scope
    self.workFolder = workFolder
    self.installation = installation
  }

  /// The identity of a runner launchd never heard of.
  ///
  /// The directory, because that is what actually distinguishes one: two
  /// hand-started runners on one Mac differ by where they live and nothing
  /// else. Prefixed so it can never collide with a real launchd label, which
  /// always begins `actions.runner.`, and so that anybody who finds one of
  /// these in `defaults` can tell what they are looking at.
  public static func manualLabel(for directory: URL) -> String {
    "standfast.manual:" + directory.standardizedFileURL.path
  }
}

extension DiscoveredRunner {
  /// Resolves the part of a work path that exists and proves the result stays
  /// under the runner.
  ///
  /// Public since INV-006: discovery stopped enforcing this, so the app's scan
  /// reads it to tell maintenance when to abstain — and it involves resolving
  /// symlinks, which is why the scan reads it off the main actor.
  public var containedWorkDirectory: URL? {
    Self.resolvedPath(workDirectory, containedIn: directory, allowingRoot: true)
  }

  /// `_diag` is fixed by the runner rather than configured, but it is still a
  /// path on a filesystem and can be replaced by a symlink. An internal target
  /// remains a runner directory; an external or unresolvable one does not.
  var containedDiagnosticsDirectory: URL? {
    Self.resolvedPath(diagnosticsDirectory, containedIn: directory)
  }

  /// Resolves a path and the root it must stay under. The resolved spelling is
  /// used by the immediate operation, so replacing the configured leaf symlink
  /// afterwards does not redirect that operation through the old spelling.
  ///
  /// This narrows rather than eliminates the race: `FileManager` and `du` still
  /// accept pathnames, so the same user can replace a resolved component after
  /// this check and before the syscall. Closing that remaining window requires
  /// descriptor-relative operations such as `openat`/`renameat`/`unlinkat`.
  static func resolvedPath(
    _ path: URL, containedIn root: URL, allowingRoot: Bool = false
  ) -> URL? {
    guard let resolvedRoot = Self.resolvingExistingPathComponents(in: root),
      let resolvedPath = Self.resolvingExistingPathComponents(in: path)
    else { return nil }

    let rootPath = resolvedRoot.path
    let path = resolvedPath.path
    if path == rootPath { return allowingRoot ? resolvedPath : nil }
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return path.hasPrefix(prefix) ? resolvedPath : nil
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
  /// Runner directories the operator named. Never guessed at: walking the disk
  /// looking for `.runner` files would read directories nobody asked this app
  /// to read, and would find other people's runners in shared folders.
  private let manualDirectories: [URL]
  /// Where gitlab-runner keeps its `config.toml` — a fixed, documented place,
  /// which is why GitLab runners need no pointing at.
  private let gitLabConfigFile: URL
  private let listDirectory: @Sendable (URL) throws -> [URL]

  public init(
    launchAgentsDirectory: URL? = nil, manualDirectories: [URL] = [],
    gitLabConfigFile: URL? = nil
  ) {
    self.manualDirectories = manualDirectories
    self.gitLabConfigFile =
      gitLabConfigFile
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".gitlab-runner/config.toml")
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
    manualDirectories: [URL] = [],
    gitLabConfigFile: URL? = nil,
    listDirectory: @escaping @Sendable (URL) throws -> [URL]
  ) {
    self.launchAgentsDirectory = launchAgentsDirectory
    self.manualDirectories = manualDirectories
    self.gitLabConfigFile =
      gitLabConfigFile ?? URL(fileURLWithPath: "/nonexistent/config.toml")
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
    // Read first, so a LaunchAgents directory that will not list does not take
    // the other providers down with it. None of these sources has anything to
    // do with the others, and a failure to enumerate one is no evidence about
    // any of them.
    let manual = manualRunners()
    let gitLab = gitLabRunners()

    let entries: [URL]
    do {
      entries = try listDirectory(launchAgentsDirectory)
    } catch {
      if Self.isNoSuchFile(error) {
        return DiscoveryResult(
          runners: manual.runners + gitLab.runners,
          unreadable: manual.unreadable + gitLab.unreadable)
      }
      return DiscoveryResult(
        runners: manual.runners + gitLab.runners,
        unreadable: manual.unreadable + gitLab.unreadable,
        failure: .launchAgentsUnreadable(launchAgentsDirectory))
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

    // A directory somebody added that is *also* installed as a service gets one
    // row, not two, and the serviced identity is the one that survives: it is
    // the only one that can be started and stopped from here.
    let serviced = Set(runners.map { $0.directory.standardizedFileURL.path })
    let extra = manual.runners.filter {
      !serviced.contains($0.directory.standardizedFileURL.path)
    }

    return DiscoveryResult(
      runners: deduplicatedByLabel(runners + extra + gitLab.runners),
      unreadable: (unreadable + manual.unreadable + gitLab.unreadable)
        .sorted { $0.path < $1.path },
      possiblyInstalledLabels: hasUnidentifiedCandidate ? nil : possiblyInstalledLabels)
  }

  /// The runners `config.toml` declares. A missing file is a Mac without
  /// gitlab-runner, which is most Macs; a file declaring runners this app
  /// cannot use is reported by name, because dropping a runner the file
  /// plainly declares is how half a fleet goes missing in silence.
  private func gitLabRunners() -> (runners: [DiscoveredRunner], unreadable: [URL]) {
    guard let text = try? String(contentsOf: gitLabConfigFile, encoding: .utf8) else {
      return ([], [])
    }
    guard let reading = try? GitLabRunnerConfigFile.reading(text) else {
      return ([], [gitLabConfigFile])
    }
    let home = gitLabConfigFile.deletingLastPathComponent()
    let runners = reading.entries.map { entry in
      DiscoveredRunner(
        // Instance and id, because nothing else tells two runners with the
        // same name on two instances apart. Prefixed like the manual labels,
        // so anybody who meets one in `defaults` can tell what it is.
        label: "standfast.gitlab:\(entry.instanceHost):\(entry.id)",
        directory: home,
        agentId: entry.id,
        agentName: entry.name,
        scope: .gitLab(instanceHost: entry.instanceHost),
        installation: .gitLabService)
    }
    return (runners, reading.skipped.isEmpty ? [] : [gitLabConfigFile])
  }

  /// The runners the operator pointed at, and the directories that did not
  /// turn out to hold one.
  ///
  /// A directory that is not a runner is reported rather than dropped:
  /// somebody chose the wrong folder, and showing nothing would leave them
  /// waiting for a row that is never coming.
  private func manualRunners() -> (runners: [DiscoveredRunner], unreadable: [URL]) {
    var runners: [DiscoveredRunner] = []
    var unreadable: [URL] = []
    for directory in manualDirectories {
      if let runner = Self.manualRunner(in: directory) {
        runners.append(runner)
      } else {
        unreadable.append(directory)
      }
    }
    return (runners, unreadable)
  }

  private static func manualRunner(in directory: URL) -> DiscoveredRunner? {
    let runnerFile = directory.appendingPathComponent(".runner")
    guard let config = try? RunnerConfig(contentsOf: runnerFile),
      let scope = RunnerScope(gitHubURL: config.gitHubUrl)
    else { return nil }

    let runner = DiscoveredRunner(
      label: DiscoveredRunner.manualLabel(for: directory),
      directory: directory,
      agentId: config.agentId,
      agentName: config.agentName,
      scope: scope,
      workFolder: config.workFolder,
      installation: .manual)
    return runner
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
    // Deliberately no containment check here (INV-006). A work folder
    // symlinked outside the runner — builds on an external SSD — is a
    // legitimate machine, and erasing its whole row treated it as having no
    // state, no jobs and no Stop button. Only housekeeping needs containment,
    // and `Housekeeper` and `DiskUsage` re-derive it themselves at the moment
    // it matters, failing closed. A `.runner` that *declares* an escaping
    // path is still rejected above, by `RunnerConfig` — that one is the
    // file's fault.
    return (runner, agent.label)
  }
}
