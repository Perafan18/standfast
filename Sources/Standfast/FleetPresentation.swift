import Foundation
import RunnerKit

enum StateTone: Equatable, Sendable {
  case healthy, active, attention, stopped, neutral
}

// Everything the menu shows, as values a test can read: one runner's state,
// one runner's row, the notice's lines, and the single state the icon carries.
// The views in `App.swift` render these and decide nothing.

/// What one runner's row shows.
///
/// Deliberately not a `RunnerState`. `.starting` is not a state the resolver
/// can ever return: the resolver is stateless and per-runner by design, and
/// what separates a runner that is still registering from one that will never
/// register is the fact that somebody pressed a button three seconds ago.
/// Only the app knows that, so only the app can name this case.
enum DisplayState: Equatable, Sendable {
  case resolved(RunnerState)
  /// Started moments ago; GitHub has not acknowledged it yet.
  case starting

  /// Nil while settling, which is what keeps a runner mid-handshake out of the
  /// menu bar summary instead of counted as the fault it currently looks like.
  var resolvedState: RunnerState? {
    if case .resolved(let state) = self { return state }
    return nil
  }
}

extension DisplayState {
  var shortSummary: String {
    switch self {
    case .resolved(.idle): L10n.stateReadyShort
    case .resolved(.busy): L10n.stateRunningShort
    case .resolved(.disconnected): L10n.stateDisconnectedShort
    case .resolved(.stopped): L10n.stateStoppedShort
    // Named, not shrugged. The long sentence has had a stable grammar for the
    // two layers since D-R16 — "running locally, GitHub not answering" — while
    // the badge beside it said `Unknown` for both, which is the half of UI-034
    // that stayed open. The badge now says which layer went quiet, in the same
    // words the sentence uses.
    case .resolved(.unknown(.serviceStateUnreadable)): L10n.stateLayerLocalUnreadable
    // "Not answering" would be a small lie for these two: nothing was asked in
    // the first, and GitHub answered very clearly in the second. The badge says
    // what its own sentence says, which is the rule `everyUnknownSentence…`
    // pins in both catalogues.
    case .resolved(.unknown(.noToken)): L10n.stateLayerGitHubNotAsked
    case .resolved(.unknown(.rateLimited)): L10n.stateLayerGitHubRateLimited
    case .resolved(.unknown(.gitLabNoToken)): L10n.stateLayerGitLabNotAsked
    case .resolved(.unknown(.gitLabNotAuthenticated)):
      L10n.stateLayerGitLabRefusedToken
    case .resolved(.unknown(.gitLabRateLimited)): L10n.stateLayerGitLabRateLimited
    case .resolved(.unknown(.gitLabSilent)): L10n.stateLayerGitLabSilent
    case .resolved(.unknown(.managedFleetWaiting)): L10n.stateLayerManagedFleetWaiting
    case .resolved(.unknown(.managedFleetStatusUnavailable)):
      L10n.stateLayerManagedFleetUnavailable
    case .resolved(.unknown(.tokenRefused)): L10n.stateLayerGitHubRefusedToken
    case .resolved(.unknown(.tokenUnreadable)): L10n.stateLayerGitHubNotAsked
    case .resolved(.unknown(.gitLabTokenUnreadable)): L10n.stateLayerGitLabNotAsked
    case .resolved(.unknown(.gitLabInsecure)): L10n.stateLayerGitLabNotAsked
    case .resolved(.unknown(.gitLabPaused)): L10n.stateLayerGitLabPaused
    case .resolved(.unknown): L10n.stateLayerGitHubSilent
    case .starting: L10n.stateStartingShort
    }
  }

  var tone: StateTone {
    switch self {
    case .resolved(.idle): .healthy
    case .resolved(.busy), .resolved(.unknown(.managedFleetWaiting)), .starting: .active
    case .resolved(.disconnected), .resolved(.unknown): .attention
    case .resolved(.stopped): .stopped
    }
  }

