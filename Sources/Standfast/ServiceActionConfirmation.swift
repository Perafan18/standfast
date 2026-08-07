import AppKit
import Foundation
import RunnerKit

struct ServiceActionPrompt: Equatable, Sendable {
  let action: ServiceOperationAction
  let runnerID: String
  let display: DisplayState
  let runningJob: JobRecord?
  let title: String
  let message: String
  let confirm: String
  let cancel: String
  private let runnerName: String
  private let scope: RunnerScope

  init?(
    action: ServiceOperationAction, snapshot: RunnerSnapshot,
    bundles: [Bundle]? = nil
  ) {
    guard action == .stop || action == .restart else { return nil }
    switch snapshot.display {
    case .resolved(.idle), .resolved(.stopped): return nil
    default: break
    }

    let runnerName = snapshot.runner.displayName
    let scope = snapshot.runner.scope
    let scopeName = scope.displayName
    let runningJob = snapshot.jobs.running
    let title: String
    let message: String
    let confirm: String
    switch action {
    case .stop:
      title = L10n.serviceConfirmStopTitle(runnerName, in: bundles)
      if snapshot.display == .resolved(.busy), let runningJob {
        message = L10n.serviceConfirmStopBusy(
          runnerName, scopeName, runningJob.name, in: bundles)
      } else {
        message = L10n.serviceConfirmStopUncertain(
          runnerName, scopeName, in: bundles)
      }
      confirm = L10n.t("menu.stop", in: bundles)
    case .restart:
      title = L10n.serviceConfirmRestartTitle(runnerName, in: bundles)
      if snapshot.display == .resolved(.busy), let runningJob {
        message = L10n.serviceConfirmRestartBusy(
          runnerName, scopeName, runningJob.name, in: bundles)
      } else {
        message = L10n.serviceConfirmRestartUncertain(
          runnerName, scopeName, in: bundles)
      }
      confirm = L10n.t("menu.restart", in: bundles)
    case .start:
      return nil
    }

    self.action = action
    runnerID = snapshot.runner.label
    display = snapshot.display
    self.runningJob = runningJob
    self.title = title
    self.message = message
    self.confirm = confirm
    cancel = L10n.serviceConfirmCancel(in: bundles)
    self.runnerName = runnerName
    self.scope = scope
  }

  func stillMatches(_ snapshot: RunnerSnapshot) -> Bool {
    snapshot.runner.label == runnerID
      && snapshot.runner.displayName == runnerName
      && snapshot.runner.scope == scope
      && snapshot.display == display
      && snapshot.jobs.running?.name == runningJob?.name
      && snapshot.jobs.running?.startedAt == runningJob?.startedAt
  }
}

@MainActor
protocol ServiceActionConfirming {
  func confirm(_ prompt: ServiceActionPrompt) async -> Bool
}

struct ServiceAlertConfirmation: ServiceActionConfirming {
  func confirm(_ prompt: ServiceActionPrompt) async -> Bool {
    // Standfast is an accessory app. Without activation, a modal alert can
    // appear behind the current app with no Dock icon available to recover it.
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = prompt.title
    alert.informativeText = prompt.message

    // NSAlert draws its first button as the default action on the right. Cancel
    // belongs there because the safe answer must also be the visually obvious
    // one. Replacing its implicit Return equivalent with Escape leaves Return
    // unbound; confirmation always requires an explicit click.
    alert.addButton(withTitle: prompt.cancel)
    alert.addButton(withTitle: prompt.confirm)
    alert.buttons.first?.keyEquivalent = ServiceConfirmationKeys.cancel
    alert.buttons.last?.keyEquivalent = ServiceConfirmationKeys.confirm
    return alert.runModal() == .alertSecondButtonReturn
  }
}

enum ServiceConfirmationKeys {
  static let cancel = "\u{1B}"
  static let confirm = ""
}
