import Foundation
import RunnerKit

/// The page a runner's GitHub action opens, including the distinction the
/// button must say out loud.
enum GitHubDestination: Equatable {
  case workflowRuns(URL)
  case runnerSettings(URL)
  /// A GitLab instance's home page. `config.toml` does not say which project
  /// or group a runner belongs to, so this is as deep as an honest link goes,
  /// and the button must not promise the runner's settings.
  case instance(URL)

  var url: URL {
    switch self {
    case .workflowRuns(let url), .runnerSettings(let url), .instance(let url): url
    }
  }

  var label: String {
    switch self {
    case .workflowRuns: L10n.openWorkflowRuns
    case .runnerSettings: L10n.openRunnerSettings
    case .instance: L10n.openGitLab
    }
  }

  static func forScope(_ scope: RunnerScope) -> Self {
    if case .gitLab = scope { return .instance(scope.settingsURL) }
    if let runs = scope.workflowRunsURL { return .workflowRuns(runs) }
    return .runnerSettings(scope.settingsURL)
  }
}

/// What an empty Control Center means after discovery has answered.
///
/// The payload is semantic rather than view-shaped: a clean empty machine gets
/// installation guidance, while discovery failures retain the exact paths the
/// user can inspect. The view renders this value and makes no discovery choice.
enum ControlCenterEmptyPresentation: Equatable {
  case checking
  case noRunnersInstalled
  case launchAgentsUnavailable(directory: String)
  case unreadableRunners(paths: [String])

  static func building(overview: FleetOverviewPresentation) -> Self? {
    switch overview.state {
    case .checking:
      .checking
    case .noRunnersInstalled:
      .noRunnersInstalled
    case .unavailable:
      switch overview.recovery {
      case .launchAgentsUnavailable(let directory):
        .launchAgentsUnavailable(directory: directory)
      case .unreadableRunners(let paths):
        .unreadableRunners(paths: paths)
      case nil:
        .checking
      }
    case .fleet:
      nil
    }
  }

  /// Nil where the header directly above already carries this sentence.
  ///
  /// UI-031. An empty Control Center repeated "No hay runners instalados en
  /// esta Mac" twice — once in the header, once in the body 250 points below
  /// it, in a larger font — on the first screen anybody installing this app
  /// ever sees. The failure states keep their title: the header summarises the
  /// fleet, and "1 runner requiere atención" is not the same sentence as the
  /// directory that would not list.
  var title: String? {
    switch self {
    case .checking: L10n.checkingRunners
    case .noRunnersInstalled: nil
    case .launchAgentsUnavailable: L10n.launchAgentsUnreadableTitle
    case .unreadableRunners: L10n.someRunnersUnreadableTitle
    }
  }

  var detailLines: [String] {
    switch self {
    case .checking:
      []
    case .noRunnersInstalled:
      // The second line is the one that keeps somebody from concluding the app
      // cannot see their machine: a runner started with `./run.sh` leaves no
      // LaunchAgent, so discovery cannot find it and this screen is where they
      // find out Settings takes the folder.
      [L10n.controlCenterNoRunnersDescription, L10n.controlCenterNoRunnersManual]
    case .launchAgentsUnavailable(let directory):
      [directory]
    case .unreadableRunners(let paths):
      paths
    }
  }

  var symbolName: String {
    switch self {
    case .checking: "arrow.triangle.2.circlepath"
    case .noRunnersInstalled: FleetSummary.noRunnersSymbolName
    case .launchAgentsUnavailable, .unreadableRunners: "exclamationmark.triangle"
    }
  }

  /// Where somebody with no runner at all can find out how to get one.
  ///
  /// The other half of UI-039: the empty state told the user to go and install
  /// a self-hosted runner and left them to find the instructions themselves,
  /// which is the one screen where they have nothing else to go on.
  ///
  /// Only here. The failure states already name the exact paths to inspect,
  /// and a link to installation instructions over a directory that would not
  /// list is an answer to a question nobody asked.
  var guide: URL? {
    switch self {
    case .noRunnersInstalled: Self.installGuide
    case .checking, .launchAgentsUnavailable, .unreadableRunners: nil
    }
  }

  static let installGuide = URL(
    string: "https://docs.github.com/actions/hosting-your-own-runners"
      + "/managing-self-hosted-runners/adding-self-hosted-runners")!
}

/// What discovery could not read on a Mac that still has runners to show: a
/// notice on the Overview rather than the whole page. The fleet's recovery
/// itself, so its title and paths are the ones every other surface uses.
typealias ControlCenterNoticePresentation = FleetRecoveryPresentation

