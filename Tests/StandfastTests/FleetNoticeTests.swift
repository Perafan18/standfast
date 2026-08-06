import Foundation
import RunnerKit
import Testing

@testable import Standfast

private func runner(_ name: String) -> DiscoveredRunner {
  DiscoveredRunner(
    label: "actions.runner.acme-widget.\(name)",
    directory: URL(fileURLWithPath: "/tmp/\(name)"),
    agentId: 7, agentName: name, scope: .repository(owner: "acme", name: "widget"))
}

private let plist = URL(
  fileURLWithPath: "/Users/someone/Library/LaunchAgents/actions.runner.a.b.plist")

@Test func aCleanMacIsToldToInstallARunner() {
  // Not an error. Nothing was found because nothing is there, and the answer
  // is to install one rather than to go fixing something.
  #expect(FleetNotice.resolving(runners: [], unreadable: []) == .noRunnersInstalled)
}

@Test func nothingFoundButSomethingUnreadableIsADifferentAnswer() {
  // Runners are installed; this app could not read them. Telling this user to
  // install a runner is the one reply guaranteed to be useless.
  #expect(
    FleetNotice.resolving(runners: [], unreadable: [plist]) == .unreadable([plist]))
}

@Test func theUnreadableNoticeCarriesThePathsAndNotACount() {
  // A plist duplicated in Finder describes one runner and lands here twice, so
  // any number this app printed would be one it made up. The paths are also
  // the only thread the user has to pull on.
  let copied = plist.deletingLastPathComponent()
    .appendingPathComponent("actions.runner.a.b copy.plist")

  #expect(
    FleetNotice.resolving(runners: [], unreadable: [plist, copied])
      == .unreadable([plist, copied]))
}

@Test func runnersThatDidResolveDoNotHideTheOnesThatDidNot() {
  // Two runners installed, one plist corrupt: the menu shows one row and would
  // otherwise say nothing at all about the other, which is a runner silently
  // missing from a menu whose whole job is to list them.
  #expect(
    FleetNotice.resolving(runners: [runner("build-mac")], unreadable: [plist])
      == .unreadable([plist]))
}

@Test func aHealthyMacGetsNoNoticeAtAll() {
  #expect(FleetNotice.resolving(runners: [runner("build-mac")], unreadable: []) == nil)
}
