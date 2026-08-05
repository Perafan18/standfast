import Foundation
import RunnerKit
import Testing

@testable import RunnerMenubar

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
private let label = "actions.runner.acme-widget.build-mac"

@Test func aRunnerNobodyStartedIsShownExactlyAsResolved() {
  var window = SettlingWindow(duration: 30)
  for state: RunnerState in [.idle, .busy, .disconnected, .stopped, .unknown(.noAnswer)] {
    #expect(window.display(state, for: label, at: epoch) == .resolved(state))
  }
}

@Test func disconnectedRightAfterAStartReadsAsStarting() {
  // The whole reason this type exists: the runner's process is up, GitHub has
  // not registered it yet, and the resolver — correctly, statelessly — calls
  // that a fault one second after the user pressed Start.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.disconnected, for: label, at: epoch + 1) == .starting)
  #expect(window.display(.disconnected, for: label, at: epoch + 29) == .starting)
}

@Test func aRunnerStillDisconnectedWhenTheWindowRunsOutIsReported() {
  // The benefit of the doubt is not indefinite. A runner that never registers
  // has a real problem, and after half a minute saying so is the useful thing.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(
    window.display(.disconnected, for: label, at: epoch + 30)
      == .resolved(.disconnected))
}

@Test func aStartThatFailedIsNotDressedUpAsStarting() {
  // `svc.sh start` exits 0 even when the `launchctl load` under it failed, so
  // the re-probe finding the service down is the only report a failed start
  // ever produces. Swallowing it would leave "Starting…" on screen for the
  // whole window over a runner that never came up.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.stopped, for: label, at: epoch + 1) == .resolved(.stopped))
}

@Test func theWindowClosesAsSoonAsTheRunnerRegisters() {
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.idle, for: label, at: epoch + 2) == .resolved(.idle))
  // A later disconnect is a real one: this runner already proved it can
  // register, so the handshake is not what is failing now.
  #expect(
    window.display(.disconnected, for: label, at: epoch + 3) == .resolved(.disconnected))
}

@Test func closingTheWindowGivesBackTheResolvedState() {
  // What Stop does. Whatever the runner was settling towards, it is not that.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)
  window.close(for: label)

  #expect(
    window.display(.disconnected, for: label, at: epoch + 1) == .resolved(.disconnected))
}

@Test func oneRunnerSettlingDoesNotCoverForAnother() {
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)

  #expect(window.display(.disconnected, for: "another.runner", at: epoch + 1)
    == .resolved(.disconnected))
  #expect(window.display(.disconnected, for: label, at: epoch + 1) == .starting)
}

@Test func reopeningExtendsTheWindowFromTheNewStart() {
  // Start, give up, start again: the second attempt gets its own full window
  // rather than the remains of the first.
  var window = SettlingWindow(duration: 30)
  window.open(for: label, at: epoch)
  window.open(for: label, at: epoch + 20)

  #expect(window.display(.disconnected, for: label, at: epoch + 40) == .starting)
}
