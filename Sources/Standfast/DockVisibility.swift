import AppKit
import Foundation

/// Where Standfast is willing to be seen.
///
/// Not a boolean at the seam, because the two values are not "on" and "off" of
/// the same thing: one is an app with a Dock tile, a menu bar of its own and a
/// place in ⌘-Tab, the other is a process macOS does not list at all.
enum DockPresence: Equatable, Sendable {
  case dock
  case menuBarOnly
}

/// The seam. `NSApplication.setActivationPolicy` is process-wide state, so a
/// test that called it for real would move the test runner into the Dock and
/// leave it there for everything that ran afterwards.
@MainActor
protocol ActivationPolicySetting: AnyObject {
  func apply(_ presence: DockPresence)
}

@MainActor
final class AppActivationPolicy: ActivationPolicySetting {
  func apply(_ presence: DockPresence) {
    switch presence {
    case .dock: NSApp?.setActivationPolicy(.regular)
    case .menuBarOnly: NSApp?.setActivationPolicy(.accessory)
    }
  }
}

/// Whether this Mac shows Standfast in the Dock.
///
/// `LSUIElement` in the bundle decides how the process *starts* — as an
/// accessory, with the icon in the menu bar and no tile — and that stays the
/// default: this is a menu bar app, the strict gate refuses a build that takes
/// a tile nobody asked for, and a status item that also occupies the Dock is
/// two answers to "is it running?".
///
/// What `LSUIElement` cannot be is a preference. It is read once at launch and
/// changing it means editing the installed bundle, which invalidates the
/// signature. The activation policy is the same decision, made at runtime and
/// reversible, so the switch lives here.
@MainActor
final class DockVisibility: ObservableObject {
  static let defaultsKey = "dev.standfast.settings.dock.visible"

  @Published private(set) var isVisible: Bool

  private let policy: any ActivationPolicySetting
  private let defaults: UserDefaults

  init(
    policy: any ActivationPolicySetting = AppActivationPolicy(),
    defaults: UserDefaults = .standard
  ) {
    self.policy = policy
    self.defaults = defaults
    // Absent means off, which is what `bool(forKey:)` already answers for a key
    // nobody has written. Said out loud because the alternative — inheriting
    // whatever the process happens to be — would make the switch describe the
    // app on one launch and disagree with it on the next.
    isVisible = defaults.bool(forKey: Self.defaultsKey)
    // At launch, not on first use. A preference that only takes effect the next
    // time somebody touches the switch is a preference the app forgot.
    policy.apply(isVisible ? .dock : .menuBarOnly)
  }

  func setVisible(_ visible: Bool) {
    isVisible = visible
    defaults.set(visible, forKey: Self.defaultsKey)
    policy.apply(visible ? .dock : .menuBarOnly)
  }
}
