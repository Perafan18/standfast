import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
private let label = "actions.runner.acme-widget.build-mac"

@Test func aRunnerNobodyStartedIsShownExactlyAsResolved() {
  var window = SettlingWindow(duration: 30)
  for state: RunnerState in [.idle, .busy, .disconnected, .stopped, .unknown(.noAnswer)] {
    #expect(window.display(state, for: label, readBeganAt: epoch) == .resolved(state))
  }
}

@Test func disconnectedRightAfterAStartReadsAsStarting() {
  // The whole reason this type exists: the runner's process is up, GitHub has
  // not registered it yet, and the resolver — correctly, statelessly — calls
  // that a fault one second after the user pressed Start.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 1) == .starting)
  #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 29) == .starting)
}

@Test func aRunnerStillDisconnectedWhenTheWindowRunsOutIsReported() {
  // The benefit of the doubt is not indefinite. A runner that never registers
  // has a real problem, and after half a minute saying so is the useful thing.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(
    window.display(.disconnected, for: label, readBeganAt: epoch + 30)
      == .resolved(.disconnected))
}

@Test func aStartThatFailedIsNotDressedUpAsStarting() {
  // `svc.sh start` exits 0 even when the `launchctl load` under it failed, so
  // the re-probe finding the service down is the only report a failed start
  // ever produces. Swallowing it would leave "Starting…" on screen for the
  // whole window over a runner that never came up.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(
    window.display(.stopped, for: label, readBeganAt: epoch + 1) == .resolved(.stopped))
}

@Test func aReadingNobodyAnsweredLeavesTheWindowWhereItWas() {
  // GitHub rate limited, the network down, `launchctl` timing out: none of
  // them says the handshake finished or failed, so the registration that is
  // still under way a scan later is still the one being waited for.
  for reason: UnknownReason in [.rateLimited, .noAnswer, .serviceStateUnreadable] {
    var window = SettlingWindow(duration: 30)
    window.open(for: label, at: epoch)

    #expect(
      window.display(.unknown(reason), for: label, readBeganAt: epoch + 2)
        == .resolved(.unknown(reason)))
    #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 17) == .starting)
    #expect(window.settlingLabels == [label])
  }
}

@Test func anUnansweredReadingPastTheDeadlineStillSpendsTheWindow() {
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(
    window.display(.unknown(.noAnswer), for: label, readBeganAt: epoch + 30)
      == .resolved(.unknown(.noAnswer)))
  #expect(window.settlingLabels.isEmpty)
}

@Test func theWindowClosesAsSoonAsTheRunnerRegisters() {
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.idle, for: label, readBeganAt: epoch + 2) == .resolved(.idle))
  // A later disconnect is a real one: this runner already proved it can
  // register, so the handshake is not what is failing now.
  #expect(
    window.display(.disconnected, for: label, readBeganAt: epoch + 3)
      == .resolved(.disconnected))
}

@Test func closingTheWindowGivesBackTheResolvedState() {
  // What Stop does. Whatever the runner was settling towards, it is not that.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)
  window.close(for: label)

  #expect(
    window.display(.disconnected, for: label, readBeganAt: epoch + 1)
      == .resolved(.disconnected))
}

@Test func oneRunnerSettlingDoesNotCoverForAnother() {
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(
    window.display(.disconnected, for: "another.runner", readBeganAt: epoch + 1)
      == .resolved(.disconnected))
  #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 1) == .starting)
}

@Test func pruningForgetsRunnersThatAreGoneAndKeepsTheRest() {
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)
  window.open(for: "another.runner", at: epoch)

  window.keepOnly([label])

  #expect(window.settlingLabels == [label])
  #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 1) == .starting)
  #expect(
    window.display(.disconnected, for: "another.runner", readBeganAt: epoch + 1)
      == .resolved(.disconnected))
}

// MARK: - Readings older than the window

@Test func aReadingTakenBeforeTheWindowOpenedDoesNotSpendIt() {
  // A scan started before the click can land after it: `gh` alone is allowed
  // thirty seconds per runner. What that scan saw is the machine as it was
  // before anything happened, so letting it close the window would throw away
  // the benefit of the doubt on evidence that predates the doubt.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch + 10)

  #expect(window.display(.idle, for: label, readBeganAt: epoch) == .starting)
  // And the window is still there for the reading that comes after it.
  #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 11) == .starting)
}

@Test func aStaleReadingIsNotBelievedWhateverItSays() {
  // Not only `.idle`. Every state a scan can carry is a statement about a
  // machine that no longer exists once the user has acted on it.
  for state: RunnerState in [.idle, .busy, .disconnected, .stopped, .unknown(.noAnswer)] {
    var window = SettlingWindow(duration: 30)
    window.open(for: label, at: epoch + 10)
    #expect(window.display(state, for: label, readBeganAt: epoch + 9) == .starting)
    #expect(window.settlingLabels == [label])
  }
}

@Test func aReadingTakenAtTheInstantTheWindowOpenedStillCounts() {
  // The boundary is inclusive on purpose: a reading is stale when it is older
  // than the window, and one taken at the same instant is not older.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.idle, for: label, readBeganAt: epoch) == .resolved(.idle))
  #expect(window.settlingLabels.isEmpty)
}

@Test func reopeningExtendsTheWindowFromTheNewStart() {
  // Start, give up, start again: the second attempt gets its own full window
  // rather than the remains of the first.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)
  window.open(for: label, at: epoch + 20)

  #expect(window.display(.disconnected, for: label, readBeganAt: epoch + 40) == .starting)
}
