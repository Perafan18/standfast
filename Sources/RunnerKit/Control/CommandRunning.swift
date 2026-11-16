import Foundation

/// What a finished command left behind.
public struct CommandResult: Sendable {
  public let standardOutput: String
  /// 127 is "command not found", which is how a `gh` that is not on PATH
  /// announces itself — an app launched from Finder inherits a PATH without
  /// Homebrew on it. Without this, that is indistinguishable from a `gh` that
  /// ran and answered nothing.
  public let exitCode: Int32

  public init(standardOutput: String, exitCode: Int32) {
    self.standardOutput = standardOutput
    self.exitCode = exitCode
  }
}

public enum CommandError: Error {
  /// The executable is missing, is not executable, or the fork failed.
  ///
  /// The underlying error is kept whole for whoever has to explain this to a
  /// user. It does not currently separate "missing" from "not executable" —
  /// Foundation reports both as `NSFileNoSuchFileError` — so a diagnosis that
  /// needs that distinction has to stat the path itself.
  case couldNotLaunch(executable: String, underlying: any Error)
  /// Still running when the deadline passed, and signalled to death.
  case timedOut(executable: String)
}

/// The seam every external command goes through.
///
/// `launchctl`, `svc.sh`, `gh` and `du` are the external commands this app
/// invokes, and tests must not depend on any of them describing the host that
/// runs the suite. Keeping them behind one protocol makes those boundaries
/// deterministic and the state logic testable.
public protocol CommandRunning: Sendable {
  /// Throws only when the process could not be launched or would not finish;
  /// a non-zero exit comes back in the result for the caller to interpret.
  func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult
}

extension CommandRunning {
  public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    try run(executable, arguments, workingDirectory: nil)
  }
}

public struct ProcessCommandRunner: CommandRunning {
  private let timeout: TimeInterval
  private let terminationGrace: TimeInterval

  /// - Parameters:
  ///   - timeout: how long a command may take before it is signalled. `gh`
  ///     does network I/O, and a stalled connection would otherwise block the
  ///     calling thread for as long as the app lives.
  ///   - terminationGrace: how long SIGTERM gets to work before SIGKILL.
  public init(timeout: TimeInterval = 30, terminationGrace: TimeInterval = 2) {
    self.timeout = timeout
    self.terminationGrace = terminationGrace
  }

  public func run(
    _ executable: String, _ arguments: [String], workingDirectory: URL?
  ) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let workingDirectory { process.currentDirectoryURL = workingDirectory }

    let out = Pipe()
    process.standardOutput = out
    // Discarded rather than piped: nothing reads stderr, and an unread pipe
    // deadlocks the child once it fills.
    process.standardError = FileHandle.nullDevice
    // Nor is stdin inherited: a command that decides to prompt would sit
    // waiting on a terminal that, in a menu bar app, nobody is watching.
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw CommandError.couldNotLaunch(executable: executable, underlying: error)
    }

    let watchdog = Watchdog(process)
    watchdog.arm(timeout: timeout, terminationGrace: terminationGrace)

    // Drain concurrently, but let the direct child decide when the command is
    // finished. A descendant it spawned can inherit stdout and delay EOF
    // indefinitely; it must not keep a completed or timed-out command (and
    // the thread waiting on it) hanging around.
    let output = ProcessOutputCollector(out.fileHandleForReading)
    process.waitUntilExit()
    let data = output.finish()

    if watchdog.disarm() { throw CommandError.timedOut(executable: executable) }
    // Lossy decoding on purpose: one stray byte turning a whole `launchctl
    // list` into an empty string would report every runner as stopped.
    return CommandResult(
      standardOutput: String(decoding: data, as: UTF8.self),
      exitCode: process.terminationStatus)
  }
}

/// Collects stdout without letting EOF define the lifetime of the command.
///
/// `availableData` returns each chunk as it arrives, which keeps a chatty
/// child from filling the pipe while the caller waits for that child itself.
/// After the direct child exits, a brief grace lets bytes it had already put
/// in the pipe land here. A descendant still holding the pipe after that is
/// not this command finishing late; waiting for it was the hang.
private final class ProcessOutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private let finished = DispatchSemaphore(value: 0)
  private var data = Data()

  init(_ handle: FileHandle) {
    Thread.detachNewThread { [self] in
      autoreleasepool {
        while true {
          let chunk = handle.availableData
          guard !chunk.isEmpty else { break }
          lock.lock()
          data.append(chunk)
          lock.unlock()
        }
        finished.signal()
      }
    }
  }

  func finish() -> Data {
    _ = finished.wait(timeout: .now() + .milliseconds(100))
    lock.lock()
    defer { lock.unlock() }
    return data
  }
}

/// Signals the child only while it is still ours to signal. Once `run()` has
/// reaped the process its pid can be recycled, and killing it then would hit
/// a stranger.
private final class Watchdog: @unchecked Sendable {
  private let lock = NSLock()
  private let disarmed = DispatchSemaphore(value: 0)
  private let process: Process
  private var reaped = false
  private var fired = false

  init(_ process: Process) { self.process = process }

  /// Keeps deadlines independent from the global dispatch pool. The command
  /// itself is blocking work and several concurrent commands can occupy that
  /// pool on older runtimes; scheduling their watchdogs behind them defeats
  /// the timeout precisely when it is needed most.
  func arm(timeout: TimeInterval, terminationGrace: TimeInterval) {
    Thread.detachNewThread { [self] in
      autoreleasepool {
        guard disarmed.wait(timeout: .now() + timeout) == .timedOut else { return }
        terminate()
        guard disarmed.wait(timeout: .now() + terminationGrace) == .timedOut else { return }
        forceKill()
      }
    }
  }

  func terminate() { whileAlive { process.terminate() } }

  func forceKill() { whileAlive { kill(process.processIdentifier, SIGKILL) } }

  /// Stops the watchdog and reports whether it had already gone off.
  func disarm() -> Bool {
    lock.lock()
    reaped = true
    let didFire = fired
    lock.unlock()
    disarmed.signal()
    return didFire
  }

  private func whileAlive(_ signalIt: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !reaped, process.isRunning else { return }
    fired = true
    signalIt()
  }
}
