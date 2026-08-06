import Foundation

/// The seam over `ProcessInfo`'s activity API, which touches the power
/// management of the machine the tests run on.
@MainActor
protocol SleepPreventing {
  /// - Returns: a token whose lifetime is the assertion. Opaque on purpose —
  ///   `ProcessInfo` hands back an object with nothing on it worth reading, and
  ///   the only thing anybody may do with it is give it back.
  func beginPreventingIdleSleep(reason: String) -> AnyObject
  func endPreventingIdleSleep(_ token: AnyObject)
}

struct ProcessActivity: SleepPreventing {
  func beginPreventingIdleSleep(reason: String) -> AnyObject {
    ProcessInfo.processInfo.beginActivity(
      options: .idleSystemSleepDisabled, reason: reason)
  }

  func endPreventingIdleSleep(_ token: AnyObject) {
    guard let activity = token as? NSObjectProtocol else { return }
    ProcessInfo.processInfo.endActivity(activity)
  }
}

/// Keeps the Mac awake for as long as a runner is building, and not one moment
/// longer.
///
/// `beginActivity` rather than a `caffeinate` subprocess. Both do the same
/// thing to the same subsystem, but a child process outlives a crash — leaving
/// a Mac that will not sleep and nothing on screen to say why — where the
/// assertion is held by this process and released with it, whatever kills it.
///
/// Off by default and worth being honest about who it is for. On the Mac mini
/// this was built against, on mains power with sleep already disabled, it does
/// nothing whatsoever. It is for the laptop: a MacBook that idles to sleep
/// forty minutes into a build kills the job, and the failure looks like a
/// network error rather than like a power setting.
@MainActor
final class SleepGuard: ObservableObject {
  /// Where the switch is remembered.
  static let defaultsKey = "preventSleep"

  /// What `pmset -g assertions` shows next to this app's assertion. A
  /// diagnostic string for whoever is working out why their Mac will not sleep,
  /// never shown in the app — which is why it does not go through `L10n`.
  static let reason = "Standfast: a self-hosted runner is executing a job"

  @Published private(set) var isEnabled: Bool

  private let activity: any SleepPreventing
  private let defaults: UserDefaults
  private var token: AnyObject?
  /// The last thing the fleet said, so switching this on mid-build takes hold
  /// immediately instead of at the next scan.
  private var isFleetBusy = false

  init(
    activity: any SleepPreventing = ProcessActivity(), defaults: UserDefaults = .standard
  ) {
    self.activity = activity
    self.defaults = defaults
    isEnabled = defaults.bool(forKey: Self.defaultsKey)
  }

  /// Whether the assertion is being held right now. The only observable
  /// difference this type makes, and the only thing worth asserting about it.
  var isHoldingTheMacAwake: Bool { token != nil }

  func setEnabled(_ on: Bool) {
    isEnabled = on
    defaults.set(on, forKey: Self.defaultsKey)
    reconcile()
  }

  /// - Parameter busy: whether *any* runner on this machine is executing a job.
  ///   One assertion for the fleet rather than one per runner: two runners
  ///   building and one finishing must not let the Mac sleep out from under the
  ///   other, and the token is either held or not.
  func update(busy: Bool) {
    isFleetBusy = busy
    reconcile()
  }

  private func reconcile() {
    let wanted = isEnabled && isFleetBusy
    if wanted, token == nil {
      token = activity.beginPreventingIdleSleep(reason: Self.reason)
    } else if !wanted, let held = token {
      // Released the moment the last job ends, rather than held for the life of
      // the app. An assertion nobody is using is a Mac that never sleeps.
      activity.endPreventingIdleSleep(held)
      token = nil
    }
  }
}
