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
  /// The runner had work by the time the last check ran, so its directory was
  /// not touched. Its own case rather than an error: refusing is this type
  /// working correctly, and the user has to be told which of the two happened.
  ///
  /// Nothing changed before the runner became unsafe. Kept distinct from the
  /// refusal below so callers do not remeasure an unchanged directory.
  case refused
  /// The runner's current directory was preserved, but a grave left by an
  /// earlier Standfast cleanup was removed before the safety probe answered.
  /// Callers keep the refusal notice and refresh the disk measurement.
  case refusedAfterChange
}

/// A write the filesystem refused, and the directory it refused it about.
///
/// Which directory is the whole of what the menu has to say — by the time
/// anything here can fail, what is left is a permission on one folder — and it
/// cannot be worked out from outside. A delete that fails does so *after* the
/// rename, so the directory the user was told about is not there any more, and
/// naming it would point them at a path that no longer exists.
public struct HousekeepingFailure: Error, Equatable, Sendable {
  public let directory: URL
  /// Whether the operation changed the directory, or began a recursive removal
  /// that may have changed it before failing. Callers invalidate measurements;
  /// the user-facing copy deliberately describes the uncertain case as such.
  public let didModify: Bool

  public init(directory: URL, didModify: Bool = false) {
    self.directory = directory
    self.didModify = didModify
  }
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
  private enum GraveSelection {
    case cache(CleanupTarget)
    case legacy

    func includes(_ grave: StandfastGrave) -> Bool {
      switch (self, grave) {
      case (.cache(let wanted), .cache(let found)): wanted == found
      case (.legacy, .legacy): true
      case (.cache, .legacy), (.legacy, .cache): false
      }
    }
  }

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
    guard let workDirectory = runner.containedWorkDirectory else {
      throw HousekeepingFailure(directory: runner.workDirectory)
    }
    let configuredWorkDirectory = runner.workDirectory
    let configuredTrash = configuredWorkDirectory.appendingPathComponent(Self.trashFolder)
    // This directory is Standfast's only when it is a directory at the name we
    // own. Even an internal symlink could point at another runner-owned folder;
    // sweeping that target would turn containment into permission to delete it.
    guard !Self.isSymbolicLink(at: configuredTrash),
      let trash = DiscoveredRunner.resolvedPath(configuredTrash, containedIn: workDirectory)
    else { throw HousekeepingFailure(directory: configuredTrash) }
    // Anything still in there is from an earlier run that did not finish
    // emptying it — quit, killed, or stopped by a file it could not unlink.
    // Nobody else writes here, so it is ours to clear, and clearing it is the
    // only thing that ever will.
    //
    // Above the guard below, which is the whole point of where this line sits.
    // A delete that failed halfway has already renamed the directory away, so
    // every later call finds no live cache and returns before it reaches here.
    // The measurement below now keeps a recovery button visible for a typed
    // grave, but that button only works because its call reaches this sweep
    // before the absent-cache return.
    let sweptLeftovers = try sweepLeftovers(in: trash, matching: .cache(target))

    let victim = workDirectory.appendingPathComponent(target.folderName)
    guard FileManager.default.fileExists(atPath: victim.path) else {
      removeIfEmpty(trash)
      return sweptLeftovers ? .done : .nothingToDo
    }

    // `_work` and not the trash: what could not be written to is the directory
    // the trash was going to be made in, and sending the user to look at a
    // hidden folder that does not exist helps nobody.
    try attempting(configuredWorkDirectory, didModify: sweptLeftovers) {
      try files.createDirectory(at: trash)
    }
    let grave = trash.appendingPathComponent(target.graveName(identifier: UUID()))

