import AppKit
import Dispatch

/// Activates the agent app only after SwiftUI has materialised a real window.
///
/// `openWindow` and `openSettings` return before their scene is guaranteed to
/// exist. A queue hop narrows that race but does not close it; the observable
/// condition is a visible application window that can become main.
@MainActor
struct SceneActivationCoordinator {
  typealias ScheduledPoll = @MainActor @Sendable () -> Void

  private let maximumPollAttempts: Int
  private let hasVisibleMainWindow: () -> Bool
  private let activate: () -> Void
  private let scheduleNextPoll: (@escaping ScheduledPoll) -> Void

  init(
    maximumPollAttempts: Int,
    hasVisibleMainWindow: @escaping () -> Bool,
    activate: @escaping () -> Void,
    scheduleNextPoll: @escaping (@escaping ScheduledPoll) -> Void
  ) {
    self.maximumPollAttempts = maximumPollAttempts
    self.hasVisibleMainWindow = hasVisibleMainWindow
    self.activate = activate
    self.scheduleNextPoll = scheduleNextPoll
  }

  func activateWhenWindowIsVisible() {
    poll(remainingAttempts: maximumPollAttempts)
  }

  private func poll(remainingAttempts: Int) {
    if hasVisibleMainWindow() {
      activate()
      return
    }
    guard remainingAttempts > 0 else { return }
    scheduleNextPoll {
      poll(remainingAttempts: remainingAttempts - 1)
    }
  }
}

extension SceneActivationCoordinator {
  static func live(
    hasVisibleMainWindow: @escaping () -> Bool = {
      NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeMain }
    },
    activate: @escaping () -> Void = {
      NSApplication.shared.activate()
    }
  ) -> SceneActivationCoordinator {
    SceneActivationCoordinator(
      maximumPollAttempts: 50,
      hasVisibleMainWindow: hasVisibleMainWindow,
      activate: activate,
      scheduleNextPoll: { poll in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: poll)
      })
  }
}
