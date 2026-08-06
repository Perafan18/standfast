import Foundation
import UserNotifications

/// The three things this app will interrupt somebody for, each its own switch.
///
/// One switch per kind rather than one for the lot. They fail differently and
/// they are wanted differently: somebody who reads every build result wants the
/// failures and not the service, and somebody running a machine they never
/// look at wants the opposite.
enum NotificationKind: String, CaseIterable, Sendable {
  case jobFailed
  case runnerDisconnected
  case runnerStopped

  /// Where this switch is remembered. Spelled out rather than derived from
  /// `rawValue`, so renaming a case cannot silently reset everybody's settings.
  var defaultsKey: String {
    switch self {
    case .jobFailed: "notify.jobFailed"
    case .runnerDisconnected: "notify.runnerDisconnected"
    case .runnerStopped: "notify.runnerStopped"
    }
  }

  var menuLabel: String {
    switch self {
    case .jobFailed: L10n.notifyJobFailed
    case .runnerDisconnected: L10n.notifyDisconnected
    case .runnerStopped: L10n.notifyStopped
    }
  }
}

extension FleetEvent {
  /// Which switch decides whether this event is shown.
  var kind: NotificationKind {
    switch self {
    case .jobFailed: .jobFailed
    case .runnerDisconnected: .runnerDisconnected
    case .runnerStoppedUnexpectedly: .runnerStopped
    }
  }
}

/// What macOS has been told about notifications from this app.
enum NotificationAuthorization: Equatable {
  /// Nobody has been asked yet, which is the state this app starts every
  /// install in and stays in until a switch is turned on.
  case notDetermined
  case authorized
  /// Asked and refused, or switched off later in System Settings. The switches
  /// stay where the user put them and the menu says why nothing arrives —
  /// silently posting into a void would leave somebody waiting for a warning
  /// that can never come.
  case denied
}

/// The seam. `UNUserNotificationCenter.current()` reads the running
/// application's bundle and raises when there is not one, which is exactly the
/// situation under `swift test`; and a test may not put a real banner on the
/// machine it runs on, or depend on a permission a CI runner cannot grant.
@MainActor
protocol NotificationDelivering {
  /// - Returns: whether notifications may be shown from now on.
  func requestAuthorization() async -> Bool
  func post(title: String, body: String, id: String)
}

struct UserNotificationDelivery: NotificationDelivering {
  /// `.current()` is called here and never at initialisation: constructing one
  /// of these must stay free of side effects, because the app builds it at
  /// launch and the whole point is that nothing happens until a switch is
  /// turned on.
  func requestAuthorization() async -> Bool {
    let granted = try? await UNUserNotificationCenter.current()
      .requestAuthorization(options: [.alert, .sound])
    return granted == true
  }

  func post(title: String, body: String, id: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    // No trigger: delivered as soon as the system will take it. A time
    // interval trigger of zero is rejected, and one of a second would put the
    // banner up after the thing it describes has moved on.
    UNUserNotificationCenter.current()
      .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }
}

/// Which events reach the user, and whether macOS will let them.
///
/// Everything off until somebody says otherwise, and the permission prompt
/// deferred to that moment. An app that asks for notification permission on
/// first launch is asking before it has shown anybody why they would want one,
/// and the answer to a question asked that early is usually no — which is a
/// no that then applies to the failure notification the user would have said
/// yes to a week later.
@MainActor
final class NotificationSettings: ObservableObject {
  @Published private(set) var enabled: Set<NotificationKind>
  @Published private(set) var authorization: NotificationAuthorization = .notDetermined

  private let delivery: any NotificationDelivering
  private let defaults: UserDefaults
  /// Kept only so a test has something to wait on: the permission prompt is
  /// asynchronous and the switch it belongs to is not.
  private var request: Task<Void, Never>?

  init(
    delivery: any NotificationDelivering = UserNotificationDelivery(),
    defaults: UserDefaults = .standard
  ) {
    self.delivery = delivery
    self.defaults = defaults
    // `bool(forKey:)` answers false for a key nobody has written, which is the
    // default this feature needs anyway.
    enabled = Set(
      NotificationKind.allCases.filter { defaults.bool(forKey: $0.defaultsKey) })
  }

  func isEnabled(_ kind: NotificationKind) -> Bool { enabled.contains(kind) }

  func setEnabled(_ kind: NotificationKind, _ on: Bool) {
    if on { enabled.insert(kind) } else { enabled.remove(kind) }
    defaults.set(on, forKey: kind.defaultsKey)
    guard on else { return }
    // Asked on every enable rather than once. macOS only ever shows the prompt
    // for a decision it has not got, so a second call costs nothing — and it is
    // the one moment this app can find out that somebody has since switched
    // Standfast off in System Settings.
    request = Task { [delivery] in
      let granted = await delivery.requestAuthorization()
      authorization = granted ? .authorized : .denied
    }
  }

  /// The line under the switches, and nil when there is nothing to add.
  var notice: String? {
    // Only worth saying once a switch is on: an app that has never been asked
    // to notify anybody has nothing to explain.
    guard authorization == .denied, !enabled.isEmpty else { return nil }
    return L10n.notificationsBlocked
  }

  /// Shows the events whose switch is on, and drops the rest.
  func deliver(_ events: [FleetEvent]) {
    for event in events where enabled.contains(event.kind) {
      delivery.post(title: event.title, body: event.body, id: identifier(for: event))
    }
  }

  /// Waits for the permission prompt a switch started. Nothing in the app needs
  /// this; a test does.
  func quiesce() async { await request?.value }

  /// Distinct per event, so two runners going down do not replace each other's
  /// banner, and stable within one, so a repeat replaces rather than stacks.
  private func identifier(for event: FleetEvent) -> String {
    switch event {
    case .jobFailed(let runner, let job): "jobFailed.\(runner).\(job)"
    case .runnerDisconnected(let runner): "disconnected.\(runner)"
    case .runnerStoppedUnexpectedly(let runner): "stopped.\(runner)"
    }
  }
}
