import Foundation

/// Asks whether a runner started by hand is actually running.
///
/// Its own probe, beside `LaunchctlProbe`, because a hand-started runner has no
/// launchd job to ask about. What it leaves instead is a process: its own
/// `Runner.Listener`, launched by absolute path out of its own directory, which
/// is the only thing on this Mac that distinguishes one runner's listener from
/// another's.
public struct ListenerProcessProbe: Sendable {
  /// The binary the runner starts. Deliberately not `Runner.Worker`, which is a
  /// job rather than the connection.
  static let listenerPath = "bin/Runner.Listener"

  /// What brings the listener back. `run.sh` loops, and a listener that exits
  /// to update or retry leaves this helper waiting seconds before the next one
  /// starts. It outlives a listener only to relaunch it.
  static let helperPath = "run-helper.sh"
  /// The helper's shebang, which the kernel puts in front of its path.
  static let helperInterpreter = "/bin/bash "

  /// An app opened from Finder or at login inherits no locale, and in the C
  /// locale `ps` escapes every byte outside ASCII, so a folder like
  /// `Integración` never matches. `LC_ALL` outranks anything inherited.
  private static let pinnedLocale = "LC_ALL=en_US.UTF-8"

  private let commandRunner: any CommandRunning
  private let userID: uid_t

  public init(
    commandRunner: any CommandRunning = ProcessCommandRunner(), userID: uid_t = getuid()
  ) {
    self.commandRunner = commandRunner
    self.userID = userID
  }

  /// Whether a listener is running out of this directory, or is about to be
  /// again, or nil when the process table could not be read.
  ///
  /// Nil rather than false, and for the reason `LaunchctlProbe` documents: a
  /// listing that failed says nothing about the runner, and folding it into
  /// "not running" draws a live runner as stopped with its controls greyed out.
  ///
  /// Blocks the calling thread inside `ps`. Safe only from a thread that is
  /// yours to block; see `offCooperativePool`.
  public func blockingIsRunning(inDirectory directory: URL) -> Bool? {
    // `-ww` because without it `ps` truncates each line to the terminal width,
    // and the part it cuts is the end — which on a deep path is the very
    // component that says which binary this is. This user's processes only: a
    // runner started by hand is this user's, and another account's command
    // line is a path anybody can write, which `Folder` may have to resolve.
    guard
      let listing = try? commandRunner.run(
        "/usr/bin/env",
        [Self.pinnedLocale, "/bin/ps", "-wwo", "command=", "-U", String(userID)]),
      listing.exitCode == 0
    else { return nil }

    let folder = Folder(directory)
    for line in listing.standardOutput.split(separator: "\n") {
      let command = line.trimmingCharacters(in: .whitespaces)
      if folder.launched(Self.listenerPath, in: command[...]) { return true }
      if command.hasPrefix(Self.helperInterpreter),
        folder.launched(
          Self.helperPath, in: command.dropFirst(Self.helperInterpreter.count))
      {
        return true
      }
    }
    return false
  }
}

extension ListenerProcessProbe {
  /// A runner directory under every name `ps` may print.
  ///
  /// `run.sh` finds itself with `cd -P`, so the listener runs from the physical
  /// path: links resolved, `/private` kept. Settings stores the standardized
  /// one, which keeps links and drops `/private`.
  fileprivate struct Folder {
    let stored: String
    let physical: String?

    init(_ directory: URL) {
      stored = directory.standardizedFileURL.path
      physical = Self.physical(stored)
    }

    /// Whether `command` runs the program at `relativePath` inside this folder.
    func launched(_ relativePath: String, in command: Substring) -> Bool {
      for found in command.ranges(of: "/" + relativePath) {
        // The whole path, then a boundary: a space or the end of the line.
        // Without it, a binary beside this one whose name merely begins the
        // same way would count as running.
        let rest = command[found.upperBound...]
        guard rest.isEmpty || rest.hasPrefix(" ") else { continue }
        if names(command[..<found.lowerBound]) { return true }
      }
      return false
    }

    /// Both sides through `realpath`, because either may be the one spelled
    /// through a link.
    private func names(_ root: Substring) -> Bool {
      if root == stored { return true }
      // Relative to a working directory this app cannot see; resolving it
      // from the app's own would name whatever folder that happens to be.
      guard let physical, root.hasPrefix("/") else { return false }
      // The spelling `run.sh` prints, so the usual match needs no lookup: a
      // `realpath` waits on whatever volume the path names.
      if root == physical { return true }
      return Self.physical(String(root)) == physical
    }

    private static func physical(_ path: String) -> String? {
      guard let resolved = realpath(path, nil) else { return nil }
      defer { free(resolved) }
      return String(cString: resolved)
    }
  }
}
