import Foundation
import RunnerKit

// What the Maintenance submenu shows, as values a test can read. Same rule as
// `FleetPresentation.swift`: the view renders these and decides nothing, because
// a `View` body is the one thing in this app no test can make an assertion
// about — and every bug this unit could ship is a wiring bug.

/// Sizes as the menu writes them.
enum ByteText {
  /// Finder's units, so `4.23 GB` here is the `4.23 GB` in Get Info.
  ///
  /// `du -sk` counts 1024-byte blocks and this counts in thousands, which
  /// sounds like a discrepancy and is not: how many bytes there are and how a
  /// number of bytes is written down are different questions, and the second
  /// one has an answer the user can check against another window.
  static func short(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    // No plain bytes. A menu row saying "Other runner files — 4,096 bytes" is
    // more precision than the decision needs, and every row here is a decision
    // about whether something is worth deleting.
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return formatter.string(fromByteCount: bytes)
  }
}

/// Paths as the menu writes them.
enum PathText {
  /// `~/actions-runner/_work/_tool`, the same shortening the unreadable-runner
  /// notice uses. A menu row is not wide enough for a home directory twice.
  static func abbreviated(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
  }
}

extension DisplayState {
  /// Whether this runner's caches may be deleted right now.
  ///
  /// Read off *this* runner, never off the fleet summary — the same rule as
  /// Start and Stop, and for a worse reason: a summary of one idle runner and
  /// one busy one is not idle, but it is also not a statement about either of
  /// them, and this is the one button in the app that breaks a build when it is
  /// wrong about which.
  ///
  /// `.starting` is excluded by having no resolved state at all, which is
  /// right: a runner that was started three seconds ago is one GitHub is about
  /// to start sending work to.
  var allowsHousekeeping: Bool { resolvedState?.allowsHousekeeping == true }
}

/// One button in the Maintenance submenu.
struct MaintenanceOffer: Equatable, Identifiable {
  enum Kind: Hashable, CaseIterable {
    case measure
    case cleanToolCache
    case cleanActionCache
    case trimLogs
  }

  let kind: Kind
  let label: String
  let isEnabled: Bool
  var id: Kind { kind }
}

extension MaintenanceOffer.Kind {
  /// The directory this button deletes, and nil for the ones that delete no
  /// directory. Derived from `CleanupTarget` rather than switched on twice, so
  /// there is one list of what may be deleted and not two.
  var target: CleanupTarget? {
    switch self {
    case .cleanToolCache: .toolCache
    case .cleanActionCache: .actionCache
    case .measure, .trimLogs: nil
    }
  }

  init(_ target: CleanupTarget) {
    switch target {
    case .toolCache: self = .cleanToolCache
    case .actionCache: self = .cleanActionCache
    }
  }
}

/// One runner's slice of the Maintenance submenu.
struct MaintenanceSection: Equatable {
  /// Which runner is installed, and whether a newer one exists. Nil when no log
  /// on this machine says.
  let version: String?
  /// What is taking up space, biggest first. Empty until somebody measures.
  let usage: [String]
  /// When those numbers were taken — deliberately a line of its own, because
  /// unlike everything else in this menu they are not refreshed on a timer.
  let measured: String
  let offers: [MaintenanceOffer]
  /// Anything that needs saying under the buttons: why they are greyed out,
  /// and what the last one did.
  let notes: [String]

  func offer(_ kind: MaintenanceOffer.Kind) -> MaintenanceOffer? {
    offers.first { $0.kind == kind }
  }
}

extension MaintenanceSection {
  /// - Parameters:
  ///   - isWorking: whether this runner already has a measurement or a deletion
  ///     in flight. Every button goes dead, because all of them either read or
  ///     rewrite the numbers the others are showing.
  ///   - now: when the menu is being drawn, which is what ages the measurement.
  static func building(
    _ snapshot: RunnerSnapshot, measurement: DiskMeasurement?, latest: RunnerVersion?,
    isWorking: Bool, notice: String?, now: Date
  ) -> MaintenanceSection {
    let report = measurement?.report
    var offers = [
      MaintenanceOffer(
        kind: .measure, label: L10n.measureDiskUse, isEnabled: !isWorking)
    ]
    // Nothing is offered for deletion before the size of it is known. A button
    // that cannot say what it frees is a button nobody can decide about, and
    // the confirmation it opens would have the same hole in it.
    let canDelete = snapshot.display.allowsHousekeeping && !isWorking
    if let report {
      for target in CleanupTarget.allCases {
        let bytes = report.bytes(of: target.kind)
        // An empty cache has nothing to free, and offering to free it would be
        // a row that does nothing followed by a dialogue about nothing.
        guard bytes > 0 else { continue }
        offers.append(
          MaintenanceOffer(
            kind: MaintenanceOffer.Kind(target),
            label: Self.label(for: target, bytes: bytes), isEnabled: canDelete))
      }
      if report.rotation.bytes > 0 {
        offers.append(
          MaintenanceOffer(
            kind: .trimLogs,
            label: L10n.deleteOldLogs(ByteText.short(report.rotation.bytes)),
            isEnabled: canDelete))
      }
    }

    var notes: [String] = []
    // Only where there is something to explain. A runner with nothing to delete
    // gains nothing from being told when deleting would be offered.
    if offers.contains(where: { $0.kind != .measure }),
      !snapshot.display.allowsHousekeeping
    {
      notes.append(L10n.deletingOnlyWhenIdle)
    }
    if let notice { notes.append(notice) }

    return MaintenanceSection(
      version: Self.versionLine(snapshot.version, latest: latest),
      usage: Self.usageLines(report),
      measured: Self.measuredLine(measurement, isWorking: isWorking, now: now),
      offers: offers,
      notes: notes)
  }