extension FleetRecoveryPresentation {
  /// Only beside runners. With none, the failure is the page, and the empty
  /// state says it.
  static func building(overview: FleetOverviewPresentation) -> Self? {
    guard case .fleet = overview.state else { return nil }
    return overview.recovery
  }
}

struct ControlCenterHeaderPresentation: Equatable {
  let summary: String
  let shortSummary: String
  let symbolName: String
  let tone: StateTone
  let attention: String?
  /// How many runners the state speaks for, and nil with none to count.
  let runnerCount: String?
  let freshness: String

  static func building(
    overview: FleetOverviewPresentation, readAt: Date?, now: Date,
    isScanning: Bool = false, lastAttemptFailed: Bool = false, runnerCount: Int = 0
  ) -> Self {
    return Self(
      summary: overview.summary,
      shortSummary: overview.shortSummary,
      symbolName: overview.symbolName,
      tone: overview.tone,
      attention: overview.attention,
      runnerCount: runnerCount == 0 ? nil : L10n.controlCenterRunnerCount(runnerCount),
      freshness: FleetStatus.lastCheckedLine(
        readAt: readAt, now: now, isScanning: isScanning,
        lastAttemptFailed: lastAttemptFailed))
  }

  /// The Overview row's state, and nil when the fleet is ready with nothing
  /// to warn of: then its symbol says it, as a calm runner's row leaves it.
  func sidebarState(warningCount: Int) -> String? {
    tone == .healthy && warningCount == 0 && attention == nil ? nil : shortSummary
  }
}

enum ActionEmphasis: Equatable, Sendable {
  case prominent, standard, none
}

struct RunnerCardAction: Equatable, Identifiable {
  let kind: RunnerRow.Action.Kind
  let label: String
  let accessibilityLabel: String
  let symbolName: String
  let isEnabled: Bool
  let emphasis: ActionEmphasis
  let requiresConfirmation: Bool

  var id: RunnerRow.Action.Kind { kind }
}

enum RunnerHistoryPresentation: Equatable {
  case available(rows: [JobRow], isTruncated: Bool)
  case unavailable(lastKnownRows: [JobRow])
}

/// One runner's complete, read-only Control Center projection.
///
/// The view receives no raw machine state. Service capabilities, operation
/// feedback, history, and maintenance decisions have already been made by the
/// existing presentation values this card composes.
struct RunnerCardPresentation: Equatable, Identifiable {
  let id: String
  /// What the sidebar, the window and the detail call it: the quick menu's
  /// identity, so four runners named after one Mac read apart.
  let title: String
  /// The name it was registered with, which Copy Name copies.
  let name: String
  /// The compact copy under the sidebar name; `state` keeps the full recovery
  /// detail.
  let compactState: String
  let state: String
  let stateSymbolName: String
  let scope: String
  let tone: StateTone
  /// The fleet job this slot is running, with its pull request and links, and
  /// nil for any other runner. A runner of its own reports its job in
  /// `progress`.
  let managedJob: ManagedFleetJobPresentation?
  /// The process here and the service that hands it work, read apart.
  let layers: RunnerLayersPresentation
  /// What is waiting for this runner, and nil when there is nothing worth
  /// saying. Sits with the state it explains: it is what that state is costing.
  let queued: QueuedWorkPresentation?
  /// Why this runner's service controls do nothing, and nil when they work.
  /// Greyed-out buttons with no explanation are the app knowing something and
  /// not saying it.
  let serviceNote: String?
  let operationFeedback: ServiceOperationPresentation?
  /// The receipt of an order that failed, while it lasts, and nil otherwise.
  /// Decided by `ServiceOperation.hasFailed`, the rule `needsAttention` reads,
  /// so the form's Last Action and the Overview's Needs Attention can never
  /// disagree about one runner.
  let failedReceipt: ServiceOperationPresentation?
  let history: RunnerHistoryPresentation
  let progress: String?
  let operation: ServiceOperationPresentation?
  let actions: [RunnerCardAction]
  let recentJobs: [RunnerRow.RecentJob]
  let maintenance: MaintenanceSection
  let githubDestination: GitHubDestination
  /// Which sidebar group this runner is listed under.
  let group: ControlCenterSidebar.Group
  /// What the header counts. See `RunnerSnapshot.needsAttention`.
  let needsAttention: Bool
  /// The running job against its usual time, and nil when nothing is running.
  let jobProgress: JobProgress?
  /// The folder Show logs in Finder reveals, and nil where there is no folder
  /// of this runner's own to show.
  let diagnosticsDirectory: URL?
}

