import Foundation
import RunnerKit

/// The page a runner's GitHub action opens, including the distinction the
/// button must say out loud.
enum GitHubDestination: Equatable {
  case workflowRuns(URL)
  case runnerSettings(URL)

  var url: URL {
    switch self {
    case .workflowRuns(let url), .runnerSettings(let url): url
    }
  }

  var label: String {
    switch self {
    case .workflowRuns: L10n.openWorkflowRuns
    case .runnerSettings: L10n.openRunnerSettings
    }
  }

  static func forScope(_ scope: RunnerScope) -> Self {
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
    case .launchAgentsUnavailable: L10n.launchAgentsUnreadable
    case .unreadableRunners: L10n.someRunnersUnreadable
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

enum ControlCenterNoticePresentation: Equatable {
  case launchAgentsUnavailable(directory: String)
  case unreadableRunners(paths: [String])

  static func building(overview: FleetOverviewPresentation) -> Self? {
    guard case .fleet = overview.state else { return nil }
    return switch overview.recovery {
    case .launchAgentsUnavailable(let directory):
      .launchAgentsUnavailable(directory: directory)
    case .unreadableRunners(let paths):
      .unreadableRunners(paths: paths)
    case nil:
      nil
    }
  }
}

struct ControlCenterHeaderPresentation: Equatable {
  let summary: String
  let shortSummary: String
  let symbolName: String
  let tone: StateTone
  let attention: String?
  let freshness: String

  static func building(
    overview: FleetOverviewPresentation, readAt: Date?, now: Date,
    isScanning: Bool = false, lastAttemptFailed: Bool = false
  ) -> Self {
    return Self(
      summary: overview.summary,
      shortSummary: overview.shortSummary,
      symbolName: overview.symbolName,
      tone: overview.tone,
      attention: overview.attention,
      freshness: FleetStatus.lastCheckedLine(
        readAt: readAt, now: now, isScanning: isScanning,
        lastAttemptFailed: lastAttemptFailed))
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

enum RunnerFocusPresentation: Equatable {
  case operation(ServiceOperationPresentation)
  case currentJob(String)
  case lastJob(JobRow)
  case state(String)
}

/// One runner's complete, read-only Control Center projection.
///
/// The view receives no raw machine state. Service capabilities, operation
/// feedback, history, and maintenance decisions have already been made by the
/// existing presentation values this card composes.
struct RunnerCardPresentation: Equatable, Identifiable {
  let id: String
  let title: String
  /// The compact badge copy; `state` keeps the full recovery detail.
  let compactState: String
  let state: String
  let stateSymbolName: String
  let scope: String
  let tone: StateTone
  let focus: RunnerFocusPresentation
  /// What is waiting for this runner, and nil when there is nothing worth
  /// saying. Sits with identity and state rather than behind the fold: it is
  /// the reason somebody would open the card, not something found inside it.
  let queued: QueuedWorkPresentation?
  /// Why this runner's service controls do nothing, and nil when they work.
  /// Greyed-out buttons with no explanation are the app knowing something and
  /// not saying it.
  let serviceNote: String?
  let operationFeedback: ServiceOperationPresentation?
  let history: RunnerHistoryPresentation
  let progress: String?
  let operation: ServiceOperationPresentation?
  let actions: [RunnerCardAction]
  let recentJobs: [RunnerRow.RecentJob]
  let maintenance: MaintenanceSection
  let githubDestination: GitHubDestination
  /// Whether this card opens folded on a fleet the operator has not touched.
  ///
  /// A column of complete cards is the right shape for the two or three runners
  /// one Mac usually hosts and the wrong shape for ten, where the operator
  /// scrolls past nine healthy runners to reach the one that broke. The product
  /// decides this rather than the reader: a runner with nothing to answer for
  /// folds itself away once the fleet is large enough for that to matter, and a
  /// runner that needs a person never does.
  let startsCollapsed: Bool
}

extension RunnerCardPresentation {
  /// Below this, folding hides a control the operator can already see and
  /// solves a scrolling problem that does not exist yet.
  static let compactFleetThreshold = 3

  static func startsCollapsed(tone: StateTone, fleetSize: Int) -> Bool {
    guard fleetSize > compactFleetThreshold else { return false }
    switch tone {
    // Idle and busy are the two states with nothing to decide. Everything else
    // — disconnected, stopped, or a reading that failed — is the reason the
    // window was opened, so it stays open.
    case .healthy, .active: return true
    case .attention, .stopped, .neutral: return false
    }
  }
}

extension RunnerCardPresentation {
  static func building(
    _ snapshot: RunnerSnapshot, measurement: DiskMeasurement?,
    latestRelease: RunnerVersion?, isMaintenanceWorking: Bool,
    maintenanceNotice: String?, now: Date, fleetSize: Int
  ) -> Self {
    let row = snapshot.row
    let destination = GitHubDestination.forScope(snapshot.runner.scope)
    let pastRecords = snapshot.jobs.records.filter { $0 != snapshot.jobs.running }
    let visibleRecords = Array(pastRecords.prefix(RunnerRow.recentJobsShown))
    let historyRows = JobRow.building(visibleRecords, now: now)
    let isHistoryTruncated = pastRecords.count > RunnerRow.recentJobsShown
    let operation = snapshot.operation?.presentation
    let focus: RunnerFocusPresentation
    if let operation, operation.isInFlight {
      focus = .operation(operation)
    } else if let progress = row.progress {
      focus = .currentJob(progress)
    } else if let lastJob = historyRows.first {
      focus = .lastJob(lastJob)
    } else {
      focus = .state(snapshot.display.summary)
    }
    return Self(
      id: snapshot.id,
      title: snapshot.runner.displayName,
      compactState: snapshot.display.shortSummary,
      state: snapshot.display.summary,
      stateSymbolName: snapshot.display.symbolName,
      scope: snapshot.runner.scope.displayName,
      tone: snapshot.display.tone,
      focus: focus,
      queued: QueuedWorkPresentation.building(
        snapshot.queued, runnerLabelled: snapshot.labels, display: snapshot.display),
      serviceNote: snapshot.serviceNote,
      operationFeedback: operation?.isInFlight == false ? operation : nil,
      history: snapshot.isJobHistoryAvailable
        ? .available(rows: historyRows, isTruncated: isHistoryTruncated)
        : .unavailable(lastKnownRows: historyRows),
      progress: row.progress,
      operation: operation,
      actions: row.actions.map {
        cardAction(
          $0, runnerName: snapshot.runner.displayName,
          display: snapshot.display, destination: destination)
      },
      recentJobs: row.recentJobs,
      maintenance: MaintenanceSection.building(
        snapshot, measurement: measurement, latest: latestRelease,
        isWorking: isMaintenanceWorking, notice: maintenanceNotice, now: now),
      githubDestination: destination,
      startsCollapsed: startsCollapsed(tone: snapshot.display.tone, fleetSize: fleetSize))
  }

  func action(_ kind: RunnerRow.Action.Kind) -> RunnerCardAction? {
    actions.first { $0.kind == kind }
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
      // Not `arrow.clockwise`: that is `Actualizar ahora`, which re-reads the
      // machine and changes nothing. This one stops and starts a LaunchAgent,
      // and the two sat on the same card wearing the same circular arrow.
      symbolName = "restart"
    case .openOnGitHub:
      label =
        switch destination {
        case .workflowRuns: L10n.viewRuns()
        case .runnerSettings: L10n.viewSettings()
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