  var needsAttention: Bool {
    switch self {
    case .resolved(.unknown(.managedFleetWaiting)): false
    case .resolved(.disconnected), .resolved(.unknown): true
    default: false
    }
  }

  /// The icon carries the state, because that is the whole point of living in
  /// the menu bar: the answer should be readable without a click.
  var symbolName: String {
    switch self {
    case .resolved(.idle): "checkmark.circle"
    case .resolved(.busy): "gearshape.2.fill"
    case .resolved(.disconnected): "exclamationmark.triangle"
    case .resolved(.stopped): "moon.zzz"
    case .resolved(.unknown(.managedFleetWaiting)): "arrow.triangle.2.circlepath"
    case .resolved(.unknown): "questionmark.circle"
    case .starting: "arrow.triangle.2.circlepath"
    }
  }

  var summary: String {
    switch self {
    case .resolved(.idle): L10n.stateIdle
    case .resolved(.busy): L10n.stateBusy
    case .resolved(.disconnected): L10n.stateDisconnected
    case .resolved(.stopped): L10n.stateStopped
    case .resolved(.unknown(.cliUnavailable)): L10n.stateUnknownNoCLI
    case .resolved(.unknown(.notAuthenticated)): L10n.stateUnknownNotAuthenticated
    case .resolved(.unknown(.noAnswer)): L10n.stateUnknownNoAnswer
    case .resolved(.unknown(.noToken)): L10n.stateUnknownNoToken
    case .resolved(.unknown(.rateLimited)): L10n.stateUnknownRateLimited
    case .resolved(.unknown(.gitLabNoToken)): L10n.stateUnknownGitLabNoToken
    case .resolved(.unknown(.gitLabNotAuthenticated)):
      L10n.stateUnknownGitLabNotAuthenticated
    case .resolved(.unknown(.gitLabRateLimited)): L10n.stateUnknownGitLabRateLimited
    case .resolved(.unknown(.gitLabSilent)): L10n.stateUnknownGitLabSilent
    case .resolved(.unknown(.serviceStateUnreadable)): L10n.stateUnknownNoLocalAnswer
    case .resolved(.unknown(.managedFleetWaiting)): L10n.stateUnknownManagedFleetWaiting
    case .resolved(.unknown(.managedFleetStatusUnavailable)):
      L10n.stateUnknownManagedFleetUnavailable
    case .resolved(.unknown(.tokenRefused)): L10n.stateUnknownTokenRefused
    case .resolved(.unknown(.tokenUnreadable)): L10n.stateUnknownTokenUnreadable
    case .resolved(.unknown(.gitLabTokenUnreadable)):
      L10n.stateUnknownGitLabTokenUnreadable
    case .resolved(.unknown(.gitLabInsecure)): L10n.stateUnknownGitLabInsecure
    case .resolved(.unknown(.gitLabPaused)): L10n.stateUnknownGitLabPaused
    case .starting: L10n.stateStarting
    }
  }

  /// `summary` for one runner, where the sentence names who was asked: GitLab
  /// rather than GitHub for the remote half, and `ps` rather than `launchctl`
  /// for a local half read from the process list.
  func summary(for runner: DiscoveredRunner) -> String {
    switch self {
    case .resolved(.disconnected):
      if case .gitLab = runner.scope { return L10n.stateDisconnectedGitLab }
    case .resolved(.unknown(.serviceStateUnreadable)):
      switch runner.installation {
      case .manual, .gitLabService: return L10n.stateUnknownNoLocalAnswerProcess
      case .launchAgent, .managedFleet: break
      }
    default: break
    }
    return summary
  }