extension RunnerCardPresentation {
  /// Where this runner goes in the Overview's lists: what somebody has to
  /// answer for first, a failed order included, then stopped, then working.
  /// Discovery order stays the sidebar's.
  var attentionRank: Int {
    if needsAttention { return 0 }
    return switch tone {
    case .attention: 0
    case .stopped: 1
    case .neutral: 2
    case .active: 3
    case .healthy: 4
    }
  }

  /// What VoiceOver hears after the runner's name wherever it is identified,
  /// in the sidebar and atop its detail: the state in brief, where it is
  /// registered, then the state in full.
  var identityAccessibilityValue: String {
    "\(compactState), \(scope). \(state)"
  }

  /// The order the sidebar row still answers for: one in flight, or one that
  /// failed while its receipt lasts. A context menu sends an order to the row
  /// clicked, which need not be the runner the detail shows, and then this row
  /// is the only place that order can answer.
  var sidebarReceipt: ServiceOperationPresentation? {
    if let operation, operation.isInFlight { return operation }
    return failedReceipt
  }

  /// Ready, online and waiting, with nothing in flight, failed or queued: the
  /// state its symbol and its two layer rows already say.
  private var isCalm: Bool {
    tone == .healthy && sidebarReceipt == nil && !needsAttention && queued == nil
  }

  /// The state under the sidebar name, and nil for a calm runner, so the rows
  /// that say something are the ones that have something to say.
  var sidebarState: String? { isCalm ? nil : compactState }

  /// The sentence under Status, remedy included, and nil for a calm runner,
  /// where it would restate the two rows above it.
  var statusSentence: String? { isCalm ? nil : state }

  /// The sidebar row's spoken value: the identity, then that order.
  var sidebarAccessibilityValue: String {
    guard let receipt = sidebarReceipt else { return identityAccessibilityValue }
    return "\(identityAccessibilityValue). \(receipt.title)"
  }

  /// The heat lines over this runner's detail, and nil unless its own job has
  /// overrun on a Mac that is being throttled. The lines come from the caller:
  /// the thermal monitor is an object, not part of this value.
  func overrunThermalLine(thermalLines: [String]) -> String? {
    guard jobProgress?.isOverTypical == true, !thermalLines.isEmpty else { return nil }
    return thermalLines.joined(separator: "\n")
  }
}

extension RunnerSnapshot {
  /// The open job this runner could still be working on. Stopped settles it
  /// only for a hand-started runner, where it means no listener is left; a
  /// LaunchAgent's stopped is launchd's word alone.
  var liveJob: JobRecord? {
    display == .resolved(.stopped) && runner.installation == .manual
      ? nil : jobs.running
  }

  /// The folder Show logs in Finder reveals: only one that is this runner's
  /// own. A GitLab runner keeps no `_diag`, and a fleet slot's logs are its
  /// supervisor's. The card offers it and the model reveals it by this one
  /// rule.
  var ownDiagnosticsDirectory: URL? {
    switch runner.installation {
    case .launchAgent, .manual: containedDiagnosticsDirectory
    case .gitLabService, .managedFleet: nil
    }
  }
}

