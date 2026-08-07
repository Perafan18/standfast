import Foundation

/// The deliberately small menu-bar projection.
///
/// The menu answers only the questions that fit in a glance: whether the fleet
/// is healthy, which three runners need attention first, and where to go for
/// the full controls. It is a value so opening the menu never starts a scan or
/// changes a runner.
struct QuickMenuPresentation: Equatable {
  enum Item: Equatable {
    case fleet(String)
    case runner(RunnerEcho)
    case discovery(String)
    case thermal(String)
    case freshness(String)
    case refresh
    case openControlCenter
    case openSettings
    case quit
  }

  /// The one compact slice of a runner that belongs in the quick menu.
  ///
  /// `canStart` is intentionally the only action capability. The full set of
  /// service actions stays in the Control Center, while a conclusively stopped
  /// service can safely offer the one recovery action here.
  struct RunnerEcho: Equatable, Identifiable {
    let id: String
    let title: String
    let progress: String?
    let operation: ServiceOperationPresentation?
    let canStart: Bool
  }

  let items: [Item]
  var namedRowCount: Int { items.count }
}

extension QuickMenuPresentation {
  /// Builds the bounded menu from already-read model values.
  static func building(
    snapshots: [RunnerSnapshot], notice: FleetNotice?, thermalLines: [String],
    readAt: Date?, now: Date
  ) -> Self {
    let candidates = snapshots.enumerated().compactMap { index, snapshot in
      echoCandidate(for: snapshot).map { (index: index, snapshot: snapshot, priority: $0) }
    }
    let echoes =
      candidates
      .sorted { lhs, rhs in
        lhs.priority == rhs.priority ? lhs.index < rhs.index : lhs.priority < rhs.priority
      }
      .prefix(Self.runnerEchoLimit)
      .map { runnerEcho(for: $0.snapshot) }

    let fleetLine =
      candidates.count > Self.runnerEchoLimit
      ? L10n.quickMenuMoreRunners(candidates.count - Self.runnerEchoLimit)
      : L10n.quickMenuFleet(
        FleetSummary.accessibilityValue(
          for: FleetSummary.summarising(snapshots.map(\.display)))
      )

    var items: [Item] = [.fleet(fleetLine)]
    items += echoes.map(Item.runner)
    if let notice { items.append(.discovery(discoverySummary(for: notice))) }
    items += thermalLines.prefix(Self.thermalLinesShown).map(Item.thermal)
    items += [
      .freshness(FleetStatus.lastCheckedLine(readAt: readAt, now: now)),
      .refresh, .openControlCenter, .openSettings, .quit,
    ]
    return Self(items: items)
  }

  /// The maximum echoes are a hard menu-height budget, not an estimate based
  /// on display width or an attempt to print a smaller row.
  private static let runnerEchoLimit = 3
  private static let thermalLinesShown = 2

  private static func runnerEcho(for snapshot: RunnerSnapshot) -> RunnerEcho {
    let row = snapshot.row
    return RunnerEcho(
      id: snapshot.id, title: row.title, progress: row.progress, operation: row.operation,
      canStart: snapshot.display == .resolved(.stopped) && !snapshot.isServiceActionReserved
    )
  }

  /// One discovery item must remain one rendered line. The detailed paths are
  /// still available in the Control Center; putting them here recreates the
  /// unbounded menu this type replaces.
  private static func discoverySummary(for notice: FleetNotice) -> String {
    notice.lines.first ?? ""
  }

  private static func echoCandidate(for snapshot: RunnerSnapshot) -> EchoPriority? {
    switch snapshot.display {
    case .resolved(.disconnected), .resolved(.stopped), .resolved(.unknown):
      .attention
    case .resolved(.busy) where snapshot.operation != nil:
      .activity
    case .starting where snapshot.operation != nil:
      .activity
    case .resolved(.busy):
      .activity
    case .starting:
      .starting
    case .resolved(.idle):
      snapshot.operation == nil ? nil : .activity
    }
  }

  private enum EchoPriority: Int, Comparable {
    case attention
    case activity
    case starting

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }
}