    // Everything above this line is preparation, and it is above the check for
    // that reason: what follows the check is one syscall.
    guard isStillSafe() else {
      // The empty folder this was about to delete through has no business
      // outliving the decision not to. Leaving it behind turns a refusal the
      // user is told changed nothing into a directory the next measurement
      // reports to them under "Other runner files".
      removeIfEmpty(trash)
      return sweptLeftovers ? .refusedAfterChange : .refused
    }
    try attempting(target.directory(in: runner), didModify: sweptLeftovers) {
      try files.move(victim, to: grave)
    }
    try attempting(configuredTrash, didModify: true) { try files.remove(grave) }
    removeIfEmpty(trash)
    return .done
  }

  /// Removes UUID-only graves made before Standfast encoded their cache kind.
  ///
  /// No runner cache is named or inferred here. These entries have already
  /// crossed the atomic rename and can be recovered only as generic Standfast
  /// leftovers; malformed names and typed graves are deliberately left for
  /// their own evidence-backed paths.
  @discardableResult
  public func blockingCleanLegacyTrash(
    in runner: DiscoveredRunner
  ) throws -> HousekeepingOutcome {
    guard let workDirectory = runner.containedWorkDirectory else {
      throw HousekeepingFailure(directory: runner.workDirectory)
    }
    let configuredTrash = runner.workDirectory.appendingPathComponent(Self.trashFolder)
    guard !Self.isSymbolicLink(at: configuredTrash),
      let trash = DiscoveredRunner.resolvedPath(configuredTrash, containedIn: workDirectory)
    else { throw HousekeepingFailure(directory: configuredTrash) }

    let swept = try sweepLeftovers(in: trash, matching: .legacy)
    removeIfEmpty(trash)
    return swept ? .done : .nothingToDo
  }

  /// Blocks the calling thread on a directory listing and a handful of
  /// unlinks. Same rule as `blockingClean`.
  ///
  /// - Parameters:
  ///   - now: the moment the sweep is being asked for, which is what ages the
  ///     files.
  ///   - agreedTo: the plan the user was shown, or nil to sweep whatever the
  ///     fresh one names. What they agreed to is a ceiling and never a floor:
  ///     the plan behind a confirmation comes out of a measurement of unbounded
  ///     age — there is no expiry on one, deliberately, because `du` is too
  ///     expensive to run on a timer — and `_diag` gains about ten worker logs
  ///     a day, so a fortnight-old number understates by a hundred and forty
  ///     files. Re-planning has to stay here, because that is what keeps the
  ///     log the listener has open out of the sweep; intersecting the two is
  ///     what keeps the count in the dialogue true as well.
  @discardableResult
  public func blockingRotateDiagnostics(
    in runner: DiscoveredRunner, retention: DiagnosticsRetention = .standard,
    now: Date, agreedTo agreed: DiagnosticsRotationPlan? = nil,
    isStillSafe: () -> Bool
  ) throws -> HousekeepingOutcome {
    guard let diagnostics = runner.containedDiagnosticsDirectory else {
      throw HousekeepingFailure(directory: runner.diagnosticsDirectory)
    }
    let plan: DiagnosticsRotationPlan
    do {
      plan = try Self.rotationPlan(
        in: diagnostics, retention: retention, now: now,
        limitedTo: agreed.map { Set($0.doomed) })
    } catch {
      throw HousekeepingFailure(directory: runner.diagnosticsDirectory)
    }
    guard !plan.isEmpty else { return .nothingToDo }
    guard isStillSafe() else { return .refused }
    // Unlinked one at a time rather than moved aside first. Each unlink is
    // already atomic on its own, a sweep interrupted halfway leaves a `_diag`
    // that is still a perfectly good `_diag`, and the one file this app's job
    // reader depends on — the log the listener has open — is never in the plan.
    //
    // A file that has gone since the plan was made is not a failure either: the
    // point of the whole operation is that it is not there any more.
    var didModify = false
    for url in plan.doomed {
      do {
        didModify =
          try removingIfPresent(url, blaming: runner.diagnosticsDirectory)
          || didModify
      } catch let failure as HousekeepingFailure {
        throw HousekeepingFailure(
          directory: failure.directory,
          didModify: didModify || failure.didModify)
      }
    }
    return .done
  }

  public static func rotationPlan(
    for runner: DiscoveredRunner, retention: DiagnosticsRetention = .standard,
    now: Date, limitedTo allowed: Set<URL>? = nil
  ) throws -> DiagnosticsRotationPlan {
    guard let diagnostics = runner.containedDiagnosticsDirectory else {
      throw HousekeepingFailure(directory: runner.diagnosticsDirectory)
    }
    do {
      return try rotationPlan(
        in: diagnostics, retention: retention, now: now, limitedTo: allowed)
    } catch {
      throw HousekeepingFailure(directory: runner.diagnosticsDirectory)
    }
  }

  private static func rotationPlan(
    in diagnostics: URL, retention: DiagnosticsRetention,
    now: Date, limitedTo allowed: Set<URL>?
  ) throws -> DiagnosticsRotationPlan {
    DiagnosticsRotation.plan(
      try DiagnosticsFile.listing(in: diagnostics),
      retention: retention, now: now, limitedTo: allowed)
  }

  private static func isSymbolicLink(at url: URL) -> Bool {
    fileType(at: url) == .typeSymbolicLink
  }

  private static func fileType(at url: URL) -> FileAttributeType? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.type] as? FileAttributeType
  }

  private func sweepLeftovers(
    in trash: URL, matching selection: GraveSelection
  ) throws -> Bool {
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: trash, includingPropertiesForKeys: nil)
    } catch let error where FileSystemFailure.isMissing(error) {
      return false
    } catch {
      throw HousekeepingFailure(directory: trash)
    }
    var didModify = false
    for entry in entries {
      guard Self.fileType(at: entry) == .typeDirectory,
        let grave = StandfastGrave(name: entry.lastPathComponent),
        selection.includes(grave)
      else { continue }
      do {
        try files.remove(entry)
        didModify = true
      } catch let error where FileSystemFailure.isMissing(error) {
        // Another actor reached the same desired state between our listing and
        // unlink. It is not a cleanup failure, but it proves the measurement
        // that led here is stale and must be refreshed.
        didModify = true
      } catch {
        // Recursive directory removal is not atomic. Even the first call may
        // have unlinked children before reporting the file it could not remove,
        // so conservatively invalidate the measurement from this point on.
        throw HousekeepingFailure(directory: trash, didModify: true)
      }
    }
    return didModify
  }

  /// Removes the trash only when it is ours alone to remove. Two cleanups
  /// running at once would otherwise let the first one finish by deleting the
  /// second one's grave.
  ///
  /// Never a failure: an empty hidden folder left behind costs a row in a
  /// breakdown, and the action the user asked for has already happened.
  private func removeIfEmpty(_ trash: URL) {
    // A listing that could not be read leaves it alone: a directory nothing can
    // look inside is not one to delete recursively.
    guard let left = try? FileManager.default.contentsOfDirectory(atPath: trash.path),
      left.isEmpty
    else { return }
    try? files.remove(trash)
  }

  /// Names the directory a failed write was about, so the menu can point at the
  /// one thing the user can fix.
  private func attempting(
    _ directory: URL, didModify: Bool = false, _ write: () throws -> Void
  ) throws {
    do { try write() } catch {
      throw HousekeepingFailure(directory: directory, didModify: didModify)
    }
  }

  private func removingIfPresent(_ url: URL, blaming directory: URL) throws -> Bool {
    do {
      try files.remove(url)
      return true
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return false
    } catch {
      throw HousekeepingFailure(directory: directory)
    }
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
