import Foundation
import RunnerKit

/// The history row already decided by `RunnerRow`, named for the card-facing
/// interface without introducing a second history projection.
typealias JobRow = RunnerRow.RecentJob

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

/// One runner's complete, read-only Control Center projection.
///
/// The view receives no raw machine state. Service capabilities, operation
/// feedback, history, and maintenance decisions have already been made by the
/// existing presentation values this card composes.
struct RunnerCardPresentation: Equatable, Identifiable {
  let id: String
  let title: String
  let state: String
  let stateSymbolName: String
  let scope: String
  let progress: String?
  let operation: ServiceOperationPresentation?
  let actions: [RunnerRow.Action]
  let recentJobs: [JobRow]
  let maintenance: MaintenanceSection
  let githubDestination: GitHubDestination
}

extension RunnerCardPresentation {
  static func building(
    _ snapshot: RunnerSnapshot, measurement: DiskMeasurement?,
    latestRelease: RunnerVersion?, isMaintenanceWorking: Bool,
    maintenanceNotice: String?, now: Date
  ) -> Self {
    let row = snapshot.row
    let destination = GitHubDestination.forScope(snapshot.runner.scope)
    return Self(
      id: snapshot.id,
      title: snapshot.name,
      state: snapshot.display.summary,
      stateSymbolName: snapshot.display.symbolName,
      scope: snapshot.runner.scope.displayName,
      progress: row.progress,
      operation: row.operation,
      actions: row.actions.map { action in
        guard action.kind == .openOnGitHub else { return action }
        return RunnerRow.Action(
          kind: action.kind, label: destination.label, isEnabled: action.isEnabled)
      },
      recentJobs: row.recentJobs,
      maintenance: MaintenanceSection.building(
        snapshot, measurement: measurement, latest: latestRelease,
        isWorking: isMaintenanceWorking, notice: maintenanceNotice, now: now),
      githubDestination: destination)
  }
}