  /// Whether GitHub can hand this runner work right now.
  ///
  /// Not the same question as `needsAttention`, and the difference is the whole
  /// point: a runner somebody stopped on purpose is not an alarm, but it is
  /// still a runner that will not take the job waiting for it. Busy counts as
  /// yes — it is connected and will take the next one. `.starting` counts as
  /// yes so a restart does not raise an alarm about work it is about to claim.
  var canReceiveWork: Bool {
    switch self {
    case .resolved(.idle), .resolved(.busy), .starting: true
    case .resolved(.disconnected), .resolved(.stopped), .resolved(.unknown): false
    }
  }

  /// Whether this runner's LaunchAgent is loaded, which is the only fact the
  /// buttons need.
  ///
  /// Every case but `.stopped` was reached through a `launchctl` that answered
  /// yes: the resolver short-circuits to `.stopped` when the agent is not
  /// loaded, so even `.unknown` — where it is GitHub that went quiet, not the
  /// process — means the service is up.
  ///
  /// The one case that is a guess is `.unknown(.serviceStateUnreadable)`, where
  /// `launchctl` itself is what did not answer. It is guessed *this* way on
  /// purpose: a running runner drawn as stopped loses Stop and Restart, which
  /// is the button bug this unit was written to prevent, while a stopped one
  /// drawn as running merely offers a Stop that does nothing. Enabling all
  /// three instead would mean a row where Start and Stop are lit at once, and
  /// a menu that offers both is a menu that has stopped claiming to know.
  private var isServiceRunning: Bool { self != .resolved(.stopped) }

  /// Read off *this* runner, never off the menu bar summary.
  ///
  /// The summary of one idle runner and one stopped runner is `.idle`, which
  /// is right for the icon and disastrous for a button: gating Start on it
  /// leaves the stopped runner with no way to be started, ever.
  var canStart: Bool { !isServiceRunning }
  var canStop: Bool { isServiceRunning }
  /// Restart is Stop-then-Start, so it needs something to stop. A stopped
  /// runner has Start for that, and offering both would be two buttons for
  /// one outcome.
  var canRestart: Bool { isServiceRunning }
}

/// One runner's slice of the menu, as data.
///
/// Pulled out of the view on purpose. Every bug this unit was written to
/// prevent was a wiring bug — an action gated on the fleet summary, a name
/// read from the wrong field, a count printed instead of a list — and a
/// `View` body is the one thing in this app a test cannot make an assertion
/// about. The view below renders this and decides nothing.
struct RunnerRow: Equatable {
  let title: String
  /// What this runner is building and how long it has been at it, and nil when
  /// it is not building anything.
  let progress: String?
  /// The last requested service-operation outcome, if there is one to report.
  let operation: ServiceOperationPresentation?
  let actions: [Action]
  /// The jobs before this one, newest first.
  let recentJobs: [RecentJob]

  struct Action: Equatable {
    let kind: Kind
    let label: String
    let isEnabled: Bool

    enum Kind: Hashable, CaseIterable {
      case start, stop, restart, openOnGitHub
    }
  }

  /// One finished job. Carries its own identity rather than being rendered by
  /// its text: two runs of the same job that took the same time produce the
  /// same line, and `ForEach` over repeated identifiers is undefined. A start
  /// time is unique per runner because a runner runs one job at a time.
  struct RecentJob: Equatable, Identifiable {
    let id: Date
    let text: String
  }

  /// How many finished jobs the menu lists.
  ///
  /// Five: enough to see whether the last few builds went through, few enough
  /// that the submenu they live in is one glance rather than a scroll. This is
  /// a menu bar, not a log viewer — past five the question is one for GitHub's
  /// own run list, which "Open on GitHub" is two rows above.
  static let recentJobsShown = 5

  func action(_ kind: Action.Kind) -> Action? { actions.first { $0.kind == kind } }
}

