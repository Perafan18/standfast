import Foundation
import RunnerKit

@testable import Standfast

/// The banners this app tried to put on screen, and the permission it asked
/// for. Nothing here touches `UNUserNotificationCenter`, which reads the running
/// application's bundle and raises when there is not one — and which would
/// otherwise make this suite depend on a permission CI cannot grant.
@MainActor
final class FakeNotificationDelivery: NotificationDelivering {
  struct Posted: Equatable {
    let title: String
    let body: String
    let id: String
  }

  private(set) var posted: [Posted] = []
  private(set) var authorizationRequests = 0
  /// What macOS answers when asked. Set to false for the user who said no.
  var grants = true

  func requestAuthorization() async -> Bool {
    authorizationRequests += 1
    return grants
  }

  func post(title: String, body: String, id: String) {
    posted.append(Posted(title: title, body: body, id: id))
  }
}

/// Counts the power assertions taken out and handed back, without going near
/// this machine's power management.
@MainActor
final class FakeSleepPreventer: SleepPreventing {
  private final class Token {}

  private(set) var begun = 0
  private(set) var ended = 0
  private(set) var reasons: [String] = []

  /// Whether an assertion is outstanding, counted rather than read off the
  /// guard — an implementation that took two and released one would otherwise
  /// look identical to a correct one.
  var isHeld: Bool { begun > ended }

  func beginPreventingIdleSleep(reason: String) -> AnyObject {
    begun += 1
    reasons.append(reason)
    return Token()
  }

  func endPreventingIdleSleep(_ token: AnyObject) { ended += 1 }
}

/// A temperature a test can set.
final class FakeThermalReporter: ThermalReporting, @unchecked Sendable {
  private let lock = NSLock()
  private var current: ThermalPressure

  init(_ pressure: ThermalPressure = .none) { current = pressure }

  func set(_ pressure: ThermalPressure) {
    lock.lock()
    defer { lock.unlock() }
    current = pressure
  }

  func pressure() -> ThermalPressure {
    lock.lock()
    defer { lock.unlock() }
    return current
  }
}

/// A defaults domain of this test's own, so a switch flipped here is never read
/// back on the machine running the suite.
func scratchDefaults() -> UserDefaults {
  let name = "standfast.tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

/// One runner's snapshot, built by hand.
///
/// The watcher reads snapshots rather than the machine, which is what lets a
/// state sequence that takes half an hour on a real runner be three lines here.
func snapshot(
  _ name: String = "build-mac", scope: String = "widget",
  display: DisplayState = .resolved(.idle), qualifier: String? = nil,
  jobs: JobHistory = .empty, readAt: Date = Date(timeIntervalSince1970: 1_785_962_174),
  version: RunnerVersion? = nil
) -> RunnerSnapshot {
  RunnerSnapshot(
    runner: DiscoveredRunner(
      label: "actions.runner.\(scope).\(name)",
      directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7, agentName: name,
      scope: .repository(owner: "acme", name: scope)),
    display: display, qualifier: qualifier, jobs: jobs, readAt: readAt,
    version: version)
}

/// A measurement built by hand, so the menu can be asked what it would show for
/// a disk without there being one.
func measured(
  toolCache: Int64 = 0, actionCache: Int64 = 0, checkout: Int64 = 0, logs: Int64 = 0,
  rotatable: Int64 = 0, rotatableCount: Int = 0,
  at readAt: Date = Date(timeIntervalSince1970: 1_785_962_174)
) -> DiskMeasurement {
  let named: [(String, DiskEntryKind, Int64)] = [
    ("_tool", .toolCache, toolCache), ("_actions", .actionCache, actionCache),
    ("nest-rules-app", .checkout, checkout),
  ]
  return DiskMeasurement(
    report: DiskReport(
      entries: named.map { DiskEntry(name: $0.0, kind: $0.1, bytes: $0.2) },
      logBytes: logs,
      rotation: DiagnosticsRotationPlan(
        doomed: (0..<rotatableCount).map { URL(fileURLWithPath: "/tmp/_diag/log\($0)") },
        bytes: rotatable)),
    readAt: readAt)
}

/// A finished job, the way `_diag` describes one.
func job(
  _ name: String, at seconds: TimeInterval, result: JobResult?, took: TimeInterval = 60
) -> JobRecord {
  JobRecord(
    name: name, startedAt: Date(timeIntervalSince1970: seconds),
    finishedAt: result == nil ? nil : Date(timeIntervalSince1970: seconds + took),
    result: result)
}

/// Newest first, the way `JobHistory` carries them.
func history(_ records: [JobRecord], running: JobRecord? = nil) -> JobHistory {
  JobHistory(records: records.sorted { $0.startedAt > $1.startedAt }, running: running)
}
