import Testing

@testable import Standfast

@MainActor
@Test func sceneActivationWaitsForAVisibleMainWindow() {
  var hasVisibleMainWindow = false
  var activationCount = 0
  var scheduled: [@MainActor () -> Void] = []
  let coordinator = SceneActivationCoordinator(
    maximumPollAttempts: 3,
    hasVisibleMainWindow: { hasVisibleMainWindow },
    activate: { activationCount += 1 },
    scheduleNextPoll: { scheduled.append($0) })

  coordinator.activateWhenWindowIsVisible()

  #expect(activationCount == 0)
  #expect(scheduled.count == 1)

  hasVisibleMainWindow = true
  scheduled.removeFirst()()

  #expect(activationCount == 1)
  #expect(scheduled.isEmpty)
}

@MainActor
@Test func sceneActivationUsesNoTimerWhenAWindowIsAlreadyVisible() {
  var activationCount = 0
  var scheduled: [@MainActor () -> Void] = []
  let coordinator = SceneActivationCoordinator(
    maximumPollAttempts: 3,
    hasVisibleMainWindow: { true },
    activate: { activationCount += 1 },
    scheduleNextPoll: { scheduled.append($0) })

  coordinator.activateWhenWindowIsVisible()

  #expect(activationCount == 1)
  #expect(scheduled.isEmpty)
}

@MainActor
@Test func sceneActivationFailsClosedAfterItsPollingBudget() {
  var activationCount = 0
  var scheduled: [@MainActor () -> Void] = []
  let coordinator = SceneActivationCoordinator(
    maximumPollAttempts: 2,
    hasVisibleMainWindow: { false },
    activate: { activationCount += 1 },
    scheduleNextPoll: { scheduled.append($0) })

  coordinator.activateWhenWindowIsVisible()
  #expect(scheduled.count == 1)

  scheduled.removeFirst()()
  #expect(scheduled.count == 1)

  scheduled.removeFirst()()
  #expect(scheduled.isEmpty)
  #expect(activationCount == 0)
}

@MainActor
@Test func sceneActivationStillObservesTheFinalAllowedPoll() {
  var observationCount = 0
  var activationCount = 0
  var scheduled: [@MainActor () -> Void] = []
  let coordinator = SceneActivationCoordinator(
    maximumPollAttempts: 2,
    hasVisibleMainWindow: {
      observationCount += 1
      return observationCount == 3
    },
    activate: { activationCount += 1 },
    scheduleNextPoll: { scheduled.append($0) })

  coordinator.activateWhenWindowIsVisible()
  scheduled.removeFirst()()
  scheduled.removeFirst()()

  #expect(observationCount == 3)
  #expect(activationCount == 1)
  #expect(scheduled.isEmpty)
}

@MainActor
@Test func liveSceneActivationActuallySchedulesAnotherObservation() async throws {
  var observationCount = 0
  var activationCount = 0
  let coordinator = SceneActivationCoordinator.live(
    hasVisibleMainWindow: {
      observationCount += 1
      return observationCount >= 2
    },
    activate: { activationCount += 1 })

  coordinator.activateWhenWindowIsVisible()

  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(1))
  while activationCount == 0 && clock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }

  #expect(observationCount >= 2)
  #expect(activationCount == 1)
}
