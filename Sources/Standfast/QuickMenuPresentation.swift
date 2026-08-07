import Foundation
import RunnerKit

/// The deliberately small menu-bar projection.
///
/// The menu names every discovered runner in discovery order and keeps detail
/// inside native submenus. It is a value so opening the menu never starts a
/// scan or changes a runner.
struct QuickMenuPresentation: Equatable {
  enum Item: Equatable {
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
    let longState: String
    let progress: String?
    let operation: ServiceOperationPresentation?
    let canStart: Bool
  }

  /// The native top-level elements the menu view emits. Runner state,
  /// progress, operation feedback, and Start live inside one submenu instead
  /// of becoming sibling menu rows.
  struct Emission: Equatable {
    enum Element: Equatable {
      case text(String)
      case runnerMenu(RunnerEcho)
      case refresh
      case openControlCenter
      case openSettings
      case quit
    }

    let elements: [Element]
  }

  let items: [Item]
  var namedRowCount: Int { emission.elements.count }

  var emission: Emission {
    Emission(
      elements: items.map { item in
        switch item {
        case .discovery(let line), .thermal(let line), .freshness(let line):
          .text(line)
        case .runner(let runner):
          .runnerMenu(runner)
        case .refresh:
          .refresh
        case .openControlCenter:
          .openControlCenter
        case .openSettings:
          .openSettings
        case .quit:
          .quit
        }
      })
  }
}

extension QuickMenuPresentation {
  static func building(
    snapshots: [RunnerSnapshot], notice: FleetNotice?, thermalLines: [String],
    readAt: Date?, now: Date
  ) -> Self {
    let identities = runnerIdentities(for: snapshots)
    var items = zip(snapshots, identities).map { snapshot, identity in
      Item.runner(runnerEcho(for: snapshot, identity: identity))
    }
    if let notice, let discovery = discoverySummary(for: notice) {
      items.append(.discovery(discovery))
    }
    items += thermalLines.prefix(Self.thermalLinesShown).map(Item.thermal)
    items += [
      .freshness(FleetStatus.lastCheckedLine(readAt: readAt, now: now)),
      .refresh, .openControlCenter, .openSettings, .quit,
    ]
    return Self(items: items)
  }

  private struct RunnerIdentity {
    let name: String
    var qualifier: String?
  }

  private static let thermalLinesShown = 2

  private static func runnerIdentities(
    for snapshots: [RunnerSnapshot]
  ) -> [RunnerIdentity] {
    var identities = snapshots.map {
      RunnerIdentity(name: $0.runner.displayName, qualifier: nil)
    }
    let groups = Dictionary(
      grouping: snapshots.indices, by: { snapshots[$0].runner.displayName })

    for indices in groups.values where indices.count > 1 {
      let repositoryNames = indices.compactMap { index -> String? in
        guard case .repository(_, let name) = snapshots[index].runner.scope else {
          return nil
        }
        return name
      }
      if repositoryNames.count == indices.count,
        Set(repositoryNames).count == indices.count
      {
        for (index, repositoryName) in zip(indices, repositoryNames) {
          identities[index].qualifier = repositoryName
        }
      } else {
        for index in indices {
          identities[index].qualifier = snapshots[index].runner.scope.displayName
        }
      }

      let remainingCollisions = Dictionary(
        grouping: indices, by: { identities[$0].qualifier! })
      for collision in remainingCollisions.values where collision.count > 1 {
        let agentIDs = collision.map { snapshots[$0].runner.agentId }
        let discriminators: [Int]
        if Set(agentIDs).count == collision.count {
          discriminators = agentIDs
        } else {
          discriminators = Array(1...collision.count)
        }
        for (index, discriminator) in zip(collision, discriminators) {
          identities[index].qualifier = L10n.quickMenuScopeWithID(
            identities[index].qualifier!, discriminator)
        }
      }
    }
    return identities
  }

  private static func runnerEcho(
    for snapshot: RunnerSnapshot, identity: RunnerIdentity
  ) -> RunnerEcho {
    let title: String
    if let qualifier = identity.qualifier {
      title = L10n.quickMenuRunnerInScope(
        identity.name, qualifier, snapshot.display.shortSummary)
    } else {
      title = L10n.quickMenuRunner(identity.name, snapshot.display.shortSummary)
    }
    return RunnerEcho(
      id: snapshot.id, title: title, longState: snapshot.display.summary,
      progress: snapshot.jobProgress?.line, operation: snapshot.operation?.presentation,
      canStart: snapshot.display == .resolved(.stopped) && !snapshot.isServiceActionReserved
    )
  }

  /// One discovery item must remain one rendered line. The detailed paths are
  /// still available in the Control Center; putting them here recreates the
  /// unbounded menu this type replaces.
  private static func discoverySummary(for notice: FleetNotice) -> String? {
    switch notice {
    case .noRunnersInstalled:
      return L10n.noRunnersFound
    case .launchAgentsUnreadable(let directory):
      return [L10n.launchAgentsUnreadable, PathText.abbreviated(directory)]
        .joined(separator: " ")
    case .unreadable(let paths):
      guard let first = paths.first else { return nil }
      return [
        L10n.someRunnersUnreadable,
        PathText.abbreviated(first),
        paths.count > 1 ? L10n.moreUnreadable : nil,
      ]
      .compactMap { $0 }
      .joined(separator: " ")
    }
  }
}
