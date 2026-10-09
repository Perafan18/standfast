import Foundation
import ServiceManagement

/// Whether Standfast launches itself when the user logs in — as macOS has it,
/// never as this app last asked for it.
enum LoginItemStatus: Equatable {
  case enabled
  case disabled
  /// Registered, and switched off by the user in System Settings. macOS keeps
  /// the registration and declines to act on it, so this is neither of the two
  /// obvious answers: a toggle drawn from what this app requested would sit on
  /// `on` above an app that never launches.
  case requiresApproval
  /// macOS answered something this version does not recognise. Not a state any
  /// current macOS produces — `SMAppService.Status` is a system enum that may
  /// grow, and drawing a value nobody has seen as a plain off switch is a guess
  /// about what a future macOS meant.
  case unavailable
}

extension LoginItemStatus {
  init(_ status: SMAppService.Status) {
    switch status {
    case .enabled: self = .enabled
    // Both mean the same thing to a checkbox: this app is not a login item
    // right now. They are not the same underneath — `.notFound` is what an app
    // that has *never* registered answers, and `.notRegistered` is what one
    // that has been unregistered answers — but neither is a failure, and
    // neither stops a registration from working.
    //
    // Measured, because the obvious reading of `.notFound` is wrong: it is the
    // status of every freshly installed copy, and calling that "unavailable"
    // would greet every new user with a line saying the feature does not work
    // here, over a toggle that works perfectly.
    case .notRegistered, .notFound: self = .disabled
    case .requiresApproval: self = .requiresApproval
    default: self = .unavailable
    }
  }
}

/// The seam. `SMAppService` writes to the user's real login items and answers
/// from launchd, neither of which a test may touch.
protocol LoginItemRegistering: Sendable {
  func status() -> LoginItemStatus
  func setEnabled(_ enabled: Bool) throws
}

struct AppServiceLoginItem: LoginItemRegistering {
  func status() -> LoginItemStatus { LoginItemStatus(SMAppService.mainApp.status) }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}

/// Opt-in, and never louder than the truth.
@MainActor
final class LoginItem: ObservableObject {
  @Published private(set) var status: LoginItemStatus
  /// What was last asked for, and nil until something is. The only way to tell
  /// a login item that is off because nobody wanted it on from one that is off
  /// because turning it on did not work.
  @Published private(set) var lastRequest: Bool?

  private let registrar: any LoginItemRegistering

  init(registrar: any LoginItemRegistering = AppServiceLoginItem()) {
    self.registrar = registrar
    status = registrar.status()
  }

  /// Asks macOS again. The user can approve or switch off this item in System
  /// Settings at any time, and nothing tells this app it happened.
  func refresh() {
    let now = registrar.status()
    // Changed somewhere else, so what this app last asked for no longer
    // explains it: an item switched off in System Settings did not fail to
    // turn on.
    if now != status { lastRequest = nil }
    status = now
  }

  var isEnabled: Bool { status == .enabled }

  /// The line under the toggle, and nil when there is nothing to add.
  var notice: String? {
    switch status {
    case .enabled: nil
    case .disabled: lastRequest == true ? L10n.openAtLoginFailed : nil
    case .requiresApproval: L10n.openAtLoginNeedsApproval
    case .unavailable: L10n.openAtLoginUnavailable
    }
  }

  /// Asks macOS, then asks it back what actually happened.
  ///
  /// The re-read is the point. `register()` returning without throwing does not
  /// mean the item is enabled — a user who has switched Standfast off in System
  /// Settings leaves it `requiresApproval` — and `unregister()` on an app macOS
  /// has never heard of throws while changing nothing. A toggle that showed
  /// what was requested rather than what is true would be the one control in
  /// this app that lies about the machine, in an app whose entire premise is
  /// that a service reporting "Started" may not be running.
  func setEnabled(_ enabled: Bool) {
    lastRequest = enabled
    // Discarded rather than shown: `SMAppService`'s errors are `OSStatus`
    // numbers with no text a user could act on, and the status re-read below
    // says the one thing that matters — whether it took.
    try? registrar.setEnabled(enabled)
    status = registrar.status()
  }
}
