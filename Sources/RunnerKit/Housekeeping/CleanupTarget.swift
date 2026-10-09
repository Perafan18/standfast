import Foundation

/// What one directory under `_work` is for, which is the only thing that
/// decides whether it may be deleted.
public enum DiskEntryKind: Equatable, Sendable, CaseIterable {
  /// `_work/_tool`, the hosted tool cache. Four gigabytes of the four and a
  /// half on the Mac this was measured against, and every byte of it put there
  /// by an `actions/setup-*` that will put it back.
  case toolCache
  /// `_work/_actions`, where the runner checks out the actions a workflow uses.
  case actionCache
  /// `_work/_temp`, which is `$RUNNER_TEMP`.
  case temporary
  /// A repository working copy, one per repository this runner builds.
  case checkout
  /// Anything else the runner keeps in there — `_PipelineMapping` today.
  case other
}

/// What Standfast is willing to delete.
///
/// Two directories, and the list is short on purpose: this is the one thing
/// this app does that can break somebody's build.
///
/// Both are caches whose contents are re-fetched on a miss. `_tool` is the
/// hosted tool cache an `actions/setup-*` step fills; `_actions` is where the
/// runner checks out the actions a workflow names, and it checks out any it
/// cannot find. Losing either costs one slow build and nothing else, which is
/// the property that makes them safe to offer at all.
///
/// Three neighbours are deliberately absent:
///
/// - **The repository checkouts.** Nothing in one is a cache. A workflow that
///   wrote a file git does not track — a build artefact, an `.env` a step
///   generated, a `node_modules` — loses it, and the next run pays for a full
///   clone where it would have paid for a fetch. On the machine this was
///   measured against it is also 9% of `_work`, so it buys nearly nothing for
///   by far the most risk.
/// - **`_work/_temp`.** It reads as the safest of the lot and it is the most
///   dangerous: it is `$RUNNER_TEMP`, where a job in flight keeps the script of
///   every composite step it is running. It is also empty whenever the runner
///   is idle — which is the only time any of this is offered — so deleting it
///   can free nothing and can break a build.
/// - **`_work/_PipelineMapping`**, the runner's own bookkeeping, and four
///   kilobytes of it.
public enum CleanupTarget: String, CaseIterable, Sendable {
  case toolCache
  case actionCache

  /// The folder under `_work`, as the runner names it.
  public var folderName: String {
    switch self {
    case .toolCache: "_tool"
    case .actionCache: "_actions"
    }
  }

  public var kind: DiskEntryKind {
    switch self {
    case .toolCache: .toolCache
    case .actionCache: .actionCache
    }
  }

  public func directory(in runner: DiscoveredRunner) -> URL {
    runner.workDirectory.appendingPathComponent(folderName)
  }

  /// A cache after the atomic rename and before its recursive delete finishes.
  /// The type survives in the leaf so a measurement can keep offering the one
  /// recovery action that reaches these bytes.
  func graveName(identifier: UUID) -> String {
    "standfast-v1.\(rawValue).\(identifier.uuidString)"
  }

  /// Recovers only names this version of Standfast emits. A partial match would
  /// let an unrelated or malformed entry in the private trash pose as a cache
  /// that is safe to delete.
  init?(graveName: String) {
    let pieces = graveName.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count == 3, pieces[0] == "standfast-v1",
      let target = CleanupTarget(rawValue: String(pieces[1])),
      let identifier = UUID(uuidString: String(pieces[2])),
      identifier.uuidString == pieces[2]
    else { return nil }
    self = target
  }
}

/// What a direct child of Standfast's private trash proves about its origin.
///
/// The first shipped names were bare UUIDs. They prove that Standfast made the
/// grave, but not whether it held `_tool` or `_actions`; preserving that
/// distinction avoids inventing a destructive cache kind during migration.
enum StandfastGrave: Equatable {
  case cache(CleanupTarget)
  case legacy

  init?(name: String) {
    if let target = CleanupTarget(graveName: name) {
      self = .cache(target)
      return
    }
    guard let identifier = UUID(uuidString: name), identifier.uuidString == name else {
      return nil
    }
    self = .legacy
  }
}

extension DiskEntryKind {
  /// Reads the kind off the folder's name, which is the only thing there is to
  /// read it off: `_work` carries no manifest.
  ///
  /// The two cache names come from `CleanupTarget` rather than being written
  /// again here. A second copy of `"_tool"` is how a rename ends up showing the
  /// tool cache under one heading and offering to delete a directory under
  /// another.
  init(folderName: String) {
    if let target = CleanupTarget.allCases.first(where: { $0.folderName == folderName }) {
      self = target.kind
    } else if folderName == "_temp" {
      self = .temporary
    } else {
      // Every directory the runner owns starts with an underscore. A leading
      // dot proves nothing, since `<org>/.github` checks out as `.github`, so
      // only the names this app and Finder leave here are singled out.
      let notARepository = [Housekeeper.trashFolder, ".DS_Store"].contains(folderName)
      self = folderName.hasPrefix("_") || notARepository ? .other : .checkout
    }
  }
}
