import AppKit
import Combine
import Dispatch
import OSLog

/// Activates only the exact scene window requested by the latest menu action.
///
/// SwiftUI's open actions return before their `NSWindow` is guaranteed to exist. The
/// coordinator polls a weak scene registry, retries the same open action once at its soft
/// timeout, then reports a hard timeout without falling back to another application window.
@MainActor
final class SceneActivationCoordinator: ObservableObject {
  typealias ScheduledPoll = @MainActor @Sendable () -> Void
  typealias OpenScene = @MainActor @Sendable () -> Void

  private enum PollingPhase {
    case beforeSoftTimeout
    case beforeHardTimeout
  }

  private final class ActivationRequest {
    let generation: UInt64
    let target: SceneTarget
    let openScene: OpenScene
    var isFinished = false

    init(generation: UInt64, target: SceneTarget, openScene: @escaping OpenScene) {
      self.generation = generation
      self.target = target
      self.openScene = openScene
    }
  }

  let windowRegistry: SceneWindowRegistry

  private let pollsUntilSoftTimeout: Int
  private let pollsUntilHardTimeout: Int
  private let activateApplication: () -> Void
  private let schedulePoll: (@escaping ScheduledPoll) -> Void
  private let reportSoftTimeout: (SceneTarget) -> Void
  private let reportHardTimeout: (SceneTarget) -> Void
  private var latestGeneration: UInt64 = 0

  init(
    windowRegistry: SceneWindowRegistry,
    pollsUntilSoftTimeout: Int,
    pollsUntilHardTimeout: Int,
    activateApplication: @escaping () -> Void,
    schedulePoll: @escaping (@escaping ScheduledPoll) -> Void,
    reportSoftTimeout: @escaping (SceneTarget) -> Void,
    reportHardTimeout: @escaping (SceneTarget) -> Void
  ) {
    precondition(pollsUntilSoftTimeout >= 0)
    precondition(pollsUntilHardTimeout >= 0)
    self.windowRegistry = windowRegistry
    self.pollsUntilSoftTimeout = pollsUntilSoftTimeout
    self.pollsUntilHardTimeout = pollsUntilHardTimeout
    self.activateApplication = activateApplication
    self.schedulePoll = schedulePoll
    self.reportSoftTimeout = reportSoftTimeout
    self.reportHardTimeout = reportHardTimeout
  }

  func openAndActivate(_ target: SceneTarget, openScene: @escaping OpenScene) {
    latestGeneration &+= 1
    let request = ActivationRequest(
      generation: latestGeneration,
      target: target,
      openScene: openScene)
    // Keep the activation request in the menu action. Only locating and fronting
    // the exact window may wait for SwiftUI's asynchronous scene creation.
    activateApplication()
    openScene()
    poll(
      request,
      phase: .beforeSoftTimeout,
      remainingPolls: pollsUntilSoftTimeout)
  }

  private func poll(
    _ request: ActivationRequest,
    phase: PollingPhase,
    remainingPolls: Int
  ) {
    guard request.generation == latestGeneration, !request.isFinished else { return }

    if let window = windowRegistry.window(for: request.target), window.canBecomeKey {
      request.isFinished = true
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
      return
    }

    if remainingPolls > 0 {
      schedulePoll { [weak self] in
        guard let self else { return }
        self.poll(
          request,
          phase: phase,
          remainingPolls: remainingPolls - 1)
      }
      return
    }

    switch phase {
    case .beforeSoftTimeout:
      reportSoftTimeout(request.target)
      request.openScene()
      poll(
        request,
        phase: .beforeHardTimeout,
        remainingPolls: pollsUntilHardTimeout)
    case .beforeHardTimeout:
      request.isFinished = true
      reportHardTimeout(request.target)
    }
  }
}

extension SceneActivationCoordinator {
  private static let logger = Logger(
    subsystem: "dev.standfast.app",
    category: "SceneActivation")

  static func live(windowRegistry: SceneWindowRegistry) -> SceneActivationCoordinator {
    return SceneActivationCoordinator(
      windowRegistry: windowRegistry,
      pollsUntilSoftTimeout: 10,
      pollsUntilHardTimeout: 40,
      activateApplication: {
        NSApplication.shared.activate()
      },
      schedulePoll: { poll in
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: poll)
      },
      reportSoftTimeout: { target in
        logger.warning(
          "Retrying scene activation after soft timeout: \(target.accessibilityIdentifier, privacy: .public)"
        )
      },
      reportHardTimeout: { target in
        logger.error(
          "Scene activation failed after hard timeout: \(target.accessibilityIdentifier, privacy: .public)"
        )
      })
  }
}
