import Testing

@testable import RunnerKit

private let repositoryScope = RunnerScope.repository(owner: "acme", name: "widget")
private let runnerPath = "repos/acme/widget/actions/runners/21"

/// Built the same way the client builds it, from the same constant, so a test
/// cannot key its canned answer on a filter that is never sent. The `--jq`
/// filter is one argument with spaces inside it, and a fake keyed on a joined
/// string would silently match nothing and return "no answer" for every test.
private func ghArguments(_ path: String) -> [String] {
  ["api", path, "--jq", GHCommandLineClient.statusFilter]
}

private func onPath(_ path: String = runnerPath) -> [String] {
  ["/usr/bin/env", "gh"] + ghArguments(path)
}

private func atHomebrew(_ path: String = runnerPath) -> [String] {
  ["/opt/homebrew/bin/gh"] + ghArguments(path)
}

private func atIntelHomebrew(_ path: String = runnerPath) -> [String] {
  ["/usr/local/bin/gh"] + ghArguments(path)
}

private func ask(_ fake: FakeCommandRunner, scope: RunnerScope = repositoryScope) throws
  -> RemoteStatus
{
  try GHCommandLineClient(commandRunner: fake).runnerStatus(id: 21, scope: scope)
}

// MARK: - Reading a status

@Test func asksAboutTheRunnerByItsOwnId() throws {
  // The bug this replaces: `.runners[0]` reported whichever runner GitHub
  // listed first, so a second runner registered on the same repository
  // silently shadowed the one being displayed.
  let fake = FakeCommandRunner([onPath(): "online true\n"])

  #expect(try ask(fake) == RemoteStatus(online: true, busy: true))
  // Pins the whole argument list, not just the id: the endpoint that lists
  // runners and the one that fetches a single runner differ only by a suffix.
  #expect(fake.invocations.map(\.arguments) == [["gh"] + ghArguments(runnerPath)])
}

@Test func sendsTheFilterThatMakesGhPrintTheTwoFieldsThisClientParses() throws {
  // Pinned as a literal, deliberately not built from the constant under test.
  // Every other test keys its canned answer off `statusFilter`, so all of them
  // would keep passing if the filter turned into something gh renders
  // differently — the parsing below would simply never meet real gh output
  // again. This is the one place the jq contract is nailed down.
  //
  // Measured against gh 2.89.0: this filter prints "online false" for a
  // registered, idle runner.
  let fake = FakeCommandRunner([onPath(): "online true\n"])
  _ = try ask(fake)

  #expect(
    fake.invocations.first?.arguments == [
      "gh", "api", "repos/acme/widget/actions/runners/21",
      "--jq", #".status + " " + (.busy|tostring)"#,
    ])
}

@Test func readsAnOnlineRunnerThatIsNotBusy() throws {
  let fake = FakeCommandRunner([onPath(): "online false\n"])
  #expect(try ask(fake) == RemoteStatus(online: true, busy: false))
}

@Test func readsAnOfflineRunner() throws {
  let fake = FakeCommandRunner([onPath(): "offline false\n"])
  #expect(try ask(fake) == RemoteStatus(online: false, busy: false))
}

@Test func asksTheEndpointThatMatchesTheScope() throws {
  let path = "orgs/acme/actions/runners/21"
  let command = ["/usr/bin/env", "gh"] + ghArguments(path)
  let fake = FakeCommandRunner([command: "online true\n"])
  let status = try ask(fake, scope: .organization("acme"))

  #expect(status == RemoteStatus(online: true, busy: true))
}

// MARK: - Finding gh at all