extension RunnerCardPresentation {
  /// `title` is the runner's identity among the others, from
  /// `QuickMenuPresentation.identityNames`; alone, its name.
  static func building(
    _ snapshot: RunnerSnapshot, title: String? = nil, measurement: DiskMeasurement?,
    latestRelease: RunnerVersion?, isMaintenanceWorking: Bool,
    maintenanceNotice: String?, now: Date
  ) -> Self {
    let row = snapshot.row
    let destination = GitHubDestination.forScope(snapshot.runner.scope)
    let pastRecords = snapshot.jobs.records.filter { $0 != snapshot.liveJob }
    let visibleRecords = Array(pastRecords.prefix(RunnerRow.recentJobsShown))
    let historyRows = JobRow.building(visibleRecords, now: now)
    let isHistoryTruncated = pastRecords.count > RunnerRow.recentJobsShown
    let operation = snapshot.operation?.presentation
    return Self(
      id: snapshot.id,
      title: title ?? snapshot.runner.displayName,
      name: snapshot.runner.displayName,
      compactState: snapshot.display.shortSummary,
      state: snapshot.display.summary(for: snapshot.runner),
      stateSymbolName: snapshot.display.symbolName,
      // The qualifier, where there is one, is this scope plus whatever still
      // tells two runners in it apart: GitLab accepts one name twice on one
      // instance, and the title alone is the raw name.
      scope: snapshot.qualifier ?? snapshot.runner.scope.displayName,
      tone: snapshot.display.tone,
      managedJob: ManagedFleetJobPresentation.building(snapshot, now: now),
      layers: .building(
        display: snapshot.display, installation: snapshot.runner.installation,
        scope: snapshot.runner.scope),
      queued: QueuedWorkPresentation.building(
        snapshot.queued, runnerLabelled: snapshot.labels, display: snapshot.display),
      serviceNote: snapshot.serviceNote,
      operationFeedback: operation?.isInFlight == false ? operation : nil,
      failedReceipt: snapshot.operation?.hasFailed == true ? operation : nil,
      history: snapshot.isJobHistoryAvailable
        ? .available(rows: historyRows, isTruncated: isHistoryTruncated)
        : .unavailable(lastKnownRows: historyRows),
      progress: row.progress,
      operation: operation,
      actions: row.actions.map {
        cardAction(
          $0, runnerName: snapshot.name,
          display: snapshot.display, destination: destination)
      },
      recentJobs: row.recentJobs,
      maintenance: MaintenanceSection.building(
        snapshot, measurement: measurement, latest: latestRelease,
        isWorking: isMaintenanceWorking, notice: maintenanceNotice, now: now),
      githubDestination: destination,
      group: ControlCenterSidebar.Group(snapshot),
      needsAttention: snapshot.needsAttention,
      jobProgress: snapshot.jobProgress,
      diagnosticsDirectory: snapshot.ownDiagnosticsDirectory)
  }

  func action(_ kind: RunnerRow.Action.Kind) -> RunnerCardAction? {
    actions.first { $0.kind == kind }
  }

  /// Start, Stop and Restart in their fixed order, cut around the one this
  /// state puts forward, which the toolbar draws prominent in an item of its
  /// own. No button changes place. The destination is never among them: it
  /// is an item of its own whatever its emphasis.
  var serviceVerbs:
    (before: [RunnerCardAction], forward: RunnerCardAction?, after: [RunnerCardAction])
  {
    let verbs = actions.filter { $0.kind != .openOnGitHub }
    guard let cut = verbs.firstIndex(where: { $0.emphasis == .prominent }) else {
      return (verbs, nil, [])
    }
    return (Array(verbs[..<cut]), verbs[cut], Array(verbs[(cut + 1)...]))
  }

  private static func cardAction(
    _ action: RunnerRow.Action, runnerName: String, display: DisplayState,
    destination: GitHubDestination
  ) -> RunnerCardAction {
    let label: String
    let accessibilityLabel: String
    let symbolName: String
    switch action.kind {
    case .start:
      label = L10n.serviceStart
      accessibilityLabel = L10n.startRunner(runnerName)
      symbolName = "play.fill"
    case .stop:
      label = L10n.serviceStop
      accessibilityLabel = L10n.stopRunner(runnerName)
      symbolName = "stop.fill"
    case .restart:
      label = L10n.serviceRestart
      accessibilityLabel = L10n.restartRunner(runnerName)
      // Not `arrow.clockwise`, which is Refresh and changes nothing, nor the
      // states' `arrow.triangle.2.circlepath`. Not `restart` either: from
      // macOS 26 that symbol is a hollow ◁, which reads as Back.
      symbolName = "arrow.circlepath"
    case .openOnGitHub:
      label =
        switch destination {
        case .workflowRuns: L10n.viewRuns()
        case .runnerSettings: L10n.viewSettings()
        case .instance: L10n.openGitLab
        }
      accessibilityLabel = destination.label
      symbolName = "arrow.up.right.square"
    }

    let emphasis: ActionEmphasis
    if !action.isEnabled {
      emphasis = .none
    } else if action.kind == .start && display == .resolved(.stopped) {
      emphasis = .prominent
    } else if action.kind == .openOnGitHub && display.resolvedState == .busy {
      emphasis = .prominent
    } else {
      emphasis = .standard
    }

    let protectsWork: Bool =
      switch display {
      case .resolved(.idle), .resolved(.stopped): false
      default: true
      }
    let requiresConfirmation =
      action.isEnabled && protectsWork
      && (action.kind == .stop || action.kind == .restart)

    return RunnerCardAction(
      kind: action.kind, label: label, accessibilityLabel: accessibilityLabel,
      symbolName: symbolName, isEnabled: action.isEnabled, emphasis: emphasis,
      requiresConfirmation: requiresConfirmation)
  }
}

