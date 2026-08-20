import Foundation
import Testing

@testable import RunnerKit

// What gitlab-runner actually writes, sub-tables and all.
private let realistic = """
  concurrent = 1
  check_interval = 0
  connection_max_age = "15m0s"

  [session_server]
    session_timeout = 1800

  [[runners]]
    id = 17373720
    name = "mac-mini-m4-gitlab"
    url = "https://gitlab.com"
    token = "glrt-SECRET"
    executor = "shell"
    [runners.custom_build_dir]
    [runners.cache]
      MaxUploadedArchiveSize = 0

  [[runners]]
    id = 42
    name = "second"
    url = "https://gitlab.example.com/"
    token = "glrt-OTHER"
    executor = "shell"
  """

@Test func readsEveryRunnerTheFileDeclares() throws {
  let entries = try GitLabRunnerConfigFile.entries(in: realistic)

  #expect(entries.map(\.id) == [17_373_720, 42])
  #expect(entries.map(\.name) == ["mac-mini-m4-gitlab", "second"])
  #expect(entries.map(\.instanceHost) == ["gitlab.com", "gitlab.example.com"])
}

@Test func theTokenStaysInTheFile() throws {
  // The entry deliberately has nowhere to put it. This app asks GitLab with
  // its own token from the Keychain; the runner's credential can start jobs,
  // and carrying it around in memory to answer a question nobody asks with it
  // would be all risk and no reader.
  let mirror = Mirror(reflecting: try GitLabRunnerConfigFile.entries(in: realistic)[0])

  #expect(!mirror.children.contains { "\(String(describing: $0.value))".contains("glrt-") })
}

@Test func keysInsideSubTablesDoNotLeakIntoTheRunner() throws {
  // `[runners.cache]` and friends nest under a runner, and a line scanner that
  // did not track sections would happily read their keys as the runner's own.
  let nested = """
    [[runners]]
      id = 7
      name = "real"
      url = "https://gitlab.com"
      [runners.docker]
        name = "not-the-runner-name"
    """

  #expect(try GitLabRunnerConfigFile.entries(in: nested).map(\.name) == ["real"])
}

@Test func aRunnerWithoutAnIdIsSkippedAndNamed() throws {
  // Written by gitlab-runner before 15.0, or edited by hand. Without the id
  // there is no way to ask the API about *this* runner — the same rule
  // `.runner` files follow — and dropping it silently would hide a runner the
  // file plainly declares.
  let old = """
    [[runners]]
      name = "pre-15"
      url = "https://gitlab.com"

    [[runners]]
      id = 9
      name = "modern"
      url = "https://gitlab.com"
    """

  let file = try GitLabRunnerConfigFile.reading(old)
  #expect(file.entries.map(\.id) == [9])
  #expect(file.skipped == ["pre-15"])
}

@Test func anUnparseableUrlSkipsTheRunnerRatherThanInventingAHost() throws {
  let broken = """
    [[runners]]
      id = 9
      name = "where"
      url = "not a url"
    """

  let file = try GitLabRunnerConfigFile.reading(broken)
  #expect(file.entries.isEmpty)
  #expect(file.skipped == ["where"])
}

@Test func aRunnerWithoutANameStillHasAnIdentity() throws {
  let nameless = """
    [[runners]]
      id = 9
      url = "https://gitlab.com"
    """

  let entries = try GitLabRunnerConfigFile.entries(in: nameless)
  #expect(entries.map(\.name) == [""])
}