@Test func fallsBackToHomebrewWhenGhIsNotOnPath() throws {
  // Measured on macOS 27: `launchctl getenv PATH` is empty, so an .app opened
  // from Finder inherits /usr/bin:/bin:/usr/sbin:/sbin and never sees
  // /opt/homebrew/bin. `/usr/bin/env gh` then exits 127 with an empty stdout.
  // Since this app ships as a double-clicked .app and gh is a brew install for
  // almost everyone, that is the default case, not an edge case — reporting
  // "gh is not installed" to someone who has gh installed is a dead end.
  let fake = FakeCommandRunner([atHomebrew(): "online true\n"])
  fake.exitCodes = [onPath(): 127]

  #expect(try ask(fake) == RemoteStatus(online: true, busy: true))
  #expect(fake.invocations.map(\.executable) == ["/usr/bin/env", "/opt/homebrew/bin/gh"])
}

@Test func fallsBackToTheIntelHomebrewPrefix() throws {
  // An Intel Mac has no /opt/homebrew at all, so that candidate does not exit
  // 127 — it fails to launch.
  let fake = FakeCommandRunner([atIntelHomebrew(): "offline false\n"])
  fake.exitCodes = [onPath(): 127]
  fake.failingExecutables = ["/opt/homebrew/bin/gh"]

  #expect(try ask(fake) == RemoteStatus(online: false, busy: false))
  #expect(
    fake.invocations.map(\.executable)
      == ["/usr/bin/env", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"])
}

@Test func prefersWhateverIsOnPathOverTheKnownPrefixes() throws {
  // A gh from mise, nix or asdf is on PATH and nowhere near Homebrew. The
  // known prefixes are a fallback, never an override.
  let fake = FakeCommandRunner([
    onPath(): "online false\n",
    atHomebrew(): "online true\n",
  ])

  #expect(try ask(fake) == RemoteStatus(online: true, busy: false))
  #expect(fake.invocations.map(\.executable) == ["/usr/bin/env"])
}

@Test func reportsGhMissingOnlyAfterEveryCandidateHasBeenTried() {
  let fake = FakeCommandRunner()
  fake.exitCodes = [onPath(): 127]
  fake.failingExecutables = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

  #expect(throws: GitHubError.cliUnavailable) { try ask(fake) }
  #expect(fake.invocations.count == 3)
}

@Test func aTimedOutGhIsNotRetriedAtEveryOtherPath() {
  // A gh that hung is installed; walking the remaining candidates would spend
  // the whole timeout again to be told the same thing.
  let fake = FakeCommandRunner()
  fake.timingOutExecutables = ["/usr/bin/env"]

  #expect(throws: GitHubError.noAnswer) { try ask(fake) }
  #expect(fake.invocations.count == 1)
}

// MARK: - gh ran and did not answer

@Test func reportsAnUnauthenticatedGhSeparately() {
  // Measured: `gh api` with no credentials exits 4 with an empty stdout and
  // prints "please run: gh auth login" on stderr, which this app discards. 4
  // is gh's own auth exit code; if it ever changed, this falls through to
  // noAnswer, which costs a vaguer message rather than a wrong one.
  let fake = FakeCommandRunner()
  fake.exitCodes = [onPath(): 4]

  #expect(throws: GitHubError.notAuthenticated) { try ask(fake) }
  // And it settles the question. gh's credentials live in a config directory
  // shared by every copy on the machine, so a second binary would refuse in
  // exactly the same way.
  #expect(fake.invocations.count == 1)
}

@Test func doesNotReadAnAPIErrorBodyAsAStatus() {
  // Measured on a 404: `gh api` prints the raw JSON body on stdout, ignoring
  // --jq entirely, and exits 1. This is not a hypothetical hazard. Because
  // "Not Found" carries a space, that body splits into exactly two fields, so
  // without the exit-code check it parses today into online: false, busy:
  // false — and a repository that is merely misspelled, or a token missing a
  // scope, is drawn in the menu as a disconnected runner.
  //
  // The documentation_url is elided for width; the leading message is the part
  // that does the damage.
  let notFound = #"{"message":"Not Found","status":"404"}"#
  let fake = FakeCommandRunner([onPath(): notFound])
  fake.exitCodes = [onPath(): 1]

  #expect(throws: GitHubError.noAnswer) { try ask(fake) }
  // One refusal is the answer; the other candidates are the same gh.
  #expect(fake.invocations.count == 1)
}

@Test func neverParsesTheOutputOfACommandThatFailed() {
  // Deliberately the strongest possible input: stdout that is a flawless
  // status, on a command that failed. The rule is that a non-zero exit ends
  // the matter, and it has to hold on its own rather than leaning on the
  // status whitelist below happening to reject today's error bodies — that
  // overlap is a coincidence of what GitHub's JSON starts with, not a design.
  let fake = FakeCommandRunner([onPath(): "online true\n"])
  fake.exitCodes = [onPath(): 1]

  #expect(throws: GitHubError.noAnswer) { try ask(fake) }
}

@Test func treatsOutputThatIsNotAStatusAsNoAnswer() {
  // Keyed explicitly rather than left to the fake's empty default, so a filter
  // mismatch cannot make this pass for the wrong reason.
  let fake = FakeCommandRunner([onPath(): "online\n"])

  #expect(throws: GitHubError.noAnswer) { try ask(fake) }
}

@Test func refusesAnAnswerWithMoreFieldsThanAStatus() {
  let fake = FakeCommandRunner([onPath(): "online false extra\n"])

  #expect(throws: GitHubError.noAnswer) { try ask(fake) }
}

@Test func refusesAStatusItDoesNotRecognise() {
  // There is no safe way to guess. Reading an unknown status as online would
  // hide a runner that will never be sent work, which is the failure
  // `.disconnected` exists to catch; reading it as offline would raise the
  // alarm about a healthy one. Both are worse than admitting ignorance.
  let fake = FakeCommandRunner([onPath(): "quarantined false\n"])

  #expect(throws: GitHubError.noAnswer) { try ask(fake) }
}

@Test func doesNotMistakeAnUnknownStatusForAHealthyRunner() {
  // The direction that matters. Stated separately from the test above because
  // it is the invariant, not the mechanism: whatever this client does with an
  // unrecognised status, it must never come back saying the runner is online.
  let fake = FakeCommandRunner([onPath(): "provisioning true\n"])

  #expect((try? ask(fake))?.online != true)
}

// MARK: - Finding gh once

@Test func remembersWhereItFoundGhInsteadOfSearchingEveryTime() throws {
  // On the machine this fallback exists for, PATH fails every single time.
  // Searching per question would spend a doomed spawn on every runner on every
  // refresh, for as long as the app is open.
  let fake = FakeCommandRunner([atHomebrew(): "online true\n"])
  fake.exitCodes = [onPath(): 127]
  let client = GHCommandLineClient(commandRunner: fake)

  _ = try client.runnerStatus(id: 21, scope: repositoryScope)
  _ = try client.runnerStatus(id: 21, scope: repositoryScope)

  #expect(
    fake.invocations.map(\.executable)
      == ["/usr/bin/env", "/opt/homebrew/bin/gh", "/opt/homebrew/bin/gh"])
}

@Test func searchesAgainWhenTheRememberedGhStopsWorking() throws {
  // Homebrew upgrades and uninstalls happen while the app is running. A
  // remembered location is an optimisation, never a commitment.
  let fake = FakeCommandRunner([
    atHomebrew(): "online true\n", onPath(): "offline false\n",
  ])
  fake.exitCodes = [onPath(): 127]
  let client = GHCommandLineClient(commandRunner: fake)
  _ = try client.runnerStatus(id: 21, scope: repositoryScope)

  // gh leaves /opt/homebrew and lands back on PATH.
  fake.failingExecutables = ["/opt/homebrew/bin/gh"]
  fake.exitCodes = [:]

  #expect(
    try client.runnerStatus(id: 21, scope: repositoryScope)
      == RemoteStatus(online: false, busy: false))
}
