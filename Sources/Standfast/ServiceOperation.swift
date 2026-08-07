import Foundation

/// A requested mutation of one runner service. A returned command is evidence
/// only that the request was accepted by `svc.sh`; a later scan is what reads
/// the runner's actual state.
enum ServiceOperationAction: Equatable, Sendable {
  case start, stop, restart

  var title: String {
    switch self {
    case .start: L10n.start
    case .stop: L10n.stop
    case .restart: L10n.restart
    }
  }
}

enum ServiceOperationCause: Equatable, Sendable {
  case commandTimedOut
  case scriptMissing
  case commandCouldNotLaunch
  case restartStartFailed
  case restartStartTimedOut
  case unexpectedFailure
}

enum ServiceOperationPhase: Equatable, Sendable {
  case inFlight
  case requestAccepted
  case uncertain(ServiceOperationCause)
  case failed(ServiceOperationCause)
}

struct ServiceOperation: Equatable, Sendable {
  let action: ServiceOperationAction
  let phase: ServiceOperationPhase
  let changedAt: Date
}

/// The outcome text is built from a value, not emitted by an action. This
/// keeps the row a projection of its snapshot and prevents rendering from
/// changing observable model state.
struct ServiceOperationPresentation: Equatable {
  let title: String
  let detail: String
  let symbolName: String
  let isInFlight: Bool
}

extension ServiceOperation {
  var presentation: ServiceOperationPresentation {
    let actionTitle = action.title
    return switch phase {
    case .inFlight:
      .init(
        title: L10n.serviceOperationInFlightTitle(actionTitle),
        detail: L10n.serviceOperationInFlightDetail(actionTitle),
        symbolName: "arrow.triangle.2.circlepath", isInFlight: true)
    case .requestAccepted:
      .init(
        title: L10n.serviceOperationAcceptedTitle(actionTitle),
        detail: L10n.serviceOperationAcceptedDetail(actionTitle),
        symbolName: "checkmark.circle", isInFlight: false)
    case .uncertain(.commandTimedOut):
      .init(
        title: L10n.serviceOperationTimedOutTitle(actionTitle),
        detail: L10n.serviceOperationTimedOutDetail(actionTitle),
        symbolName: "questionmark.circle", isInFlight: false)
    case .failed(.scriptMissing):
      .init(
        title: L10n.serviceOperationScriptMissingTitle(actionTitle),
        detail: L10n.serviceOperationScriptMissingDetail(actionTitle),
        symbolName: "exclamationmark.triangle", isInFlight: false)
    case .failed(.commandCouldNotLaunch):
      .init(
        title: L10n.serviceOperationCouldNotLaunchTitle(actionTitle),
        detail: L10n.serviceOperationCouldNotLaunchDetail(actionTitle),
        symbolName: "exclamationmark.triangle", isInFlight: false)
    case .failed(.unexpectedFailure):
      .init(
        title: L10n.serviceOperationUnexpectedFailureTitle(actionTitle),
        detail: L10n.serviceOperationUnexpectedFailureDetail(actionTitle),
        symbolName: "exclamationmark.triangle", isInFlight: false)
    case .failed(.restartStartFailed):
      .init(
        title: L10n.serviceOperationRestartStartFailedTitle,
        detail: L10n.serviceOperationRestartStartFailedDetail,
        symbolName: "exclamationmark.triangle", isInFlight: false)
    case .uncertain(.restartStartTimedOut):
      .init(
        title: L10n.serviceOperationRestartStartTimedOutTitle,
        detail: L10n.serviceOperationRestartStartTimedOutDetail,
        symbolName: "questionmark.circle", isInFlight: false)
    // Only Restart creates the two restart-start cases, and only the timeout
    // is uncertain. Keeping the impossible shapes honest if constructed by a
    // future caller is safer than silently claiming the runner changed state.
    case .uncertain:
      .init(
        title: L10n.serviceOperationTimedOutTitle(actionTitle),
        detail: L10n.serviceOperationTimedOutDetail(actionTitle),
        symbolName: "questionmark.circle", isInFlight: false)
    case .failed:
      .init(
        title: L10n.serviceOperationUnexpectedFailureTitle(actionTitle),
        detail: L10n.serviceOperationUnexpectedFailureDetail(actionTitle),
        symbolName: "exclamationmark.triangle", isInFlight: false)
    }
  }
}
