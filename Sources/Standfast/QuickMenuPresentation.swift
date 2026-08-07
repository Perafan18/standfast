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

  struct RunnerIdentityFormatting: Sendable {
    let runner: @Sendable (String, String) -> String
    let runnerInScope: @Sendable (String, String, String) -> String
    let scopeWithID: @Sendable (String, Int) -> String

    static var localized: Self {
      Self(
        runner: { L10n.quickMenuRunner($0, $1) },
        runnerInScope: { L10n.quickMenuRunnerInScope($0, $1, $2) },
        scopeWithID: { L10n.quickMenuScopeWithID($0, $1) })
    }
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
    snapshots: [RunnerSnapshot], overview: FleetOverviewPresentation,
    thermalLines: [String],
    readAt: Date?, now: Date,
    identityFormatting: RunnerIdentityFormatting = .localized
  ) -> Self {
    let identities = runnerIdentities(
      for: snapshots, identityFormatting: identityFormatting)
    var items = zip(snapshots, identities).map { snapshot, identity in
      Item.runner(
        runnerEcho(
          for: snapshot, identity: identity,
          identityFormatting: identityFormatting))
    }
    if let discovery = overview.quickMenuDiscoveryLine {
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
    var discriminators: [Int] = []

    func rendered(
      state: String, identityFormatting: RunnerIdentityFormatting
    ) -> String {
      if let qualifier {
        let qualified = discriminators.reduce(qualifier) { scope, discriminator in
          identityFormatting.scopeWithID(scope, discriminator)
        }
        return identityFormatting.runnerInScope(name, qualified, state)
      }
      let qualified = discriminators.reduce(name) { identity, discriminator in
        identityFormatting.scopeWithID(identity, discriminator)
      }
      return identityFormatting.runner(qualified, state)
    }
  }

  private static let thermalLinesShown = 2
  private static let collisionStatePlaceholder = "\u{0}standfast-state\u{0}"

  private static func runnerIdentities(
    for snapshots: [RunnerSnapshot],
    identityFormatting: RunnerIdentityFormatting
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
    }

    while true {
      let collisions = Dictionary(
        grouping: identities.indices,
        by: {
          identities[$0].rendered(
            state: collisionStatePlaceholder,
            identityFormatting: identityFormatting)
        }
      ).values.filter { $0.count > 1 }
      guard !collisions.isEmpty else { break }

      for collision in collisions {
        let agentIDs = collision.map { snapshots[$0].runner.agentId }
        let discriminators =
          Set(agentIDs).count == collision.count
          ? agentIDs : Array(1...collision.count)
        for (index, discriminator) in zip(collision, discriminators) {
          identities[index].discriminators.append(discriminator)
        }
      }
    }
    return identities
  }

  private static func runnerEcho(
    for snapshot: RunnerSnapshot, identity: RunnerIdentity,
    identityFormatting: RunnerIdentityFormatting
  ) -> RunnerEcho {
    return RunnerEcho(
      id: snapshot.id,
      title: identity.rendered(
        state: snapshot.display.shortSummary,
        identityFormatting: identityFormatting),
      longState: snapshot.display.summary,
      progress: snapshot.jobProgress?.line, operation: snapshot.operation?.presentation,
      canStart: snapshot.display == .resolved(.stopped) && !snapshot.isServiceActionReserved
    )
  }

}
