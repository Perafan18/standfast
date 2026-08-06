import Foundation
import Testing

@testable import Standfast

/// Lets the main queue run whatever the monitor's `receive(on:)` put on it.
///
/// Deterministic rather than a sleep: the main queue is FIFO, so a block
/// enqueued after the monitor's cannot run before it.
@MainActor
private func drainMainQueue() async {
  await withCheckedContinuation { resume in
    DispatchQueue.main.async { resume.resume() }
  }
}

// MARK: - What the menu says, and when it says nothing

@Test func aCoolMacGetsNoLineInTheMenu() {
  // The reason this is worth having at all is that it only appears when it
  // means something. A row that reads "thermal state: nominal" is true every
  // day of the year and useful on none of them.
  #expect(ThermalNotice.lines(pressure: .none, overrunning: false).isEmpty)
  #expect(ThermalNotice.lines(pressure: .none, overrunning: true).isEmpty)
}

@Test func aThrottledMacSaysSo() {
  #expect(ThermalNotice.lines(pressure: .serious, overrunning: false).count == 1)
  #expect(ThermalNotice.lines(pressure: .critical, overrunning: false).count == 1)
  #expect(
    ThermalNotice.lines(pressure: .serious, overrunning: false)
      != ThermalNotice.lines(pressure: .critical, overrunning: false))
}

@Test func theTemperatureExplainsTheOverrunItIsCausing() {
  // The whole value of the line, and why it is crossed with v0.2's estimate
  // rather than merely printed near it: a job that normally takes 2m50s and is
  // at 6 minutes reads as something broken, and this is what turns it back into
  // something explainable.
  let quiet = ThermalNotice.lines(pressure: .serious, overrunning: false)
  let slow = ThermalNotice.lines(pressure: .serious, overrunning: true)

  #expect(slow.count == quiet.count + 1)
  #expect(slow.first == quiet.first)
  #expect(slow.last == L10n.thermalSlowingJobs)
}

@Test func aStateThisVersionDoesNotRecogniseSaysNothing() {
  // `ProcessInfo.ThermalState` is a system enum that may grow. Folding an
  // unread case into `.critical` puts the loudest line in the menu over
  // something nobody has looked up the meaning of.
  #expect(!ThermalPressure.unrecognised.isLimiting)
  #expect(ThermalNotice.lines(pressure: .unrecognised, overrunning: true).isEmpty)
}

@Test func fansSpinningUpIsNotAProblemWorthReporting() {
  // `.fair` means the machine is working, which is what a runner is for.
  #expect(ThermalPressure(.nominal) == .none)
  #expect(ThermalPressure(.fair) == .none)
  #expect(ThermalPressure(.serious) == .serious)
  #expect(ThermalPressure(.critical) == .critical)
}

// MARK: - Watching the machine

@Test @MainActor func theMonitorStartsFromWhateverTheMacIsDoingNow() {
  // A Mac already throttling when the app opens has to say so at the first
  // menu, not at the first change — which on a machine sitting at `.serious`
  // could be an hour away.
  let reporter = FakeThermalReporter(.critical)

  let monitor = ThermalMonitor(reporter: reporter, center: NotificationCenter())

  #expect(monitor.pressure == .critical)
}

@Test @MainActor func theMonitorFollowsTheMachineRatherThanPollingIt() async {
  // Subscribed rather than read on the fifteen-second scan: macOS posts on
  // every change, so there is nothing to add to the scan and nothing to pay for
  // in between.
  let center = NotificationCenter()
  let reporter = FakeThermalReporter(.none)
  let monitor = ThermalMonitor(reporter: reporter, center: center)
  #expect(monitor.pressure == .none)

  reporter.set(.serious)
  center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
  await drainMainQueue()

  #expect(monitor.pressure == .serious)
}

@Test @MainActor func aChangeNobodyAnnouncedDoesNotMoveTheReading() async {
  // The reading is only ever re-taken on the notification. A monitor that
  // recomputed on every access would be right here and would also have made the
  // subscription above pointless — and this is what tells the two apart.
  let center = NotificationCenter()
  let reporter = FakeThermalReporter(.none)
  let monitor = ThermalMonitor(reporter: reporter, center: center)

  reporter.set(.critical)
  await drainMainQueue()

  #expect(monitor.pressure == .none)
}
