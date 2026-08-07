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
  func confirm(_ prompt: ServiceActionPrompt) async -> ServiceActionConfirmationResult
}

enum ServiceActionConfirmationResult: Equatable, Sendable {
  case accepted
  case cancelled
  case unavailable
}

@MainActor
protocol ServiceAlertPresentation: AnyObject {
  func dismiss()
}

@MainActor
protocol ServiceAlertPresenting: AnyObject {
  func present(
    _ prompt: ServiceActionPrompt,
    completion: @escaping @MainActor (Bool) -> Void
  ) -> (any ServiceAlertPresentation)?
}

struct ServiceAlertConfirmation: ServiceActionConfirming {
  typealias ParentWindowProvider = @MainActor () -> NSWindow?

  private let presenter: any ServiceAlertPresenting

  init(parentWindow: @escaping ParentWindowProvider) {
    presenter = NativeServiceAlertPresenter(parentWindow: parentWindow)
  }

  init(presenter: any ServiceAlertPresenting) {
    self.presenter = presenter
  }

  static func controlCenterParentWindow(
    in windowRegistry: SceneWindowRegistry
  ) -> ParentWindowProvider {
    { windowRegistry.window(for: .controlCenter) }
  }

  func confirm(_ prompt: ServiceActionPrompt) async -> ServiceActionConfirmationResult {
    guard !Task.isCancelled else { return .cancelled }
    let session = ServiceAlertAwaitingSession()
    return await withTaskCancellationHandler {
      await session.present(prompt, using: presenter)
    } onCancel: {
      Task { @MainActor in session.cancel() }
    }
  }
}

@MainActor
private final class ServiceAlertAwaitingSession {
  private var continuation: CheckedContinuation<ServiceActionConfirmationResult, Never>?
  private var presentation: (any ServiceAlertPresentation)?
  private var result: ServiceActionConfirmationResult?

  func present(
    _ prompt: ServiceActionPrompt, using presenter: any ServiceAlertPresenting
  ) async -> ServiceActionConfirmationResult {
    await withCheckedContinuation { continuation in
      if let result {
        continuation.resume(returning: result)
        return
      }
      self.continuation = continuation
      guard !Task.isCancelled else {
        complete(.cancelled, dismissing: true)
        return
      }
      guard
        let presentation = presenter.present(
          prompt,
          completion: { [weak self] accepted in
            self?.complete(accepted ? .accepted : .cancelled, dismissing: false)
          })
      else {
        complete(Task.isCancelled ? .cancelled : .unavailable, dismissing: false)
        return
      }
      // A presenter is allowed to complete synchronously. The native sheet
      // does not, but making this bridge robust to either ordering keeps a
      // test double or future AppKit adapter from leaving a returned session
      // alive after its continuation has already resumed.
      guard result == nil else {
        presentation.dismiss()
        return
      }
      self.presentation = presentation
      if Task.isCancelled { cancel() }
    }
  }

  func cancel() {
    complete(.cancelled, dismissing: true)
  }

  private func complete(
    _ result: ServiceActionConfirmationResult, dismissing: Bool
  ) {
    guard self.result == nil else { return }
    self.result = result
    let presentation = presentation
    self.presentation = nil
    let continuation = continuation
    self.continuation = nil
    if dismissing { presentation?.dismiss() }
    continuation?.resume(returning: result)
  }
}

@MainActor
private final class NativeServiceAlertPresentation: ServiceAlertPresentation {
  private let alert: NSAlert
  private var isFinished = false

  init(alert: NSAlert) {
    self.alert = alert
  }

  func didFinish() {
    isFinished = true
  }

  func dismiss() {
    guard !isFinished else { return }
    isFinished = true
    guard let parent = alert.window.sheetParent else { return }
    parent.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
  }
}

@MainActor
private final class NativeServiceAlertPresenter: ServiceAlertPresenting {
  private let parentWindow: ServiceAlertConfirmation.ParentWindowProvider

  init(
    parentWindow: @escaping ServiceAlertConfirmation.ParentWindowProvider
  ) {
    self.parentWindow = parentWindow
  }

  func present(
    _ prompt: ServiceActionPrompt,
    completion: @escaping @MainActor (Bool) -> Void
  ) -> (any ServiceAlertPresentation)? {
    guard let parent = parentWindow(), parent.isVisible, parent.canBecomeKey,
      parent.sheetParent == nil, parent.attachedSheet == nil
    else { return nil }

    // Standfast is an accessory app. Without activation, even a sheet can be
    // hidden behind the application the user was looking at, with no Dock icon
    // available to recover it.
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
    // Preserve the first (Cancel) button's default visual treatment while
    // preventing Return from invoking the window's default button cell.
    alert.window.disableKeyEquivalentForDefaultButtonCell()

    let presentation = NativeServiceAlertPresentation(alert: alert)
    alert.beginSheetModal(for: parent) { [weak presentation] response in
      presentation?.didFinish()
      completion(response == .alertSecondButtonReturn)
    }
    return presentation
  }
}

enum ServiceConfirmationKeys {
  static let cancel = "\u{1B}"
  static let confirm = ""
}
