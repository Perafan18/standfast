import Testing

@testable import RunnerKit

/// Shaped like the real thing: a header, tab separators, and `-` in the PID
/// column for services launchd knows about but is not running.
private let listing = """
  PID\tStatus\tLabel
  870\t0\tactions.runner.acme-widget.build-mac
  -\t0\tactions.runner.acme-widget.spare-mac
  -\t1\tcom.example.crashed
  """

private func probe(_ output: String = listing) -> LaunchctlProbe {
  LaunchctlProbe(commandRunner: FakeCommandRunner(["/bin/launchctl list": output]))
}

@Test func reportsRunningWhenTheLabelHasAPID() {
  #expect(probe().isRunning(label: "actions.runner.acme-widget.build-mac"))
}

@Test func reportsNotRunningWhenThePIDIsADash() {
  // Loaded but not running: launchctl prints "-" where the PID goes.
  #expect(probe().isRunning(label: "actions.runner.acme-widget.spare-mac") == false)
}

/// Nothing about the label in the listing means not running, whether launchd
/// answered with other services, with a bare header, or with nothing at all.
@Test(arguments: ["", "PID\tStatus\tLabel", listing])
func reportsNotRunningWhenTheListingDoesNotMentionTheLabel(listed: String) {
  #expect(probe(listed).isRunning(label: "actions.runner.nope") == false)
}

@Test func matchesTheWholeLabelAndNothingLess() {
  // Two runners on one machine differ by a suffix, and neither containment
  // nor a prefix test can tell them apart.
  let listed = "PID\tStatus\tLabel\n99\t0\tactions.runner.acme-widget.build-mac-2"
  #expect(probe(listed).isRunning(label: "actions.runner.acme-widget.build-mac") == false)
  #expect(probe().isRunning(label: "actions.runner.acme-widget.build-mac-2") == false)
}

@Test func asksLaunchctlForTheWholeList() {
  let fake = FakeCommandRunner(["/bin/launchctl list": listing])
  _ = LaunchctlProbe(commandRunner: fake).isRunning(label: "whatever")
  #expect(fake.invocations == [
    .init(executable: "/bin/launchctl", arguments: ["list"], workingDirectory: nil)
  ])
}

@Test func reportsNotRunningWhenLaunchctlCannotBeLaunched() {
  let fake = FakeCommandRunner()
  fake.failingExecutables = ["/bin/launchctl"]
  #expect(LaunchctlProbe(commandRunner: fake).isRunning(label: "anything") == false)
}

@Test func keepsReadingPastALineItCannotParse() {
  // A truncated line must not end the scan: the runner being asked about may
  // still be further down the table.
  let listed = """
    PID\tStatus\tLabel
    truncated
    870\t0\tactions.runner.acme-widget.build-mac
    """
  #expect(probe(listed).isRunning(label: "actions.runner.acme-widget.build-mac"))
}

@Test func onlyAnActualPIDCountsAsRunning() {
  // Anything that is not a number in that column means launchd is not
  // reporting a live process, whatever else it means.
  let listed = "PID\tStatus\tLabel\n\t0\tactions.runner.acme-widget.build-mac"
  #expect(probe(listed).isRunning(label: "actions.runner.acme-widget.build-mac") == false)
}
