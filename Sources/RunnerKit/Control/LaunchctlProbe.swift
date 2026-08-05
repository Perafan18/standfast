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

  /// False also covers "could not tell" — launchd not answering and a service
  /// that is loaded but idle are the same picture from here, and `/bin/launchctl`
  /// missing would mean this is not a Mac.
  public func isRunning(label: String) -> Bool {
    guard let output = try? commandRunner.run("/bin/launchctl", ["list"])
    else { return false }

    for line in output.split(separator: "\n") {
      let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard columns.count == 3, columns[2] == label else { continue }
      // A pid or nothing: launchd writes "-" for a service it is not running,
      // and the header line puts the word "PID" here.
      return Int(columns[0]) != nil
    }
    return false
  }
}