extension RunnerSnapshot {
  /// The names carried by more than one runner on this machine.
  ///
  /// `config.sh` proposes the hostname as the runner's name and nearly
  /// everybody presses enter, so one Mac registered against two repositories
  /// arrives here as two runners called `mac-mini-m4` — two identical rows,
  /// each with its own four buttons, and no way to tell which is which. That is
  /// the likeliest multi-runner setup there is, which makes it the one this has
  /// to answer for.
  ///
  /// A question about the fleet, and unanswerable from one runner: whether a
  /// name identifies anything depends entirely on the others. Nothing else
  /// about a row works this way — every button is still read off its own
  /// runner's state, which is what stops a stopped runner from being made
  /// unstartable by a busy neighbour.
  static func repeatedNames(among runners: [DiscoveredRunner]) -> Set<String> {
    let counts = runners.reduce(into: [String: Int]()) { counts, runner in
      counts[runner.displayName, default: 0] += 1
    }
    return Set(counts.filter { $0.value > 1 }.keys)
  }

  /// What each runner's name is qualified with, in the order given: nil where
  /// the name alone is unique, else where it is registered, and the runner's
  /// id as well where two share a name and a scope.
  static func qualifiers(among runners: [DiscoveredRunner]) -> [String?] {
    let repeated = repeatedNames(among: runners)
    let sharedScopes = runners.reduce(into: [[String]: Int]()) { counts, runner in
      counts[[runner.displayName, runner.scope.displayName], default: 0] += 1
    }
    return runners.map { runner in
      guard repeated.contains(runner.displayName) else { return nil }
      let scope = runner.scope.displayName
      guard sharedScopes[[runner.displayName, scope], default: 0] > 1 else { return scope }
      return L10n.quickMenuScopeWithID(scope, runner.agentId)
    }
  }

  /// The name this row leads with: the runner's own, plus where it is
  /// registered when that is what tells it apart from another runner here.
  ///
  /// Only when it is needed. `acme/widget-factory` is most of a menu bar
  /// row's width, and a Mac with one runner gains nothing from carrying it —
  /// there is nothing to disambiguate it from. GitHub will not accept two
  /// runners with one name in one scope; GitLab will, hence the id.
  var name: String {
    guard let qualifier else { return runner.displayName }
    return L10n.runnerInScope(runner.displayName, qualifier)
  }

  /// What this runner is building, and nil when it is not building anything.
  ///
  /// A property rather than a call at the one place it is rendered, because it
  /// is read twice now: the row prints it, and the thermal line asks whether it
  /// has overrun.
  var jobProgress: JobProgress? {
    JobProgress.reading(jobs, display: display, at: readAt)
  }

  /// Whether Start, Stop and Restart can do anything here.
  ///
  /// They are `svc.sh`, and `svc.sh` manages a LaunchAgent. A runner started by
  /// hand has none, so a Stop button on it would invite a click and then
  /// explain a failure that was certain before it was pressed.
  var canControlService: Bool { runner.installation == .launchAgent }

  /// Why the controls do nothing, in the words of how this runner actually
  /// runs. One note per installation, because "started by hand" over a runner
  /// that runs as a service is a lie with a helpful tone.
  var serviceNote: String? {
    switch runner.installation {
    case .launchAgent: nil
    case .manual: L10n.runnerStartedByHand
    case .gitLabService: L10n.runnerGitLabService
    case .managedFleet: L10n.runnerManagedFleet
    }
  }

  /// Whether GitLab, not GitHub, is the service this runner's remote half
  /// was asked of, and so the one a sentence about it has to name.
  var isOnGitLab: Bool {
    if case .gitLab = runner.scope { return true }
    return false
  }

