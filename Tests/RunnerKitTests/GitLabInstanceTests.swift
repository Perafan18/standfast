import Foundation
import Testing

@testable import RunnerKit

@Test func anInstanceKeepsItsSchemePortAndPath() throws {
  // A self-managed GitLab on its own port, under a relative URL root, over
  // http on a lab network, or at an IPv6 literal. Keeping only the host asks
  // some other server about every one of them.
  let selfManaged = """
    [[runners]]
      id = 1
      url = "https://gitlab.corp.example:8443/"
    [[runners]]
      id = 2
      url = "https://example.com/gitlab/"
    [[runners]]
      id = 3
      url = "http://10.0.0.5:8080"
    [[runners]]
      id = 4
      url = "https://[fd00::10]/"
    """

  let instances = try GitLabRunnerConfigFile.entries(in: selfManaged).map(\.instance)

  #expect(
    instances.map(\.baseURL.absoluteString) == [
      "https://gitlab.corp.example:8443", "https://example.com/gitlab",
      "http://10.0.0.5:8080", "https://[fd00::10]",
    ])
  #expect(
    instances.map(\.name) == [
      "gitlab.corp.example:8443", "example.com/gitlab", "http://10.0.0.5:8080",
      "[fd00::10]",
    ])
}

@Test func theRunnerQuestionGoesUnderTheInstancesOwnPath() throws {
  let instance = try #require(GitLabInstance(url: "http://gitlab.lan:8080/gitlab/"))

  #expect(
    instance.runnerURL(id: 7).absoluteString
      == "http://gitlab.lan:8080/gitlab/api/v4/runners/7")
}

@Test func oneInstanceIsOneInstanceHoweverItIsSpelled() {
  // The identity keys the token, so an explicit default port or a capital
  // letter must not turn one instance into two.
  #expect(
    GitLabInstance(url: "https://GitLab.com:443/")
      == GitLabInstance(url: "https://gitlab.com"))
  #expect(GitLabInstance(url: "https://gitlab.com")?.name == "gitlab.com")
}

@Test func credentialsWrittenIntoTheUrlAreNotCarriedAround() {
  let instance = GitLabInstance(url: "https://user:secret@gitlab.com/?private_token=x#top")

  #expect(instance?.baseURL.absoluteString == "https://gitlab.com")
}

@Test func onlyWebAddressesWithAHostAreInstances() {
  #expect(GitLabInstance(url: "gitlab.com") == nil)
  #expect(GitLabInstance(url: "ftp://gitlab.com") == nil)
  #expect(GitLabInstance(url: "https://") == nil)
  #expect(GitLabInstance(url: "not a url") == nil)
}
