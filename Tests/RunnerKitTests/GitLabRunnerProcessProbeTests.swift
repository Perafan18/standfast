import Foundation
import Testing

@testable import RunnerKit

// Pinned as a literal: the argument list is what keeps other accounts'
// processes out, so it must not be built from the code under test.
private let psCommand = ["/bin/ps", "-wwo", "command=", "-U", "501"]

private func probe(_ output: String, exitCode: Int32 = 0) -> GitLabRunnerProcessProbe {
  let fake = FakeCommandRunner([psCommand: output])
  fake.exitCodes[psCommand] = exitCode
  return GitLabRunnerProcessProbe(commandRunner: fake, userID: 501)
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

@Test func theServiceStartedWithGlobalOptionsIsFound() {
  // GitLab's documented way to debug a runner is `gitlab-runner --debug run`:
  // global options come before the subcommand, and that service takes jobs.
  for command in [
    "/opt/homebrew/bin/gitlab-runner --debug run",
    "gitlab-runner --log-level debug run --config /Users/ci/.gitlab-runner/config.toml",
    "gitlab-runner --log-format=json run",
  ] {
    #expect(probe(command + "\n").blockingIsRunning() == true, "\(command)")
  }
}

@Test func aGlobalOptionsValueIsNotTheSubcommand() {
  let table = """
    gitlab-runner --debug register
    gitlab-runner --log-level run verify
    """

  #expect(probe(table).blockingIsRunning() == false)
}
