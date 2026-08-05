import Foundation

/// What GitHub thinks of one runner. Two independent facts: a runner can be
/// online and idle, online and busy, or offline — but never offline and busy.
public struct RemoteStatus: Equatable, Sendable {
  public let online: Bool
  public let busy: Bool

  public init(online: Bool, busy: Bool) {
    self.online = online
    self.busy = busy
  }
}

/// Why GitHub could not be asked. Separate cases because the fix differs, and
/// a menu bar app that says only "could not tell" leaves the user with nothing
/// to try.
public enum GitHubError: Error, Equatable {
  /// No `gh` on PATH and none at the usual install prefixes. Fix: install it.
  case cliUnavailable
  /// `gh` is installed but holds no credentials. Fix: `gh auth login`.
  case notAuthenticated
  /// `gh` ran, was authenticated, and still produced nothing usable: no
  /// network, a runner GitHub no longer knows about, a token without the scope
  /// for this endpoint, or a rate limit.
  case noAnswer
}

public protocol GitHubClient: Sendable {
  func runnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus
}

/// One way to reach `gh`: an executable plus whatever has to precede the
/// arguments. `/usr/bin/env` needs the tool's name as its first argument; an
/// absolute path needs nothing.
public struct GHLocation: Equatable, Sendable {
  public let executable: String
  public let leadingArguments: [String]

  public init(executable: String, leadingArguments: [String] = []) {
    self.executable = executable
    self.leadingArguments = leadingArguments
  }

  func command(_ arguments: [String]) -> [String] { leadingArguments + arguments }
}

/// Talks to GitHub through the `gh` CLI, borrowing whatever credentials the
/// user already set up. v1.0 adds a token-in-Keychain client behind this same
/// protocol for people who do not use `gh`.
public struct GHCommandLineClient: GitHubClient {
  private let commandRunner: any CommandRunning
  private let locations: [GHLocation]

  /// Where to look for `gh`, in order.
  ///
  /// PATH first, because a `gh` from mise, nix or asdf is a deliberate choice
  /// and the only one that will have the right credentials. The two Homebrew
  /// prefixes follow because PATH is usually not enough: `launchctl getenv
  /// PATH` is empty on a stock Mac, so an .app opened from Finder runs with
  /// `/usr/bin:/bin:/usr/sbin:/sbin` and cannot see a brew install at all.
  /// Without this fallback the app's default state, for most users, is a
  /// permanent "gh is not installed" about a gh that is installed.
  ///
  /// Probing costs at most two extra `posix_spawn` calls that fail
  /// immediately, and only on machines where PATH did not work.
  public static let standardLocations = [
    GHLocation(executable: "/usr/bin/env", leadingArguments: ["gh"]),
    GHLocation(executable: "/opt/homebrew/bin/gh"),
    GHLocation(executable: "/usr/local/bin/gh"),
  ]

  /// Asks for the two fields the menu needs as one line, so the answer needs
  /// no JSON parsing. Note the spaces inside it: this is a single argument.
  static let statusFilter = #".status + " " + (.busy|tostring)"#

  /// Exit 127 is the shell's "command not found", which is how `/usr/bin/env`
  /// reports a `gh` that is not on PATH. Exit 4 is gh's own code for missing
  /// credentials. Neither is reported any other way — stdout is empty for
  /// both, and stderr is discarded.
  private static let commandNotFound: Int32 = 127
  private static let authenticationRequired: Int32 = 4

  public init(
    commandRunner: any CommandRunning = ProcessCommandRunner(),
    locations: [GHLocation] = GHCommandLineClient.standardLocations
  ) {
    self.commandRunner = commandRunner
    self.locations = locations
  }

  public func runnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    // By id, not by list position: `.runners[0]` reported whichever runner the
    // API happened to list first, so a second runner on the same repository
    // silently shadowed this one.
    let arguments = ["api", scope.runnerAPIPath(id: id), "--jq", Self.statusFilter]

    for location in locations {
      do {
        let result = try commandRunner.run(location.executable, location.command(arguments))
        // Nothing at this path either. Keep looking.
        if result.exitCode == Self.commandNotFound { continue }
        return try status(from: result)
      } catch let failure as CommandError {
        switch failure {
        // No such executable: this prefix does not exist on this Mac.
        case .couldNotLaunch: continue
        // It is installed, it just did not finish. Trying the remaining
        // candidates would spend the whole timeout again for the same silence.
        case .timedOut: throw GitHubError.noAnswer
        }
      }
    }
    throw GitHubError.cliUnavailable
  }

  private func status(from result: CommandResult) throws -> RemoteStatus {
    guard result.exitCode != Self.authenticationRequired else {
      throw GitHubError.notAuthenticated
    }
    // The exit code, never stdout, is what says whether there is an answer at
    // all: `gh api` responds to an API error by printing the raw JSON body and
    // ignoring `--jq`. That body carries a "status" field, so a filter applied
    // to it would render a 404 as the perfectly parseable "404 null".
    guard result.exitCode == 0 else { throw GitHubError.noAnswer }

    let fields = result.standardOutput
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ")
    guard fields.count == 2 else { throw GitHubError.noAnswer }
    return RemoteStatus(online: fields[0] == "online", busy: fields[1] == "true")
  }
}
