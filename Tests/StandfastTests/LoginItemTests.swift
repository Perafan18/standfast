import Foundation
import ServiceManagement
import Testing

@testable import Standfast

/// A login-item registration that answers whatever the test says macOS would.
///
/// `SMAppService` writes to the user's real login items and reads back from
/// launchd, neither of which a test may touch — and the whole point of this
/// unit is what happens when the two disagree.
private final class FakeRegistrar: LoginItemRegistering, @unchecked Sendable {
  private let lock = NSLock()
  private var current: LoginItemStatus
  /// What the machine ends up in after a successful request, which is not
  /// always what was asked for.
  private let landsOn: (Bool) -> LoginItemStatus
  private let failing: Bool
  private var calls: [String] = []

  init(
    _ current: LoginItemStatus, failing: Bool = false,
    landsOn: @escaping (Bool) -> LoginItemStatus = { $0 ? .enabled : .disabled }
  ) {
    self.current = current
    self.failing = failing
    self.landsOn = landsOn
  }

  /// Every call in order, so a test can see that the status was re-read *after*
  /// the change rather than assumed from it.
  var sequence: [String] {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }

  func status() -> LoginItemStatus {
    lock.lock()
    defer { lock.unlock() }
    calls.append("status")
    return current
  }

  func setEnabled(_ enabled: Bool) throws {
    lock.lock()
    calls.append(enabled ? "register" : "unregister")
    let refuses = failing
    if !refuses { current = landsOn(enabled) }
    lock.unlock()
    if refuses { throw CocoaError(.fileWriteNoPermission) }
  }
}

// MARK: - Opt in

@Test @MainActor func standfastDoesNotAddItselfToLoginItemsOnItsOwn() {
  // Nothing here registers anything at launch: an app that installs itself
  // into a user's login items without being asked is one they uninstall.
  let registrar = FakeRegistrar(.disabled)
  let item = LoginItem(registrar: registrar)

  #expect(item.isEnabled == false)
  #expect(item.notice == nil)
  #expect(registrar.sequence == ["status"])
}

@Test @MainActor func turningItOnRegistersAndThenChecks() {
  let registrar = FakeRegistrar(.disabled)
  let item = LoginItem(registrar: registrar)

  item.setEnabled(true)

  #expect(item.isEnabled)
  #expect(item.notice == nil)
  // The order is the assertion: the status this shows came from asking macOS
  // after the change, not from the change having been requested.
  #expect(registrar.sequence == ["status", "register", "status"])
}

@Test @MainActor func turningItOffUnregisters() {
  let registrar = FakeRegistrar(.enabled)
  let item = LoginItem(registrar: registrar)

  item.setEnabled(false)

  #expect(item.isEnabled == false)
  #expect(item.notice == nil)
  #expect(registrar.sequence == ["status", "unregister", "status"])
}

// MARK: - Not lying about it

@Test @MainActor func aRegistrationThatFailedLeavesTheToggleOffAndSaysSo() {
  // `register()` throws and nothing changes. A toggle drawn from what was
  // asked for would sit on `on` above an app that will never launch itself —
  // in an app whose entire premise is that a service reporting "Started" may
  // not be running.
  let registrar = FakeRegistrar(.disabled, failing: true)
  let item = LoginItem(registrar: registrar)

  item.setEnabled(true)

  #expect(item.isEnabled == false)
  #expect(item.notice == L10n.openAtLoginFailed)
}

@Test @MainActor func aRegistrationWaitingOnTheUserIsNotDrawnAsOn() {
  // The case nobody expects: `register()` succeeds, macOS keeps the
  // registration, and the user has switched Standfast off in System Settings.
  // Nothing threw and the app still will not launch.
  let registrar = FakeRegistrar(.disabled, landsOn: { _ in .requiresApproval })
  let item = LoginItem(registrar: registrar)

  item.setEnabled(true)

  #expect(item.isEnabled == false)
  #expect(item.notice == L10n.openAtLoginNeedsApproval)
  // And the notice names where to go, because the switch is not in this app.
  #expect(item.notice?.contains("Standfast") == true)
}

@Test @MainActor func anOffToggleNobodyTouchedExplainsNothing() {
  // The difference between "off because nobody wanted it on" and "off because
  // turning it on did not work". Only the second one is worth a line.
  let registrar = FakeRegistrar(.disabled, failing: true)
  let item = LoginItem(registrar: registrar)
  #expect(item.notice == nil)

  item.setEnabled(false)
  #expect(item.notice == nil)

  item.setEnabled(true)
  #expect(item.notice == L10n.openAtLoginFailed)
}

@Test @MainActor func aStatusThisVersionDoesNotRecogniseIsNotDrawnAsOff() {
  // `SMAppService.Status` is a system enum that may grow. Drawing a value
  // nobody has seen as a plain off switch is a guess about what a future macOS
  // meant by it, and the line has to point at the one place that does know.
  let item = LoginItem(registrar: FakeRegistrar(.unavailable))

  #expect(item.isEnabled == false)
  #expect(item.notice == L10n.openAtLoginUnavailable)
  // Not the failure line: nothing was attempted, so nothing failed.
  #expect(item.notice != L10n.openAtLoginFailed)
}

// MARK: - What macOS can answer

@Test func everyStatusMacOSCanReturnMapsToSomethingTheMenuCanDraw() {
  #expect(LoginItemStatus(.enabled) == .enabled)
  #expect(LoginItemStatus(.requiresApproval) == .requiresApproval)
  #expect(LoginItemStatus(.notRegistered) == .disabled)
  // Measured on a real Mac, against the obvious reading of the name.
  // `.notFound` is what `SMAppService.mainApp` answers for an app that has
  // never registered — which is every freshly installed copy — and registering
  // from there works. Calling it "unavailable" greeted every new user with a
  // line saying the feature does not work here, above a toggle that did.
  #expect(LoginItemStatus(.notFound) == .disabled)
  #expect(LoginItemStatus(.notFound) != .unavailable)
}
