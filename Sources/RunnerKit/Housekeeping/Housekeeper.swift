import Foundation

/// The one seam through which this app deletes anything.
///
/// Reading the filesystem needs no seam: a test points a reader at a temporary
/// tree and looks. Deleting does, for two separate reasons. A test that got a
/// path wrong would otherwise take somebody's real `_work` with it, and the
/// interesting assertion about a refusal is that *nothing was called* — which
/// is a statement about calls that were never made, and only a fake can answer
/// it.
public protocol DestructiveFileOperations: Sendable {
  /// Succeeds when the directory is already there.
  func createDirectory(at url: URL) throws
  func move(_ url: URL, to destination: URL) throws
  func remove(_ url: URL) throws
}

public struct FileSystemOperations: DestructiveFileOperations {
  public init() {}

  public func createDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  public func move(_ url: URL, to destination: URL) throws {
    try FileManager.default.moveItem(at: url, to: destination)
  }

  public func remove(_ url: URL) throws {
    try FileManager.default.removeItem(at: url)
  }
}

/// What a maintenance action did.
public enum HousekeepingOutcome: Equatable, Sendable {
  case done
  /// There was nothing there to delete. Not a failure — a tool cache that has
  /// already been cleared is the state the button was asking for.
  case nothingToDo
  /// The runner had work by the time the last check ran, so nothing was
  /// touched. Its own case rather than an error: refusing is this type working
  /// correctly, and the user has to be told which of the two happened.
  case refused
}

/// Deletes the parts of a runner's directory that can be deleted, and refuses
/// the moment it cannot prove that is safe.
///
/// The whole design is about one race. Between the user confirming and the
/// bytes going away, a job can arrive — the runner is idle, which is precisely
/// the state in which GitHub may hand it work at any moment — and a job that
/// starts mid-delete finds a directory that is half there.
///
/// Two things answer it, and the second matters more than the first. The
/// caller's `isStillSafe` is checked immediately before the deletion rather
/// than when the menu was drawn, and the deletion itself is a *rename*: the
/// directory is moved aside in one atomic syscall and taken apart afterwards.
/// So the window between the last check and the point of no return is a single
/// `rename(2)`, and a job that lands one microsecond later finds no tool cache
/// at all — which is a cache miss and a slower build — rather than half a tool
/// cache, which is a broken toolchain and a failed build.
public struct Housekeeper: Sendable {
  /// Where a directory goes while it is being taken apart.
  ///
  /// Inside `_work` on purpose. A move within one volume is a rename and costs
  /// nothing; a move to `/tmp` or to the user's Trash may cross volumes, and
  /// Foundation answers that with a whole-tree copy of four gigabytes that
  /// leaves the original in place for the minutes it takes. That would give
  /// back exactly the window this exists to close.
  public static let trashFolder = ".standfast-trash"

  private let files: any DestructiveFileOperations

  public init(files: any DestructiveFileOperations = FileSystemOperations()) {
    self.files = files
  }

  /// Blocks the calling thread: a rename, then a recursive delete of however
  /// many gigabytes were behind it. Safe only from a thread that is yours to
  /// block. See `offCooperativePool`.
  ///
  /// - Parameter isStillSafe: asked once, as late as it can be. It is expected
  ///   to be slow — reading a runner's state means `launchctl` and a call to
  ///   GitHub — which is why everything that can be done before it is done
  ///   before it.
  @discardableResult
  public func blockingClean(
    _ target: CleanupTarget, in runner: DiscoveredRunner, isStillSafe: () -> Bool
  ) throws -> HousekeepingOutcome {
    let victim = target.directory(in: runner)
    guard FileManager.default.fileExists(atPath: victim.path) else { return .nothingToDo }

    let trash = runner.workDirectory.appendingPathComponent(Self.trashFolder)
    // Anything still in there is from a previous run that was killed between
    // the rename and the delete. Nobody else writes here, so it is ours to
    // clear, and clearing it now is the only thing that ever will.
    sweepLeftovers(in: trash)
    try files.createDirectory(at: trash)
    let grave = trash.appendingPathComponent(UUID().uuidString)

    // Everything above this line is preparation, and it is above the check for
    // that reason: what follows the check is one syscall.
    guard isStillSafe() else { return .refused }
    try files.move(victim, to: grave)
    try files.remove(grave)
    // Only when it is ours alone to remove. Two cleanups running at once would
    // otherwise let the first one finish by deleting the second one's grave.
    if (try? FileManager.default.contentsOfDirectory(atPath: trash.path))?.isEmpty == true {
      try? files.remove(trash)
    }
    return .done
  }

  /// Blocks the calling thread on a directory listing and a handful of
  /// unlinks. Same rule as `blockingClean`.
  ///
  /// - Parameter now: the moment the sweep is being asked for, which is what
  ///   ages the files.
  @discardableResult
  public func blockingRotateDiagnostics(
    in runner: DiscoveredRunner, retention: DiagnosticsRetention = .standard,
    now: Date, isStillSafe: () -> Bool
  ) -> HousekeepingOutcome {
    let plan = Self.rotationPlan(for: runner, retention: retention, now: now)
    guard !plan.isEmpty else { return .nothingToDo }
    guard isStillSafe() else { return .refused }
    // Unlinked one at a time rather than moved aside first. Each unlink is
    // already atomic on its own, a sweep interrupted halfway leaves a `_diag`
    // that is still a perfectly good `_diag`, and the one file this app's job
    // reader depends on — the log the listener has open — is never in the plan.
    //
    // A file that has gone since the plan was made is not a failure either: the
    // point of the whole operation is that it is not there any more.
    for url in plan.doomed { try? files.remove(url) }
    return .done
  }

  public static func rotationPlan(
    for runner: DiscoveredRunner, retention: DiagnosticsRetention = .standard, now: Date
  ) -> DiagnosticsRotationPlan {
    DiagnosticsRotation.plan(
      DiagnosticsFile.listing(in: runner.diagnosticsDirectory),
      retention: retention, now: now)
  }

  private func sweepLeftovers(in trash: URL) {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: trash, includingPropertiesForKeys: nil)) ?? []
    for entry in entries { try? files.remove(entry) }
  }
}

extension RunnerState {
  /// Whether this runner's caches may be deleted right now.
  ///
  /// `.idle` and `.stopped`, and nothing else. `.busy` is obvious. The two that
  /// are not:
  ///
  /// `.disconnected` does not mean "not working" — GitHub reports a machine
  /// that dropped mid-job as offline with the job still assigned to it, which
  /// is the exact shape of a runner that is grinding away on a build while its
  /// connection is down. `.unknown` is the answer that says nothing at all, and
  /// "I could not tell" is not a licence to delete four gigabytes.
  public var allowsHousekeeping: Bool { self == .idle || self == .stopped }
}
