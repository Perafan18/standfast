import Foundation

/// The read-only boundary published by actions-runner-fleet. Stable pool slots
/// survive the short-lived GitHub runner registrations created behind them.
struct ManagedFleetSnapshot: Decodable, Sendable {
  static let currentSchema = "actions-runner-fleet/status-v1"

  enum SupervisorState: String, Decodable, Sendable { case running, stopped }
  enum SlotPhase: String, Decodable, Sendable { case active, waiting }
  enum RemoteObservation: String, Decodable, Sendable {
    case notObserved = "not_observed"
    case available
    case unavailable
  }

  struct Remote: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case online, offline }
    let id: Int
    let name: String
    let status: Status
    let busy: Bool
  }

  struct Slot: Decodable, Sendable {
    let id: String
    let index: Int
    let phase: SlotPhase
    let runnerName: String?
    let workspace: String?
    let remote: Remote?

    enum CodingKeys: String, CodingKey {
      case id, index, phase, workspace, remote
      case runnerName = "runner_name"
    }
  }

  struct Pool: Decodable, Sendable {
    enum Scope: String, Decodable, Sendable { case repository, organization }
    let id: String
    let label: String
    let scope: Scope
    let target: String
    let capacity: Int
    let remoteObservation: RemoteObservation
    let slots: [Slot]

    enum CodingKeys: String, CodingKey {
      case id, label, scope, target, capacity, slots
      case remoteObservation = "remote_observation"
    }
  }

  let schema: String
  let generatedAt: Date
  let supervisorState: SupervisorState
  let pools: [Pool]

  enum CodingKeys: String, CodingKey {
    case schema, pools
    case generatedAt = "generated_at"
    case supervisorState = "supervisor_state"
  }

  init(contentsOf url: URL) throws {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let seconds = ISO8601DateFormatter()
      seconds.formatOptions = [.withInternetDateTime]
      guard let date = fractional.date(from: value) ?? seconds.date(from: value) else {
        throw DecodingError.dataCorruptedError(
          in: try decoder.singleValueContainer(), debugDescription: "Invalid generated_at")
      }
      return date
    }
    self = try decoder.decode(Self.self, from: data)
    guard schema == Self.currentSchema else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Unsupported managed fleet schema"))
    }
    guard pools.allSatisfy(Self.valid) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Invalid managed fleet snapshot"))
    }
    let poolIDs = pools.map(\.id)
    guard Set(poolIDs).count == poolIDs.count else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Duplicate managed fleet pool"))
    }
  }

  func runners(snapshotFile: URL, now: Date = Date()) -> [DiscoveredRunner] {
    pools.flatMap { pool in
      pool.slots.map { slot in
        let scope: RunnerScope =
          switch pool.scope {
          case .repository:
            if let slash = pool.target.firstIndex(of: "/") {
              .repository(
                owner: String(pool.target[..<slash]),
                name: String(pool.target[pool.target.index(after: slash)...]))
            } else {
              .organization(pool.target)
            }
          case .organization: .organization(pool.target)
          }
        let displayName =
          pool.capacity == 1 ? pool.label : "\(pool.label) #\(slot.index + 1)"
        let state: RunnerState
        if now.timeIntervalSince(generatedAt) > 120 {
          state = .unknown(.managedFleetStatusUnavailable)
        } else if supervisorState == .stopped {
          state = .stopped
        } else if slot.phase == .waiting
          || (slot.remote == nil && pool.remoteObservation == .available)
        {
          state = .unknown(.managedFleetWaiting)
        } else if pool.remoteObservation != .available {
          state = .unknown(.managedFleetStatusUnavailable)
        } else if let remote = slot.remote {
          state = remote.status == .offline ? .disconnected : (remote.busy ? .busy : .idle)
        } else {
          state = .unknown(.managedFleetStatusUnavailable)
        }
        let directory =
          slot.workspace.map(URL.init(fileURLWithPath:))
          ?? snapshotFile.deletingLastPathComponent().appendingPathComponent(pool.id)
        return DiscoveredRunner(
          label: "standfast.fleet:\(slot.id)", directory: directory,
          agentId: slot.remote?.id ?? 0, agentName: displayName, scope: scope,
          installation: .managedFleet, observedState: state, observedAt: generatedAt)
      }
    }
  }

  private static func valid(_ pool: Pool) -> Bool {
    guard !pool.id.isEmpty, !pool.label.isEmpty, !pool.target.isEmpty,
      pool.capacity > 0, pool.slots.count == pool.capacity
    else { return false }
    if pool.scope == .repository {
      let pieces = pool.target.split(separator: "/", omittingEmptySubsequences: false)
      guard pieces.count == 2, pieces.allSatisfy({ !$0.isEmpty }) else { return false }
    }
    return pool.slots.enumerated().allSatisfy { offset, slot in
      let phaseIsConsistent =
        switch slot.phase {
        case .active: slot.runnerName?.isEmpty == false
        case .waiting: slot.runnerName == nil && slot.workspace == nil && slot.remote == nil
        }
      return slot.index == offset && slot.id == "\(pool.id):\(offset)"
        && (slot.remote == nil || slot.remote?.name == slot.runnerName)
        && phaseIsConsistent
    }
  }
}