  private static func usageLines(_ report: DiskReport?) -> [String] {
    guard let report else { return [] }
    var lines =
      DiskEntryKind.allCases
      .map { ($0, report.bytes(of: $0)) }
      // Empty directories are not news. `_work` on a runner that builds one
      // repository has three of them, and a submenu of zeroes buries the one
      // number worth reading.
      .filter { $0.1 > 0 }
      .sorted { $0.1 > $1.1 }
      .map { row(for: $0.0, bytes: $0.1) }
    if report.logBytes > 0 { lines.append(L10n.diskLogs(ByteText.short(report.logBytes))) }
    return lines
  }

  private static func row(for kind: DiskEntryKind, bytes: Int64) -> String {
    let size = ByteText.short(bytes)
    switch kind {
    case .toolCache: return L10n.diskToolCache(size)
    case .actionCache: return L10n.diskActionCache(size)
    case .checkout: return L10n.diskCheckouts(size)
    case .temporary: return L10n.diskTemporary(size)
    case .other: return L10n.diskOther(size)
    }
  }

  private static func label(for target: CleanupTarget, bytes: Int64) -> String {
    let size = ByteText.short(bytes)
    switch target {
    case .toolCache: return L10n.freeToolCache(size)
    case .actionCache: return L10n.freeActionCache(size)
    }
  }

  private static func measuredLine(
    _ measurement: DiskMeasurement?, isWorking: Bool, now: Date
  ) -> String {
    if isWorking { return L10n.diskWorking }
    guard let measurement else { return L10n.diskNotMeasured }
    // A measurement that failed is not a measurement. Showing "measured 3m ago"
    // over no rows at all would read as a runner using no disk, which is the
    // opposite of what happened.
    guard measurement.report != nil else { return L10n.diskUnavailable }
    let elapsed = now.timeIntervalSince(measurement.readAt)
    guard elapsed >= FleetStatus.justNow else { return L10n.diskMeasuredJustNow }
    return L10n.diskMeasuredAgo(DurationText.coarse(elapsed))
  }

  private static func versionLine(
    _ installed: RunnerVersion?, latest: RunnerVersion?
  ) -> String? {
    guard let installed else { return nil }
    // Only when the published one is genuinely newer. A runner ahead of the
    // latest release is what a pre-release build looks like, and telling that
    // user to update is telling them to go backwards.
    guard let latest, latest > installed else {
      return L10n.runnerVersion(installed.description)
    }
    return L10n.runnerVersionOutdated(installed.description, latest.description)
  }
}

// MARK: - The confirmation

/// What the confirmation asks, as data.
///
/// A value rather than an `NSAlert` built at the call site, for the same reason
/// the rows above are values: this is the last thing between a click and four
/// gigabytes going away, and the text of it — which directory, how much, whose
/// — is the whole safety mechanism. A test has to be able to read it.
struct CleanupPrompt: Equatable {
  let title: String
  let message: String
  let confirm: String
  let cancel: String
}

extension CleanupPrompt {
  static func cleaning(
    _ target: CleanupTarget, in runner: DiscoveredRunner, bytes: Int64
  ) -> CleanupPrompt {
    CleanupPrompt(
      // The path, not the folder name. `_tool` does not say whose, and this app
      // is built for the Mac with two runners on it.
      title: L10n.cleanupConfirmTitle(
        PathText.abbreviated(target.directory(in: runner))),
      message: [
        L10n.cleanupConfirmBody(ByteText.short(bytes), runner.displayName),
        effect(of: target),
      ].joined(separator: "\n\n"),
      confirm: L10n.cleanupDelete,
      cancel: L10n.cleanupCancel)
  }

  static func trimmingLogs(
    in runner: DiscoveredRunner, plan: DiagnosticsRotationPlan
  ) -> CleanupPrompt {
    CleanupPrompt(
      title: L10n.cleanupLogsTitle(
        plan.count, PathText.abbreviated(runner.diagnosticsDirectory)),
      message: [
        L10n.cleanupConfirmBody(ByteText.short(plan.bytes), runner.displayName),
        L10n.cleanupLogsEffect(plan.count),
      ].joined(separator: "\n\n"),
      confirm: L10n.cleanupDelete,
      cancel: L10n.cleanupCancel)
  }

  private static func effect(of target: CleanupTarget) -> String {
    switch target {
    case .toolCache: L10n.cleanupToolCacheEffect
    case .actionCache: L10n.cleanupActionCacheEffect
    }
  }
}