struct ControlCenterPresentation: Equatable {
  let header: ControlCenterHeaderPresentation
  let cards: [RunnerCardPresentation]
  let empty: ControlCenterEmptyPresentation?
  let notice: ControlCenterNoticePresentation?
}

extension ControlCenterPresentation {
  /// The sidebar's runners, in discovery order within each group.
  var sidebar: [ControlCenterSidebar.Section] {
    ControlCenterSidebar.grouping(cards: cards)
  }

  /// Every runner, as the Overview lists them: by `attentionRank`, then by
  /// name as Finder sorts it, then in discovery order.
  var runnersByAttention: [RunnerCardPresentation] {
    cards.enumerated().sorted { lhs, rhs in
      if lhs.element.attentionRank != rhs.element.attentionRank {
        return lhs.element.attentionRank < rhs.element.attentionRank
      }
      let byName = lhs.element.title.localizedStandardCompare(rhs.element.title)
      if byName != .orderedSame { return byName == .orderedAscending }
      return lhs.offset < rhs.offset
    }
    .map(\.element)
  }

  /// The runners the header's attention count is about, in the same order.
  var runnersNeedingAttention: [RunnerCardPresentation] {
    runnersByAttention.filter(\.needsAttention)
  }

  /// The badge on the sidebar's Overview row: one for each runner the header
  /// counts, one for discovery's notice and one for the Mac's heat, which are
  /// the rows the Overview raises above All Runners. Zero draws no badge. Only
  /// the Overview shows the header and those rows, so while a runner is
  /// selected this is what still says they are there.
  func overviewWarningCount(thermalLines: [String]) -> Int {
    cards.count(where: \.needsAttention) + (notice == nil ? 0 : 1)
      + (thermalLines.isEmpty ? 0 : 1)
  }

  /// What VoiceOver hears on the Overview's sidebar row: the fleet, then in
  /// words each thing the badge counts. A bare number says neither what nor
  /// where, and the fleet's summary names neither discovery nor heat.
  func overviewAccessibilityValue(thermalLines: [String]) -> String {
    ([header.summary, header.attention, notice?.title].compactMap { $0 } + thermalLines)
      .joined(separator: ". ")
  }
}

/// The Control Center's sidebar: one group per service that hands runners
/// their work.
enum ControlCenterSidebar {
  enum Group: CaseIterable, Equatable, Sendable {
    case gitHub, gitLab, managedFleet

    /// A fleet slot is listed with its supervisor, whichever service it
    /// registers with: what can be done to it is decided there.
    init(_ snapshot: RunnerSnapshot) {
      if snapshot.runner.installation == .managedFleet {
        self = .managedFleet
      } else if snapshot.isOnGitLab {
        self = .gitLab
      } else {
        self = .gitHub
      }
    }

    var title: String {
      switch self {
      case .gitHub: L10n.gitHub
      case .gitLab: L10n.gitLab
      case .managedFleet: L10n.managedFleet
      }
    }
  }

  struct Section: Equatable, Identifiable {
    let group: Group
    /// Nil while this is the only group: a header over every runner on the Mac
    /// would tell nobody anything.
    let title: String?
    let cards: [RunnerCardPresentation]

    var id: Group { group }
  }

  /// Groups in a fixed order, empty ones left out, and each runner where
  /// discovery put it. Never sorted by state: a row that moves when its runner
  /// changes state is a row somebody clicks by mistake.
  static func grouping(cards: [RunnerCardPresentation]) -> [Section] {
    let groups = Group.allCases.filter { group in cards.contains { $0.group == group } }
    return groups.map { group in
      Section(
        group: group, title: groups.count > 1 ? group.title : nil,
        cards: cards.filter { $0.group == group })
    }
  }
}

/// What the sidebar has selected: the whole fleet, or one runner by its
/// durable label.
enum ControlCenterSelection: Hashable, Sendable {
  case overview
  case runner(String)

  /// How scene storage spells the Overview. No runner label can collide with
  /// it: each one starts `actions.runner.` or `standfast.`.
  static let storedOverview = "overview"

  var stored: String {
    switch self {
    case .overview: Self.storedOverview
    case .runner(let id): id
    }
  }

  /// The stored choice while it still names something. Otherwise the only
  /// runner, since an Overview of one runner says the same thing twice, and
  /// otherwise the Overview, which is never stale.
  static func resolve(stored: String, cards: [RunnerCardPresentation]) -> Self {
    if stored == storedOverview { return .overview }
    if cards.contains(where: { $0.id == stored }) { return .runner(stored) }
    if cards.count == 1, let only = cards.first { return .runner(only.id) }
    return .overview
  }
}
