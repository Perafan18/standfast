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
  /// job rather than the connection, and not `run.sh`, which is the shell that
  /// starts one and exits.
  static let listenerPath = "bin/Runner.Listener"

  private let commandRunner: any CommandRunning

  public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
    self.commandRunner = commandRunner
  }

  /// Whether a listener is running out of this directory, or nil when the
  /// process table could not be read.
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
    // component that says which binary this is.
    guard
      let listing = try? commandRunner.run("/bin/ps", ["-Awwo", "command="]),
      listing.exitCode == 0
    else { return nil }

    let wanted =
      directory.standardizedFileURL.path
      .appending("/")
      .appending(Self.listenerPath)
    for line in listing.standardOutput.split(separator: "\n") {
      let command = line.trimmingCharacters(in: .whitespaces)
      // The whole path, then a boundary. A bare `hasPrefix` would call this
      // listener running because a differently-named binary beside it is —
      // one whose own name merely begins the same way. The space or the end of
      // the line after the executable is what makes it the same binary.
      guard command.hasPrefix(wanted) else { continue }
      let rest = command.dropFirst(wanted.count)
      if rest.isEmpty || rest.hasPrefix(" ") { return true }
    }
    return false
  }
}
