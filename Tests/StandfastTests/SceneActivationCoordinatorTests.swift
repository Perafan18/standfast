import AppKit
import Testing

@testable import Standfast

@MainActor
@Suite(.serialized)
struct SceneActivationCoordinatorTests {

  @MainActor
  @Test func sceneWindowRegistryAssignsStableAXIdentifier() {
    let registry = SceneWindowRegistry()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)

    registry.register(window, for: .controlCenter)

    #expect(
      window.accessibilityIdentifier() == SceneTarget.controlCenter.accessibilityIdentifier)
  }

  @MainActor
  @Test func sceneWindowRegistryResolvesOnlyTheExactTarget() {
    let registry = SceneWindowRegistry()
    let controlCenter = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
    let settings = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
    controlCenter.title = "Same localized title"
    settings.title = "Same localized title"

    registry.register(controlCenter, for: .controlCenter)
    registry.register(settings, for: .settings)

    #expect(registry.window(for: .controlCenter) === controlCenter)
    #expect(registry.window(for: .settings) === settings)
  }

  @MainActor
  @Test func sceneWindowRegistryDoesNotUnregisterAReplacementWindow() {
    let registry = SceneWindowRegistry()
    let oldWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
    let replacement = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
    registry.register(oldWindow, for: .settings)
    registry.register(replacement, for: .settings)

    registry.unregister(oldWindow, for: .settings)

    #expect(registry.window(for: .settings) === replacement)

    registry.unregister(replacement, for: .settings)
    #expect(registry.window(for: .settings) == nil)
  }

  @MainActor
  @Test func sceneWindowRegistrationViewTracksAttachmentDetachmentAndReparenting() {
    let registry = SceneWindowRegistry()
    let firstWindow = Self.makeWindow()
    let secondWindow = Self.makeWindow()
    let registrationView = SceneWindowRegistrationView(frame: .zero)
    registrationView.update(target: .controlCenter, registry: registry)
    guard let firstContentView = firstWindow.contentView,
      let secondContentView = secondWindow.contentView
    else {
      Issue.record("Test windows have no content views")
      return
    }

    #expect(registry.window(for: .controlCenter) == nil)

    firstContentView.addSubview(registrationView)
    #expect(registry.window(for: .controlCenter) === firstWindow)

    registrationView.removeFromSuperview()
    #expect(registry.window(for: .controlCenter) == nil)

    secondContentView.addSubview(registrationView)
    #expect(registry.window(for: .controlCenter) === secondWindow)

    registrationView.removeFromSuperview()
    #expect(registry.window(for: .controlCenter) == nil)
  }

  @MainActor
  @Test func detachingOlderSceneWindowViewDoesNotUnregisterItsReplacement() {
    let registry = SceneWindowRegistry()
    let oldWindow = Self.makeWindow()
    let replacementWindow = Self.makeWindow()
    let oldView = SceneWindowRegistrationView(frame: .zero)
    let replacementView = SceneWindowRegistrationView(frame: .zero)
    oldView.update(target: .settings, registry: registry)
    replacementView.update(target: .settings, registry: registry)
    guard let oldContentView = oldWindow.contentView,
      let replacementContentView = replacementWindow.contentView
    else {
      Issue.record("Test windows have no content views")
      return
    }

    oldContentView.addSubview(oldView)
    #expect(registry.window(for: .settings) === oldWindow)

    replacementContentView.addSubview(replacementView)
    #expect(registry.window(for: .settings) === replacementWindow)

    oldView.removeFromSuperview()
    #expect(registry.window(for: .settings) === replacementWindow)

    replacementView.removeFromSuperview()
    #expect(registry.window(for: .settings) == nil)
  }

  @MainActor
  @Test func liveSceneActivationSchedulesAnotherExactWindowObservation() async throws {
    let registry = SceneWindowRegistry()
    let coordinator = SceneActivationCoordinator.live(windowRegistry: registry)
    #expect(coordinator.windowRegistry === registry)
    let window = RecordingSceneWindow()
    var eventContinuation: AsyncStream<String>.Continuation?
    let events = AsyncStream<String> { eventContinuation = $0 }
    window.recordEvent = { eventContinuation?.yield($0) }
    defer {
      eventContinuation?.finish()
      window.close()
    }

    coordinator.openAndActivate(.controlCenter, openScene: {})
    coordinator.windowRegistry.register(window, for: .controlCenter)

    let event = try await Self.firstEvent(in: events, timeout: .seconds(1))
    #expect(event == "makeKeyAndOrderFront")
  }

  @MainActor
  @Test func serviceConfirmationParentIsControlCenterEvenWhenSettingsIsKeyAndMain() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    let settings = RecordingSceneWindow()
    defer {
      controlCenter.close()
      settings.close()
    }
    registry.register(controlCenter, for: .controlCenter)
    registry.register(settings, for: .settings)
    controlCenter.orderFront(nil)
    settings.reportsKey = true
    settings.reportsMain = true
    let parent = ServiceAlertConfirmation.controlCenterParentWindow(in: registry)

    #expect(settings.isKeyWindow)
    #expect(settings.isMainWindow)
    #expect(parent() === controlCenter)
  }

  @MainActor
  @Test func serviceConfirmationParentNeverFallsBackFromMissingOrInvalidControlCenter() {
    let registry = SceneWindowRegistry()
    let settings = RecordingSceneWindow()
    defer { settings.close() }
    registry.register(settings, for: .settings)
    settings.reportsKey = true
    settings.reportsMain = true
    let parent = ServiceAlertConfirmation.controlCenterParentWindow(in: registry)

    #expect(parent() == nil)

    let invalidControlCenter = RecordingSceneWindow()
    defer { invalidControlCenter.close() }
    registry.register(invalidControlCenter, for: .controlCenter)
    invalidControlCenter.setAccessibilityIdentifier("wrong-scene")

    #expect(parent() == nil)
  }

  @Test func appWiresOneRegistryIntoActivationAndServiceConfirmation() {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let appURL = repository.appendingPathComponent("Sources/Standfast/App.swift")
    let confirmationURL = repository.appendingPathComponent(
      "Sources/Standfast/ServiceActionConfirmation.swift")
    let app = (try? String(contentsOf: appURL, encoding: .utf8)) ?? ""
    let confirmation =
      (try? String(contentsOf: confirmationURL, encoding: .utf8)) ?? ""

    #expect(app.components(separatedBy: "SceneWindowRegistry()").count == 2)
    #expect(
      app.contains(
        "SceneActivationCoordinator.live(windowRegistry: windowRegistry)"))
    #expect(
      app.contains(
        "ServiceAlertConfirmation.controlCenterParentWindow(in: windowRegistry)"))
    #expect(
      confirmation.contains("windowRegistry.window(for: .controlCenter)"))
    #expect(!confirmation.contains(".keyWindow"))
    #expect(!confirmation.contains(".mainWindow"))
    #expect(!confirmation.contains("runModal"))
    #expect(confirmation.contains("beginSheetModal"))
  }

  @MainActor
  @Test func sceneActivationIgnoresAWindowFromAnotherScene() {
    let registry = SceneWindowRegistry()
    let settings = RecordingSceneWindow()
    settings.title = L10n.controlCenterTitle
    registry.register(settings, for: .settings)
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 2,
      pollsUntilHardTimeout: 2,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.controlCenter, openScene: {})

    #expect(activationCount == 1)
    #expect(settings.makeKeyAndOrderFrontCount == 0)
    #expect(scheduled.count == 1)
  }

  @MainActor
  @Test func sceneActivationMakesTheExactHiddenWindowKeyAndFront() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    defer { controlCenter.close() }
    registry.register(controlCenter, for: .controlCenter)
    #expect(controlCenter.isVisible == false)
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 2,
      pollsUntilHardTimeout: 2,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.controlCenter, openScene: {})

    #expect(activationCount == 1)
    #expect(controlCenter.makeKeyAndOrderFrontCount == 1)
    #expect(controlCenter.isVisible)
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationSoftTimeoutReopensTheSameTargetExactlyOnce() {
    let registry = SceneWindowRegistry()
    var openedTargets: [SceneTarget] = []
    var softTimeouts: [SceneTarget] = []
    var hardTimeouts: [SceneTarget] = []
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { softTimeouts.append($0) },
      reportHardTimeout: { hardTimeouts.append($0) })

    coordinator.openAndActivate(.settings) {
      openedTargets.append(.settings)
    }
    guard scheduled.count == 1 else {
      Issue.record("Initial missing target did not schedule its soft-timeout poll")
      return
    }
    scheduled.removeFirst()()

    #expect(openedTargets == [.settings, .settings])
    #expect(softTimeouts == [.settings])
    #expect(hardTimeouts.isEmpty)
    guard scheduled.count == 1 else {
      Issue.record("Retry did not schedule its hard-timeout poll")
      return
    }
    scheduled.removeFirst()()

    #expect(openedTargets == [.settings, .settings])
    #expect(softTimeouts == [.settings])
    #expect(hardTimeouts == [.settings])
    #expect(activationCount == 1)
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationHardTimeoutReportsOnceAndFailsClosed() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    registry.register(controlCenter, for: .controlCenter)
    var openedTargets: [SceneTarget] = []
    var softTimeouts: [SceneTarget] = []
    var hardTimeouts: [SceneTarget] = []
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 0,
      pollsUntilHardTimeout: 1,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { softTimeouts.append($0) },
      reportHardTimeout: { hardTimeouts.append($0) })

    coordinator.openAndActivate(.settings) {
      openedTargets.append(.settings)
    }
    guard let hardTimeoutPoll = scheduled.first else {
      Issue.record("Missing hard-timeout poll")
      return
    }
    scheduled.removeAll()

    hardTimeoutPoll()
    hardTimeoutPoll()

    #expect(openedTargets == [.settings, .settings])
    #expect(softTimeouts == [.settings])
    #expect(hardTimeouts == [.settings])
    #expect(activationCount == 1)
    #expect(controlCenter.makeKeyAndOrderFrontCount == 0)
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationLatestRequestSupersedesAnotherTarget() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    let settings = RecordingSceneWindow()
    defer {
      controlCenter.close()
      settings.close()
    }
    var openedTargets: [SceneTarget] = []
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.controlCenter) {
      openedTargets.append(.controlCenter)
    }
    guard let supersededPoll = scheduled.first else {
      Issue.record("Missing Control Center poll")
      return
    }
    scheduled.removeAll()

    coordinator.openAndActivate(.settings) {
      openedTargets.append(.settings)
    }
    guard let latestPoll = scheduled.first else {
      Issue.record("Missing Settings poll")
      return
    }
    scheduled.removeAll()

    registry.register(controlCenter, for: .controlCenter)
    supersededPoll()

    #expect(activationCount == 2)
    #expect(controlCenter.makeKeyAndOrderFrontCount == 0)

    registry.register(settings, for: .settings)
    latestPoll()

    #expect(openedTargets == [.controlCenter, .settings])
    #expect(activationCount == 2)
    #expect(settings.makeKeyAndOrderFrontCount == 1)
    #expect(controlCenter.makeKeyAndOrderFrontCount == 0)
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationIgnoresOldCallbacksForTheSameTarget() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    defer { controlCenter.close() }
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.controlCenter, openScene: {})
    guard let oldPoll = scheduled.first else {
      Issue.record("Missing first-generation poll")
      return
    }
    scheduled.removeAll()

    coordinator.openAndActivate(.controlCenter, openScene: {})
    guard let latestPoll = scheduled.first else {
      Issue.record("Missing latest-generation poll")
      return
    }
    scheduled.removeAll()
    registry.register(controlCenter, for: .controlCenter)

    latestPoll()
    oldPoll()

    #expect(activationCount == 2)
    #expect(controlCenter.makeKeyAndOrderFrontCount == 1)
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationRequestsActivationBeforeOpeningAnExistingWindow() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    defer { controlCenter.close() }
    registry.register(controlCenter, for: .controlCenter)
    var events: [String] = []
    controlCenter.recordEvent = { events.append($0) }
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { events.append("activate") },
      schedulePoll: { _ in },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.controlCenter) { events.append("open") }

    #expect(events == ["activate", "open", "makeKeyAndOrderFront"])
  }

  @MainActor
  @Test(arguments: [SceneTarget.controlCenter, .settings])
  func sceneActivationRequestsActivationBeforeWaitingForWindowCreation(target: SceneTarget)
  {
    let registry = SceneWindowRegistry()
    let window = RecordingSceneWindow()
    defer { window.close() }
    var events: [String] = []
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    window.recordEvent = { events.append($0) }
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 2,
      pollsUntilHardTimeout: 2,
      activateApplication: { events.append("activate") },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(target) { events.append("open") }

    // This assertion runs before any poll: eventual activation cannot satisfy it.
    #expect(events == ["activate", "open"])
    guard scheduled.count == 1 else {
      Issue.record("Missing window did not schedule an observation")
      return
    }
    let poll = scheduled.removeFirst()
    registry.register(window, for: target)
    poll()
    poll()

    #expect(events == ["activate", "open", "makeKeyAndOrderFront"])
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationWaitsUntilTheExactWindowCanBecomeKey() {
    let registry = SceneWindowRegistry()
    let controlCenter = RecordingSceneWindow()
    controlCenter.allowsKey = false
    registry.register(controlCenter, for: .controlCenter)
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.controlCenter, openScene: {})

    #expect(activationCount == 1)
    #expect(controlCenter.makeKeyAndOrderFrontCount == 0)
    #expect(scheduled.count == 1)
  }

  @MainActor
  @Test func aScheduledPollDoesNotRetainTheCoordinator() {
    let registry = SceneWindowRegistry()
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    var coordinator: SceneActivationCoordinator? = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: {},
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })
    weak var weakCoordinator: SceneActivationCoordinator?
    weakCoordinator = coordinator

    coordinator?.openAndActivate(.controlCenter, openScene: {})
    #expect(scheduled.count == 1)
    coordinator = nil

    #expect(weakCoordinator == nil)
    scheduled.removeFirst()()
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationDoesNotRequireTheExactWindowToBecomeMain() {
    let registry = SceneWindowRegistry()
    let settings = RecordingSceneWindow()
    settings.allowsMain = false
    registry.register(settings, for: .settings)
    var activationCount = 0
    var scheduled: [SceneActivationCoordinator.ScheduledPoll] = []
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { activationCount += 1 },
      schedulePoll: { scheduled.append($0) },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.settings, openScene: {})

    #expect(activationCount == 1)
    #expect(settings.makeKeyAndOrderFrontCount == 1)
    #expect(scheduled.isEmpty)
  }

  @MainActor
  @Test func sceneActivationDeminiaturizesBeforeFrontingAfterRequestingActivation() {
    let registry = SceneWindowRegistry()
    let settings = RecordingSceneWindow()
    settings.reportsMiniaturized = true
    registry.register(settings, for: .settings)
    var events: [String] = []
    settings.recordEvent = { events.append($0) }
    let coordinator = SceneActivationCoordinator(
      windowRegistry: registry,
      pollsUntilSoftTimeout: 1,
      pollsUntilHardTimeout: 1,
      activateApplication: { events.append("activate") },
      schedulePoll: { _ in },
      reportSoftTimeout: { _ in },
      reportHardTimeout: { _ in })

    coordinator.openAndActivate(.settings, openScene: {})

    #expect(events == ["activate", "deminiaturize", "makeKeyAndOrderFront"])
  }

  @MainActor
  private final class RecordingSceneWindow: NSWindow {
    private(set) var makeKeyAndOrderFrontCount = 0
    var recordEvent: ((String) -> Void)?
    var allowsKey = true
    var allowsMain = true
    var reportsMiniaturized = false
    var reportsKey = false
    var reportsMain = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsMain }
    override var isMiniaturized: Bool { reportsMiniaturized }
    override var isKeyWindow: Bool { reportsKey || super.isKeyWindow }
    override var isMainWindow: Bool { reportsMain || super.isMainWindow }

    convenience init() {
      self.init(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled],
        backing: .buffered,
        defer: false)
      isReleasedWhenClosed = false
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
      makeKeyAndOrderFrontCount += 1
      recordEvent?("makeKeyAndOrderFront")
      super.makeKeyAndOrderFront(sender)
    }

    override func deminiaturize(_ sender: Any?) {
      recordEvent?("deminiaturize")
      reportsMiniaturized = false
    }
  }

  @MainActor
  private static func makeWindow() -> NSWindow {
    NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
  }

  private enum EventWaitError: Error {
    case streamEnded
    case timedOut
  }

  private static func firstEvent(
    in events: AsyncStream<String>, timeout: Duration
  ) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        for await event in events {
          return event
        }
        throw EventWaitError.streamEnded
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw EventWaitError.timedOut
      }
      guard let event = try await group.next() else {
        throw EventWaitError.streamEnded
      }
      group.cancelAll()
      return event
    }
  }

}