  var row: RunnerRow {
    RunnerRow(
      // `displayName`, not `agentName`: the `.runner` file does not always
      // carry a name, and that runner would render as a blank row followed by
      // four buttons belonging to nobody.
      title: L10n.runnerRow(name, display.summary(for: runner)),
      progress: jobProgress?.line,
      operation: operation?.presentation,
      // Every action reads this runner's own state. Nothing here consults the
      // fleet summary, which is for the icon and only the icon.
      actions: [
        .init(
          kind: .start, label: L10n.start,
          isEnabled: canControlService && display.canStart && !isServiceActionReserved),
        .init(
          kind: .stop, label: L10n.stop,
          isEnabled: canControlService && display.canStop && !isServiceActionReserved),
        .init(
          kind: .restart, label: L10n.restart,
          isEnabled: canControlService && display.canRestart && !isServiceActionReserved),
        // Always available: a runner GitHub cannot see is the one you most
        // want to go and look at.
        .init(kind: .openOnGitHub, label: L10n.openOnGitHub, isEnabled: true),
      ],
      recentJobs: jobs.records
        // The running job already has a line of its own, with the one thing
        // this list cannot give it: how long it has been going.
        .filter { $0 != liveJob }
        .prefix(RunnerRow.recentJobsShown)
        .map { RunnerRow.RecentJob(id: $0.startedAt, text: $0.historyLine) })
  }
}

extension FleetNotice {
  /// How many paths the menu will print before it stops.
  ///
  /// A menu bar menu that runs off the screen is not more informative than one
  /// that does not. Ten is far past any real machine and still short of a
  /// directory somebody has been copying plists around in.
  static let pathsShown = 10

  /// The lines this notice puts in the menu, in order.
  var lines: [String] {
    switch self {
    case .noRunnersInstalled:
      [L10n.noRunnersFound]
    case .launchAgentsUnreadable(let directory):
      [L10n.launchAgentsUnreadable, PathText.abbreviated(directory)]
    case .unreadable(let paths):
      // The paths themselves, never a count: going and looking at the file is
      // the entire point, the file name alone does not say where it is, and a
      // plist duplicated in Finder describes one runner while appearing twice.
      // The overflow line carries no number for that same reason.
      [L10n.someRunnersUnreadable]
        + paths.prefix(Self.pathsShown).map {
          PathText.abbreviated($0)
        }
        + (paths.count > Self.pathsShown ? [L10n.moreUnreadable] : [])
    }
  }
}

/// The recovery fact discovery found, independent of whether valid runner
/// cards were found beside it.
enum FleetRecoveryPresentation: Equatable {
  case launchAgentsUnavailable(directory: String)
  case unreadableRunners(paths: [String])

  static func building(_ notice: FleetNotice?) -> Self? {
    switch notice {
    case .launchAgentsUnreadable(let directory):
      .launchAgentsUnavailable(directory: PathText.abbreviated(directory))
    case .unreadable(let paths):
      .unreadableRunners(paths: paths.map(PathText.abbreviated))
    case nil, .noRunnersInstalled:
      nil
    }
  }

  var title: String {
    switch self {
    case .launchAgentsUnavailable: L10n.launchAgentsUnreadable
    case .unreadableRunners: L10n.someRunnersUnreadable
    }
  }

  var detailLines: [String] {
    switch self {
    case .launchAgentsUnavailable(let directory): [directory]
    case .unreadableRunners(let paths): paths
    }
  }

  var quickMenuLine: String {
    switch self {
    case .launchAgentsUnavailable(let directory):
      [title, directory].joined(separator: " ")
    case .unreadableRunners(let paths):
      [title, paths.first, paths.count > 1 ? L10n.moreUnreadable : nil]
        .compactMap { $0 }
        .joined(separator: " ")
    }
  }
}

/// One fleet-level truth shared by the status item, quick menu, and Control
/// Center. Empty snapshots alone are not an answer: only a conclusive notice
/// may turn them into "no runners" or a recovery state.
struct FleetOverviewPresentation: Equatable {
  enum State: Equatable {
    case checking
    case noRunnersInstalled
    case unavailable
    case fleet(DisplayState)
  }

  let state: State
  let recovery: FleetRecoveryPresentation?
  let attention: String?

