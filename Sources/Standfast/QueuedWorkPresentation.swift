import Foundation
import RunnerKit

/// What this app knows about the work queued for one runner.
///
/// Three states, not two, because "nobody asked" and "nothing is waiting" are
/// different facts and only one of them is reassuring.
enum QueuedWorkKnowledge: Equatable {
  /// Asked and answered.
  case work(QueuedWork)
  /// GitHub has no endpoint that answers this for this runner's scope —
  /// organisation and enterprise runners. Not an empty queue.
  case notAvailableHere
  /// Not asked. The runner is busy, or the fleet is on the `gh` path where a
  /// runner's labels never arrive, so there is nothing to match work against.
  case notAsked
}

/// The line about work waiting for one runner, and nil when there is nothing
/// worth saying.
struct QueuedWorkPresentation: Equatable {
  let line: String
  let tone: StateTone

  /// - Parameter display: what the runner's state is, which decides both
  ///   whether an empty queue is worth mentioning and whether a full one is an
  ///   alarm.
  static func building(
    _ knowledge: QueuedWorkKnowledge, runnerLabelled labels: [String],
    display: DisplayState
  ) -> Self? {
    // Whoever is looking at a runner that cannot take work is asking what that
    // is costing them. Deliberately not `needsAttention`: a runner somebody
    // stopped on purpose raises no alarm and still will not pick up the job
    // waiting for it, which is exactly the case worth naming. Everywhere else,
    // silence is the right amount to say.
    let asking = !display.canReceiveWork

    switch knowledge {
    case .notAsked:
      return nil

    case .notAvailableHere:
      // Said only where it matters. On every healthy organisation runner it
      // would be a permanent apology; on a stopped one it stops the operator
      // concluding from silence that nothing is piling up.
      return asking ? Self(line: L10n.queueUnknownScope, tone: .neutral) : nil

    case .work(let queue):
      // Without labels there is nothing to attribute the queue to. A stopped
      // runner never reaches GitHub — the local probe answers first — so this
      // is not a corner case: it is the state of every runner somebody turned
      // off, and "no work is waiting" there would be a claim assembled out of
      // an absence of evidence.
      guard !labels.isEmpty else { return nil }
      let waiting = queue.waiting(forRunnerLabelled: labels)
      guard !waiting.isEmpty else {
        return asking ? Self(line: L10n.queueEmpty, tone: .neutral) : nil
      }
      return Self(
        line: text(waiting.count, isPartial: queue.isPartial),
        // A healthy idle runner with matching work queued is a machine about
        // to start: GitHub dispatches within seconds. Colouring that red would
        // cry wolf on every ordinary morning. A stopped or disconnected one is
        // the opposite — the work is not going anywhere.
        tone: asking ? .attention : .neutral)
    }
  }

  private static func text(_ count: Int, isPartial: Bool) -> String {
    if isPartial { return L10n.queueWaitingPartial(count) }
    return count == 1 ? L10n.queueWaitingOne : L10n.queueWaiting(count)
  }
}
