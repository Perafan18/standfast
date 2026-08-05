import Foundation

public enum CommandError: Error, Equatable {
  /// The executable is missing, is not executable, or the fork failed. The
  /// payload is the path that was attempted, which is the only part of this a
  /// user can act on.
  case couldNotLaunch(String)
}

/// The seam every external command goes through.
///
/// `launchctl`, `svc.sh` and `gh` are the whole of this app's contact with the
/// system, and none of them exist on a machine running the test suite. Keeping
/// them behind one protocol is what makes the state logic testable at all.
public protocol CommandRunning: Sendable {
  /// Returns stdout. Throws only when the process could not be launched at
  /// all; a non-zero exit is the caller's business to interpret.
  func run(_ executable: String, _ arguments: [String], workingDirectory: URL?) throws
    -> String
}

extension CommandRunning {
  public func run(_ executable: String, _ arguments: [String]) throws -> String {
    try run(executable, arguments, workingDirectory: nil)
  }
}

public struct ProcessCommandRunner: CommandRunning {
  public init() {}

  public func run(_ executable: String, _ arguments: [String], workingDirectory: URL?)
    throws -> String
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let workingDirectory { process.currentDirectoryURL = workingDirectory }

    let out = Pipe()
    process.standardOutput = out
    // Discarded rather than piped: nothing reads stderr, and an unread pipe
    // deadlocks the child once it fills.
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw CommandError.couldNotLaunch(executable)
    }
    // Drain before waiting: a child that fills the pipe buffer blocks forever
    // if we wait first.
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
  }
}
