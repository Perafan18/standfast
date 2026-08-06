import Foundation
import RunnerKit

/// Remembers which runners were started a moment ago, so the gap between a
/// runner's process coming up and GitHub acknowledging it does not read as a
/// failure.
///
/// The gap is real and it is seconds wide. `svc.sh start` returns as soon as
/// launchd has loaded the agent, but the runner still has to open its long
/// poll and register, and until it does `launchctl` says running while GitHub
/// says it has never heard of this machine. The resolver reports that,
/// correctly, as `.disconnected` — a fault, arriving immediately after the
/// user did exactly the right thing. `ServiceController.restart` makes it
/// worse: it waits 1.5s, which is launchd's requirement, not GitHub's, so a
/// restart lands inside the gap nearly every time.
///
/// The resolver cannot fix this itself. It is stateless on purpose and a
/// half-registered runner is byte for byte a runner whose token expired last
/// week. This type is the piece that saw the click.
///
/// A value type with the clock handed in, so all of it is testable without
/// waiting for anything.
struct SettlingWindow: Sendable {
  /// Long enough for a slow registration over a slow link; short enough that a
  /// runner which is genuinely never coming back says so within half a minute.
  static let defaultDuration: TimeInterval = 30

  private var deadlines: [String: Date] = [:]
  private let duration: TimeInterval

  init(duration: TimeInterval = defaultDuration) { self.duration = duration }

  /// Opened once the start command has returned, never when the button was
  /// pressed. `restart` takes the service down first, and a refresh landing in
  /// that gap would find a perfectly real `.stopped` and close a window that
  /// had not yet done anything.
  mutating func open(for label: String, at now: Date) {
    deadlines[label] = now.addingTimeInterval(duration)
  }

  /// Whatever this runner was settling towards, it is not that any more.
  mutating func close(for label: String) { deadlines[label] = nil }

  /// Forgets runners that are no longer installed. `display` clears a deadline
  /// as soon as it reads one, so the only entries that can outlive their
  /// runner belong to a runner that stopped being discovered.
  mutating func keepOnly(_ labels: Set<String>) {
    deadlines = deadlines.filter { labels.contains($0.key) }
  }

  /// The runners currently being given the benefit of the doubt.
  var settlingLabels: Set<String> { Set(deadlines.keys) }

  /// Reads one runner's state as the menu should show it.
  ///
  /// Only `.disconnected` is held back, and only until anything else arrives.
  /// `.stopped` in particular goes straight through: `svc.sh start` exits 0
  /// even when the `launchctl load` underneath it failed, so a re-probe
  /// finding the service down is the only report a failed start will ever
  /// produce, and swallowing it would leave the user watching "Starting…"
  /// until the window ran out.
  mutating func display(_ state: RunnerState, for label: String, at now: Date)
    -> DisplayState
  {
    guard let deadline = deadlines[label] else { return .resolved(state) }
    guard state == .disconnected, now < deadline else {
      // Either the handshake finished, or it failed, or it has had long
      // enough. All three end the benefit of the doubt.
      deadlines[label] = nil
      return .resolved(state)
    }
    return .starting
  }
}