  static func building(
    snapshots: [RunnerSnapshot], notice: FleetNotice?
  ) -> Self {
    let recovery = FleetRecoveryPresentation.building(notice)
    let state: State
    if let aggregate = FleetSummary.summarising(snapshots.map(\.display)) {
      state = .fleet(aggregate)
    } else if recovery != nil {
      state = .unavailable
    } else if notice == .noRunnersInstalled {
      state = .noRunnersInstalled
    } else {
      // A nil notice is inconclusive and must not invent a clean empty result.
      state = .checking
    }
    // A runner that is perfectly healthy and whose last order failed is still
    // a runner somebody has to look at. Both facts are true; the summary used
    // to print only the flattering one, so the failure lived on as small print
    // inside a card with a green badge at the top.
    let attentionCount = snapshots.count {
      $0.display.needsAttention || $0.operation?.hasFailed == true
    }
    return Self(
      state: state, recovery: recovery,
      attention: attentionCount == 0 ? nil : L10n.runnerAttention(attentionCount))
  }

  var summary: String {
    switch state {
    case .checking: L10n.checkingRunners
    case .noRunnersInstalled: L10n.noRunnersFound
    case .unavailable: recovery?.title ?? L10n.checkingRunners
    case .fleet(let display): display.summary
    }
  }

  var shortSummary: String {
    switch state {
    case .fleet(let display): display.shortSummary
    case .checking, .noRunnersInstalled, .unavailable: summary
    }
  }

  var symbolName: String {
    switch state {
    case .checking: "arrow.triangle.2.circlepath"
    case .noRunnersInstalled: FleetSummary.noRunnersSymbolName
    case .unavailable: "exclamationmark.triangle"
    case .fleet(let display): display.symbolName
    }
  }

  var tone: StateTone {
    switch state {
    case .checking: .active
    case .noRunnersInstalled: .neutral
    case .unavailable: .attention
    case .fleet(let display): display.tone
    }
  }

  var quickMenuDiscoveryLine: String? {
    switch state {
    case .fleet:
      recovery?.quickMenuLine
    case .unavailable:
      recovery?.quickMenuLine ?? summary
    case .checking, .noRunnersInstalled:
      summary
    }
  }
}

/// The single state the menu bar icon shows for the whole machine.
enum FleetSummary {
  /// Nothing installed. Its own symbol rather than the unknown question mark:
  /// a Mac with no runners is not a Mac this app failed to read, and the two
  /// have completely different answers.
  /// An empty tray, not a dashed circle.
  ///
  /// UI-039: `circle.dashed` reads as a spinner — the more so beside
  /// `arrow.triangle.2.circlepath`, which is the symbol this app actually uses
  /// for "reading the machine". A window whose empty state looks like it is
  /// still loading never tells anybody it has finished.
  ///
  /// A tray also pairs with the `tray.full` on a card that has queued work
  /// waiting: nothing here, and something waiting, drawn as the same object.
  static let noRunnersSymbolName = "tray"

  /// Nil when there is nothing at all to summarise.
  static func summarising(_ displays: [DisplayState]) -> DisplayState? {
    guard !displays.isEmpty else { return nil }
    // Settling runners are held out of the aggregate rather than folded into
    // it. What they resolve to right now is the `.disconnected` this app has
    // decided not to believe yet, and letting it through the back door would
    // raise the warning triangle over a start that is going fine.
    let known = displays.compactMap(\.resolvedState)
    guard let aggregate = AggregateState.summarising(known) else { return .starting }
    return .resolved(aggregate)
  }

  static func symbolName(for displays: [DisplayState]) -> String {
    summarising(displays)?.symbolName ?? noRunnersSymbolName
  }

  /// What VoiceOver says after the menu-bar image's product label.
  ///
  /// This is deliberately the aggregate display, not a count assembled from
  /// individual runners: the icon carries the aggregate state, and saying a
  /// different state would make its label and value disagree.
  static func accessibilityValue(for display: DisplayState?) -> String {
    display?.summary ?? L10n.noRunnersFound
  }
}
