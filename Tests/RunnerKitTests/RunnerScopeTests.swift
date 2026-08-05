import Testing

@testable import RunnerKit

@Test func parsesRepositoryScope() {
  let scope = RunnerScope(gitHubURL: "https://github.com/acme/widget-factory")
  #expect(scope == .repository(owner: "acme", name: "widget-factory"))
}

@Test func repositoryNamesMayContainDashes() {
  // The LaunchAgent label collapses owner and repo into one dashed string;
  // this is why the URL is the source of truth and the label is not.
  let scope = RunnerScope(gitHubURL: "https://github.com/Perafan18/nest-rules-app")
  #expect(scope == .repository(owner: "Perafan18", name: "nest-rules-app"))
}

@Test func parsesOrganizationScope() {
  #expect(RunnerScope(gitHubURL: "https://github.com/acme") == .organization("acme"))
}

@Test func parsesEnterpriseScope() {
  #expect(
    RunnerScope(gitHubURL: "https://github.com/enterprises/acme-corp")
      == .enterprise("acme-corp"))
}

@Test func rejectsUnrecognisedURLs() {
  #expect(RunnerScope(gitHubURL: "https://github.com/a/b/c/d") == nil)
  #expect(RunnerScope(gitHubURL: "") == nil)
}

@Test func rejectsStringsThatAreNotWebURLs() {
  // Counting path components is not enough: plenty of junk splits into two
  // parts. This initialiser is failable so that junk stops here, rather than
  // becoming a scope that builds plausible-looking API paths for nothing.
  #expect(RunnerScope(gitHubURL: "n/a") == nil)
  #expect(RunnerScope(gitHubURL: "git@github.com:acme/widget.git") == nil)
  #expect(RunnerScope(gitHubURL: "/Users/ci/actions-runner") == nil)
}

@Test func buildsAPIPathForEachScope() {
  #expect(
    RunnerScope.repository(owner: "acme", name: "w").runnerAPIPath(id: 4)
      == "repos/acme/w/actions/runners/4")
  #expect(
    RunnerScope.organization("acme").runnerAPIPath(id: 4)
      == "orgs/acme/actions/runners/4")
  #expect(
    RunnerScope.enterprise("acme").runnerAPIPath(id: 4)
      == "enterprises/acme/actions/runners/4")
}

@Test func buildsSettingsURLForEachScope() {
  #expect(
    RunnerScope.repository(owner: "acme", name: "w").settingsURL.absoluteString
      == "https://github.com/acme/w/settings/actions/runners")
  #expect(
    RunnerScope.organization("acme").settingsURL.absoluteString
      == "https://github.com/organizations/acme/settings/actions/runners")
  #expect(
    RunnerScope.enterprise("acme").settingsURL.absoluteString
      == "https://github.com/enterprises/acme/settings/actions/runners")
}
