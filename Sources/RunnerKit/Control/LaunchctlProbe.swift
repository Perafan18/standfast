import Foundation

/// Asks launchd whether a runner's service is alive.
///
/// Preferred over parsing `svc.sh status` for its output text: the label comes
/// straight from the LaunchAgent we already read, and `launchctl list` prints
/// a stable three-column table rather than prose.
public struct LaunchctlProbe: Sendable {
  private let commandRunner: any CommandRunning

  public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
    self.commandRunner = commandRunner
  }

  /// Whether launchd is running this label, or nil when it could not be asked.
  ///
  /// Nil rather than false, because the two have opposite consequences. A
  /// `launchctl list` that timed out or would not launch says nothing about the
  /// runner, and folding it into "not running" draws a live runner as stopped —
  /// with Stop and Restart greyed out, which is the shape of bug this app has
  /// already been bitten by once. The caller has a vocabulary for "could not
  /// tell" and is the one that should use it.
  ///
  /// Blocks the calling thread inside `launchctl` for up to the command
  /// runner's timeout — thirty seconds by default. Safe to call directly only
  /// from a thread that is yours to block, which rules out the main actor and
  /// the cooperative pool behind every `Task`. `RunnerStateResolver.state(for:)`
  /// is the async route that makes the hop for you; see `offCooperativePool`.
  public func blockingIsRunning(label: String) -> Bool? {
    guard
      let listing = try? commandRunner.run("/bin/launchctl", ["list"]),
      listing.exitCode == 0
    else { return nil }

    for line in listing.standardOutput.split(separator: "\n") {
      let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard columns.count == 3, columns[2] == label else { continue }
      // A pid or nothing: launchd writes "-" for a service it is not running,
      // and the header line puts the word "PID" here.
      return Int(columns[0]) != nil
    }
    return false
  }
}
