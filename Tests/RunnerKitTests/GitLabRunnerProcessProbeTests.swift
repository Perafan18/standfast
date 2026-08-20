import Foundation
import Testing

@testable import RunnerKit

private let psCommand = ["/bin/ps", "-Awwo", "command="]

private func probe(_ output: String, exitCode: Int32 = 0) -> GitLabRunnerProcessProbe {
  let fake = FakeCommandRunner([psCommand: output])
  fake.exitCodes[psCommand] = exitCode
  return GitLabRunnerProcessProbe(commandRunner: fake)
}

@Test func theServiceRunningIsFound() {
  // What `gitlab-runner install && gitlab-runner start` leaves in the process
  // table. One process serves every [[runners]] entry in config.toml, which is
  // why this probe takes no argument: the answer is per machine, not per
  // runner.
  let table = """
    /opt/homebrew/bin/gitlab-runner run --working-directory /Users/ci/ --config /Users/ci/.gitlab-runner/config.toml
    /usr/sbin/cfprefsd agent
    """

  #expect(probe(table).blockingIsRunning() == true)
}

@Test func aMachineWithoutTheServiceIsNotRunning() {
  #expect(probe("/usr/sbin/cfprefsd agent\n").blockingIsRunning() == false)
}

@Test func otherGitLabRunnerCommandsAreNotTheService() {
  // `register`, `verify`, `list` — all real invocations somebody may have in a
  // terminal right now, none of them the long-lived process that takes jobs.
  let table = """
    /opt/homebrew/bin/gitlab-runner verify
    /opt/homebrew/bin/gitlab-runner register --url https://gitlab.com
    grep gitlab-runner run
    """

  #expect(probe(table).blockingIsRunning() == false)
}

@Test func aBinaryWhoseNameMerelyContainsTheWordIsNotIt() {
  // A wrapper somebody wrote, or this app's own helper scripts.
  let table = """
    /Users/ci/bin/my-gitlab-runner-wrapper run
    /Users/ci/gitlab-runner-backup/gitlab-runner-old run
    """

  #expect(probe(table).blockingIsRunning() == false)
}

@Test func aListingThatFailedSaysNothingRatherThanNo() {
  #expect(probe("", exitCode: 1).blockingIsRunning() == nil)
}
