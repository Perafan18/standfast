import Foundation

/// What GitHub thinks of one runner: whether it is connected, and whether it
/// has a job. Two independent facts, and this type deliberately constrains
/// neither — offline-and-busy is what a machine that died mid-job looks like,
/// so callers have to decide which of the two to lead with rather than assume
/// the combination cannot arise.
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
  /// Blocks the calling thread while it asks GitHub, for as long as whatever is
  /// underneath allows — thirty seconds through `ProcessCommandRunner`. Named
  /// so that both sides know: an implementer may block, and a caller must have
  /// a thread it is allowed to block. That rules out the main actor and the
  /// cooperative pool behind every `Task`.
  ///
  /// There is no async facade on this protocol on purpose. The one caller is
  /// `RunnerStateResolver`, whose whole job is to compose this answer with the
  /// local probe synchronously and hop once, in `state(for:)`, for both.
  func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus
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
  private let found = FoundLocation()

  /// Remembers which candidate answered, so the search happens once instead of
  /// once per question.
  ///
  /// Shared between copies of the struct on purpose: the client is created per
  /// use in places, and a cache that reset with every copy would not be one. It
  /// is only ever an optimisation — losing it costs two failed spawns, and a
  /// wrong answer is impossible, because a remembered location that no longer
  /// works simply falls through to the full search again.
  private final class FoundLocation: @unchecked Sendable {
    private let lock = NSLock()
    private var location: GHLocation?

    var current: GHLocation? {
      lock.lock()
      defer { lock.unlock() }
      return location
    }

    func remember(_ new: GHLocation) {
      lock.lock()
      defer { lock.unlock() }
      location = new
    }
  }

  /// Where to look for `gh`, in order.
  ///
  /// PATH first, because a `gh` from mise, nix or asdf is a deliberate choice
  /// of installation and configuration. Authentication still follows `gh`'s
  /// own precedence, including token environment variables inherited by this
  /// process; no executable location proves which credentials it will use.
  /// The two Homebrew prefixes follow because PATH is usually not enough:
  /// `launchctl getenv PATH` is empty on a stock Mac, so an .app opened from
  /// Finder runs with `/usr/bin:/bin:/usr/sbin:/sbin` and cannot see a brew
  /// install at all.
  /// Without this fallback the app's default state, for most users, is a
  /// permanent "gh is not installed" about a gh that is installed.
  ///
  /// The search runs once and the winner is remembered. That matters more than
  /// it looks: on exactly the machines the fallback exists for, PATH fails
  /// *every* time, so an unremembered search would spend a doomed spawn on
  /// every question, for every runner, on every refresh — not once.
  public static let standardLocations = [
    GHLocation(executable: "/usr/bin/env", leadingArguments: ["gh"]),
    GHLocation(executable: "/opt/homebrew/bin/gh"),
    GHLocation(executable: "/usr/local/bin/gh"),
  ]

  /// Asks for the two fields the menu needs as one line, so the answer needs
  /// no JSON parsing. Note the spaces inside it: this is a single argument.
  static let statusFilter = #".status + " " + (.busy|tostring)"#

  /// Where the newest published runner is announced. A public repository, so
  /// this needs no more credentials than the status call beside it — but it is
  /// still an API call against the same rate limit, which is why nothing calls
  /// it on the refresh loop.
  static let latestReleasePath = "repos/actions/runner/releases/latest"

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

  public func blockingRunnerStatus(id: Int, scope: RunnerScope) throws -> RemoteStatus {
    // By id, not by list position: `.runners[0]` reported whichever runner the
    // API happened to list first, so a second runner on the same repository
    // silently shadowed this one.
    let arguments = ["api", scope.runnerAPIPath(id: id), "--jq", Self.statusFilter]
    return try status(from: answer(to: arguments))
  }

  /// Runs `gh` wherever it is on this Mac, and remembers what answered.
  ///
  /// Whatever worked last time is tried first. On the machine this app is aimed
  /// at — Homebrew gh, launched from Finder — the search ends at the second
  /// candidate, so without the memory every question from every runner on every
  /// refresh would pay for a spawn that is known in advance to fail.
  private func answer(to arguments: [String]) throws -> CommandResult {
    if let remembered = found.current, let result = try attempt(remembered, arguments) {
      return result
    }
    // Either nothing was remembered, or gh has moved or been uninstalled since.
    // Either way the search below overwrites the memory with whatever answers
    // now, so there is nothing to clear first.
    for location in locations {
      guard let result = try attempt(location, arguments) else { continue }
      found.remember(location)
      return result
    }
    throw GitHubError.cliUnavailable
  }

  /// Nil when there is no `gh` at this location. A result — of any exit code —
  /// means one ran, and its answer is the final one.
  private func attempt(
    _ location: GHLocation, _ arguments: [String]
  ) throws -> CommandResult? {
    do {
      let result = try commandRunner.run(location.executable, location.command(arguments))
      // Nothing at this path. Keep looking.
      return result.exitCode == Self.commandNotFound ? nil : result
    } catch let failure as CommandError {
      switch failure {
      // No such executable: this prefix does not exist on this Mac.
      case .couldNotLaunch: return nil
      // It is installed, it just did not finish. Trying the remaining
      // candidates would spend the whole timeout again for the same silence.
      case .timedOut: throw GitHubError.noAnswer
      }
    }
  }

  private func status(from result: CommandResult) throws -> RemoteStatus {
    guard result.exitCode != Self.authenticationRequired else {
      throw GitHubError.notAuthenticated
    }
    // The exit code, never stdout, is what says whether there is an answer at
    // all: `gh api` responds to an API error by printing the raw JSON body and
    // ignoring `--jq`. This is not a precaution against something hypothetical.
    // The measured 404 body begins `{"message":"Not Found",` — and because
    // "Not Found" has a space in it, the raw body splits into exactly two
    // fields. Without this check a 404 parses cleanly, today, into
    // `online: false, busy: false`, and the menu shows a perfectly healthy
    // repository as a disconnected runner.
    guard result.exitCode == 0 else { throw GitHubError.noAnswer }

    let fields = result.standardOutput
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: " ")
    // The status is checked against both spellings rather than read as
    // "online, or else offline", because there is no safe way to guess at a
    // third one. Treating an unrecognised status as online hides a runner that
    // will never be sent work — the exact failure `.disconnected` exists to
    // surface — and treating it as offline raises the alarm about a healthy
    // one. "Could not tell" is the only honest answer, and this app already
    // has the vocabulary for it.
    guard
      fields.count == 2,
      fields[0] == "online" || fields[0] == "offline",
      fields[1] == "true" || fields[1] == "false"
    else {
      throw GitHubError.noAnswer
    }
    return RemoteStatus(online: fields[0] == "online", busy: fields[1] == "true")
  }
}

extension GHCommandLineClient: RunnerReleaseChecking {
  public func blockingLatestRunnerRelease() throws -> RunnerVersion {
    let result = try answer(to: ["api", Self.latestReleasePath, "--jq", ".tag_name"])
    guard result.exitCode != Self.authenticationRequired else {
      throw GitHubError.notAuthenticated
    }
    // The same trap as the status call: `gh api` answers an API error by
    // printing the raw JSON body and ignoring `--jq` entirely, so the exit code
    // is the only thing that says whether there is an answer here at all. A
    // body is not a version and would not parse, but relying on that would be
    // relying on GitHub never publishing a release named after its own error.
    guard result.exitCode == 0, let version = RunnerVersion(result.standardOutput) else {
      throw GitHubError.noAnswer
    }
    return version
  }
}
