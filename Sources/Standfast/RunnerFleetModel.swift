import Foundation
import RunnerKit
import SwiftUI

/// One runner and what to show for it.
struct RunnerSnapshot: Identifiable, Equatable {
  let runner: DiscoveredRunner
  let display: DisplayState
  /// Where this runner is registered, and nil when its name already says which
  /// runner it is. Decided for the fleet rather than for the runner, because
  /// whether a name identifies anything is a question about the other runners;
  /// see `repeatedNames(among:)`.
  let qualifier: String?
  /// What this runner's own listener log says it has been doing.
  let jobs: JobHistory
  /// Whether `_diag` supplied a reading for this snapshot. An unavailable
  /// cold read also carries an empty history, but cannot baseline job events.
  let isJobHistoryAvailable: Bool
  /// When the scan behind this snapshot read the machine.
  ///
  /// Carried into the row rather than left to the clock so that every number
  /// in it describes one moment. A running job's elapsed time measured against
  /// `Date()` would tick on while the state beside it stayed as it was read
  /// half a minute ago, and the row would be quietly describing two different
  /// machines.
  let readAt: Date
  /// When the source that completed `display` answered. Equal to `readAt` for
  /// a local stopped/unknown result and later when GitHub completed the state.
  /// Event ordering uses this without changing the local probe stamp above.
  let stateReadAt: Date
  /// Which runner is installed here, and nil when nothing on disk says. Read
  /// with the rest of the scan rather than on its own schedule: it comes out of
  /// the head of the same log the job history is read from, and a runner that
  /// updated itself an hour ago must not still be reported as the old one.
  let version: RunnerVersion?
  /// A service mutation owns this runner until a conclusive post-action probe
  /// is applied. The row uses this to reject clicks before they can become
  /// silent no-ops in the model.
  let isServiceActionReserved: Bool
  /// What the last requested service mutation established. This never claims a
  /// runner state: a request returning only means its command returned.
  let operation: ServiceOperation?
  var id: String { runner.label }

  init(
    runner: DiscoveredRunner, display: DisplayState, qualifier: String? = nil,
    jobs: JobHistory = .empty, readAt: Date = .distantPast,
    isJobHistoryAvailable: Bool = true, stateReadAt: Date? = nil,
    version: RunnerVersion? = nil,
    isServiceActionReserved: Bool = false, operation: ServiceOperation? = nil
  ) {
    self.runner = runner
    self.display = display
    self.qualifier = qualifier
    self.jobs = jobs
    self.isJobHistoryAvailable = isJobHistoryAvailable
    self.readAt = readAt
    self.stateReadAt = stateReadAt ?? readAt
    self.version = version
    self.isServiceActionReserved = isServiceActionReserved
    self.operation = operation
  }
}

/// What the menu has to say beyond the runner rows themselves.
enum FleetNotice: Equatable {
  /// Nothing installed and nothing that failed to read. The expected result on
  /// a Mac that has never had a runner, where the answer is to install one
  /// rather than to fix anything.
  case noRunnersInstalled
  /// The directory that should contain every runner LaunchAgent could not be
  /// listed, so an empty result says nothing about what is installed.
  case launchAgentsUnreadable(URL)
  /// LaunchAgents that announced themselves as runners and could not be
  /// resolved. The paths, never a count: a plist duplicated in Finder
  /// describes one runner and appears here twice, so "2 unreadable runners"
  /// would be a number this app made up.
  case unreadable([URL])

  static func resolving(
    runners: [DiscoveredRunner], unreadable: [URL],
    failure: DiscoveryFailure? = nil
  ) -> FleetNotice? {
    if case .launchAgentsUnreadable(let directory) = failure {
      return .launchAgentsUnreadable(directory)
    }
    // Unreadable wins wherever it appears, including next to runners that did
    // resolve. A runner silently missing from the menu is worse than a line of
    // noise, and this is the only case here a user can act on.
    if !unreadable.isEmpty { return .unreadable(unreadable) }
    return runners.isEmpty ? .noRunnersInstalled : nil
  }
}

@MainActor
final class RunnerFleetModel: ObservableObject {
  @Published private(set) var snapshots: [RunnerSnapshot] = []
  /// The current service operation or nominal five-minute scan-wall-clock
  /// receipt for each installed runner. Labels are durable identities; names
  /// can collide.
  @Published private(set) var operations: [String: ServiceOperation] = [:]
  @Published private(set) var notice: FleetNotice?
  /// When the scan behind what is on screen *started* reading, and nil until
  /// one has. Stamped at the start rather than on arrival on purpose: a `gh`
  /// that hangs for thirty seconds leaves a stale menu, and a mark taken when
  /// the answer landed would describe it as fresh.
  @Published private(set) var lastReadAt: Date?
  /// The newest runner GitHub has published, and nil until it has been asked.
  /// Fleet-wide because the question is: there is one `actions/runner`.
  @Published private(set) var latestRelease: RunnerVersion?

  /// Which events reach the user, held here rather than beside this model so
  /// that the one place a scan turns into a notification is testable. Every bug
  /// this app has shipped was a wiring bug, and `App.swift` is the one file no
  /// test can read.
  let notifications: NotificationSettings
  let sleep: SleepGuard
  let housekeeping: HousekeepingModel

  private let discover: @Sendable () -> DiscoveryResult
  private let resolver: RunnerStateResolver
  private let controller: ServiceController
  private let clock: @Sendable () -> Date
  private let probeDelay: TimeInterval
  private let refreshInterval: TimeInterval?
  private let versions: any RunnerVersionReading
  private let releases: any RunnerReleaseChecking
  private let opener: any URLOpening
  private let serviceConfirmation: any ServiceActionConfirming
  private let releaseInterval: TimeInterval
  /// When GitHub was last asked what the newest runner is, and nil until it
  /// has been. Held here rather than beside the answer because a question that
  /// failed still counts as asked — otherwise a machine with no network would
  /// spend an API call on every single scan, all day, for an answer it is not
  /// going to get.
  private var lastReleaseCheck: Date?
  private var settling: SettlingWindow
  /// What the last scan said, so this one can report what changed. Held here
  /// for the same reason `settling` is: no single scan can own it.
  private var watcher = FleetWatcher()
  /// One per runner, carrying how much of its listener log has already been
  /// read. Held here for the same reason `settling` is: it is state about a
  /// runner that no single scan can own.
  private var jobLogs: [String: JobLogReader] = [:]
  private var inFlight: Task<Void, Never>?
  private var refreshRequested = false
  private var ticker: Task<Void, Never>?
  /// Actions still running, each removing itself when it finishes. Kept only
  /// so `quiesce()` has something to wait on.
  private var actions: [UUID: Task<Void, Never>] = [:]
  /// Dialogues waiting for a decision. Separate from command actions because
  /// no operation or reservation exists until an accepted prompt is
  /// revalidated against the latest snapshot.
  private var serviceConfirmationTasks: [UUID: Task<Void, Never>] = [:]
  /// Labels with a prompt already open. A second click is rejected before it
  /// can open another prompt for the same machine state.
  private var serviceConfirmationsInFlight: Set<String> = []
  /// A service mutation owns its runner until a conclusive post-completion
  /// launchd probe has been applied. Labels, rather than one fleet-wide flag,
  /// keep independent runners independent while making contradictory clicks
  /// on one runner harmless.
  private var serviceActionsInFlight: Set<String> = []
  /// The boundary a probe must reach before it can release the corresponding
  /// action. Absent while svc.sh itself is still running.
  private var serviceActionCompletions: [String: Date] = [:]
  /// Labels the last conclusive discovery proved were still installed. An
  /// inconclusive scan may add resolved labels, but never removes from this
  /// set: absence is removal evidence only when discovery says it is.
  private var knownInstalledLabels: Set<String> = []
  /// The last answer to "is this runner doing work?" from a scan where
  /// discovery could reconstruct its row, kept apart from `snapshots` because
  /// a later discovery may be unable to do so.
  /// In that case an empty menu is honest UI, but it is not evidence that work
  /// previously observed on that label has ended.
  private var activityEvidence: [String: Bool] = [:]

  private enum ExpectedStopResult {
    case none
    case completed(ExpectedStopOutcome)
    case cancelled
  }

  /// - Parameters:
  ///   - discover: a call rather than a `RunnerDiscovery`, because *where* the
  ///     scan runs is as much a part of this model's job as what it finds —
  ///     `discover()` reads the filesystem on whatever thread invokes it — and
  ///     only a call a test can wrap makes that checkable.
  ///   - probeDelay: how long to let launchd settle before re-probing after an
  ///     action.
  ///   - refreshInterval: nil to leave the model driven only by explicit
  ///     refreshes, which is what tests want.
  init(
    discover: @escaping @Sendable () -> DiscoveryResult = {
      RunnerDiscovery().discover()
    },
    resolver: RunnerStateResolver = RunnerStateResolver(),
    controller: ServiceController = ServiceController(),
    settling: SettlingWindow = SettlingWindow(),
    notifications: NotificationSettings = NotificationSettings(),
    sleep: SleepGuard = SleepGuard(),
    housekeeping: HousekeepingModel = HousekeepingModel(),
    versions: any RunnerVersionReading = RunnerVersionReader(),
    releases: any RunnerReleaseChecking = GHCommandLineClient(),
    opener: any URLOpening = WorkspaceURLOpener(),
    serviceConfirmation: any ServiceActionConfirming = ServiceAlertConfirmation(),
    clock: @escaping @Sendable () -> Date = Date.init,
    probeDelay: TimeInterval = 2,
    // 15s: fast enough that "did my build start?" is answered by looking up,
    // slow enough not to spend a GitHub API call every second all day.
    refreshInterval: TimeInterval? = 15,
    // A day. `actions/runner` ships every few weeks, so anything shorter is an
    // API call spent to learn nothing — and unlike the status call, which is
    // about this machine and has to be current, being a few hours late with
    // "there is a newer runner" costs nobody anything.
    releaseInterval: TimeInterval = 24 * 60 * 60
  ) {
    self.discover = discover
    self.resolver = resolver
    self.controller = controller
    self.settling = settling
    self.notifications = notifications
    self.sleep = sleep
    self.housekeeping = housekeeping
    self.versions = versions
    self.releases = releases
    self.opener = opener
    self.serviceConfirmation = serviceConfirmation
    self.clock = clock
    self.probeDelay = probeDelay
    self.refreshInterval = refreshInterval
    self.releaseInterval = releaseInterval
    refresh()
    guard let refreshInterval else { return }
    // A sleeping task rather than a `Timer`: a scheduled timer runs in the
    // default run loop mode, and an open NSMenu puts the run loop in event
    // tracking mode — so the one moment the user is looking at the menu is
    // exactly when a timer would stop refreshing it.
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(refreshInterval))
        guard let self else { return }
        tick()
      }
    }
  }

  deinit {
    ticker?.cancel()
    for task in serviceConfirmationTasks.values { task.cancel() }
  }

  // MARK: - Reading

  func refresh() {
    guard inFlight == nil else {
      // Remembered rather than dropped. N runners at up to a 30s `gh` timeout
      // each can easily outlast the 15s tick that starts the next scan, and
      // the request most likely to arrive during a slow one is the re-probe
      // after an action — the single answer the user is actually waiting for.
      refreshRequested = true
      return
    }
    // Stamped before anything is read and carried to `lastReadAt`, where it
    // measures the freshness of the scan as a whole. Each runner gets a second,
    // exact stamp when its own launchd probe answers; action ordering uses that
    // probe stamp rather than this scan-level one.
    let startedAt = clock()
    // Asked at most once a day, and beside the scan rather than inside it: see
    // `checkForNewRelease`.
    if lastReleaseCheck.map({ startedAt.timeIntervalSince($0) >= releaseInterval })
      ?? true
    {
      checkForNewRelease(at: startedAt)
    }
    inFlight = Task { [discover, resolver, jobLogs, versions, clock] in
      let scan = await Self.scan(
        discover: discover, resolver: resolver, readers: jobLogs, versions: versions,
        clock: clock)
      apply(scan, startedAt: startedAt)
      inFlight = nil
      if refreshRequested {
        refreshRequested = false
        refresh()
      }
    }
  }

  /// The refresh the ticker asks for, which is not the refresh the menu asks
  /// for — and the difference is the whole of the fix.
  ///
  /// A tick is dropped where an explicit request is remembered. Remembering
  /// both, which is what this used to do, is how a `gh` slower than the
  /// interval turned the ticker into a loop: every tick that landed during a
  /// scan left a request pending, so the scan restarted the instant it
  /// finished, and then again, for as long as the network stayed bad. No
  /// pause, an API call per pass, and a radio that never gets to sleep —
  /// spending the most battery exactly when the machine can least afford it.
  ///
  /// Dropping loses nothing. A tick asks for a fresh reading, and a scan
  /// already running is one.
  func tick() {
    guard inFlight == nil else { return }
    // And a reading younger than the interval is one this tick has nothing to
    // add to. `readAt` is when the machine was read rather than when the
    // answer landed, which is what makes it the right clock here: a scan that
    // overran leaves the next tick due the moment it arrives, and that is the
    // same loop by a slower route. It also means a Refresh now pushes the next
    // automatic reading out, which is what a user who has just refreshed
    // wanted.
    if let refreshInterval, let lastReadAt,
      clock().timeIntervalSince(lastReadAt) < refreshInterval
    {
      return
    }
    refresh()
  }

  /// Waits out everything this model has running: actions, the refresh each of
  /// them ends with, and any refresh a running one asked for. The scene never
  /// needs this — it watches `@Published` — but a test does.
  func quiesce() async {
    while true {
      if let confirmation = serviceConfirmationTasks.values.first {
        await confirmation.value
        continue
      }
      if let action = actions.values.first {
        await action.value
        continue
      }
      guard let refresh = inFlight else { return }
      await refresh.value
    }
  }

  /// Asked alongside a scan and never inside one.
  ///
  /// It is one question about the whole internet rather than about this Mac, it
  /// is answered by spawning `gh`, and the comment on `releaseInterval` says
  /// what it is worth: being a few hours late with "there is a newer runner"
  /// costs nobody anything. A scan that waited for it would be a menu that
  /// stays empty for as long as `gh` takes — up to the command timeout, thirty
  /// seconds — and the very first scan of every launch is one that asks, because
  /// `lastReleaseCheck` is process memory that starts at nil. That is a blank
  /// menu at every start of the app, in the one situation where the answer
  /// matters least.
  ///
  /// - Parameter readAt: stamped before the answer rather than after it, so a
  ///   Mac with no network asks once a day rather than once every fifteen
  ///   seconds. A question that failed still counts as asked.
  private func checkForNewRelease(at readAt: Date) {
    lastReleaseCheck = readAt
    let releases = releases
    let id = UUID()
    actions[id] = Task {
      let latest = await offCooperativePool { try? releases.blockingLatestRunnerRelease() }
      // The last known answer is kept when there is none, for the same reason a
      // stale version beats no version: the runner did not stop being out of
      // date because the Wi-Fi dropped.
      if let latest { latestRelease = latest }
      actions[id] = nil
    }
  }

  /// Off both pools, and sequential.
  ///
  /// This function is `nonisolated async`, which means it runs on the
  /// cooperative pool — one thread per core, shared with every other `Task` in
  /// the app, main actor included. Nothing that blocks may run here, and both
  /// halves of a scan block: `discover()` reads a directory and two files per
  /// runner, and the resolver parks a thread inside `waitUntilExit()` twice.
  /// Both are handed to `offCooperativePool`, the resolver by way of its own
  /// async facade.
  ///
  /// Sequential because parallelism is not what makes this fast enough — there
  /// are rarely more than a handful of runners, and the coalescing in
  /// `refresh()` is what stops a slow scan from piling up.
  private nonisolated static func scan(
    discover: @escaping @Sendable () -> DiscoveryResult, resolver: RunnerStateResolver,
    readers: [String: JobLogReader], versions: any RunnerVersionReading,
    clock: @escaping @Sendable () -> Date
  ) async -> Scan {
    // Conservative by design: discovery may enumerate the directory first and
    // then spend arbitrarily long resolving candidates before it returns. An
    // absence from that result must not be dated after an action that completed
    // during those candidate reads.
    let discoveryStartedAt = clock()
    let found = await offCooperativePool { discover() }
    var states: [RunnerState] = []
    var jobs: [JobLogReader.Reading] = []
    var installed: [RunnerVersion?] = []
    var readAt: [Date] = []
    var stateReadAt: [Date] = []
    var readers = readers
    for runner in found.runners {
      let state = await resolver.reading(for: runner, clock: clock)
      states.append(state.state)
      readAt.append(state.readAt)
      stateReadAt.append(state.stateReadAt)
      // The same rule as discovery, for the same reason: this is file I/O, and
      // the cheap path — a directory listing and a `stat` — is only the usual
      // one. A cold read is hundreds of kilobytes, off a home directory that
      // may well be on a network volume.
      let reader = readers[runner.label] ?? JobLogReader()
      let diagnostics = runner.diagnosticsDirectory
      // One hop for both, and the version read off the log the history has just
      // been read from. Its own hop and its own listing of `_diag` would be the
      // same directory walked twice per runner per refresh, which is the work
      // `JobLogReader` documents its cache as existing to avoid — and it grows
      // with the file count the sweep exists to bound.
      let read = await offCooperativePool { () -> Reading in
        var reader = reader
        let history = reader.reading(diagnosticsIn: diagnostics)
        return Reading(
          jobs: history, reader: reader,
          version: history.isAvailable
            ? reader.activeLog.flatMap(versions.blockingVersion) : nil)
      }
      jobs.append(read.jobs)
      readers[runner.label] = read.reader
      installed.append(read.version)
    }
    return Scan(
      found: found, states: states, jobs: jobs, readers: readers, versions: installed,
      discoveryStartedAt: discoveryStartedAt, readAt: readAt,
      stateReadAt: stateReadAt)
  }

  /// Everything one hop off the pool reads about one runner's `_diag`.
  ///
  /// A named type for the same reason `Scan` is: it crosses a thread boundary.
  /// One hop rather than two because both halves come out of the same directory
  /// listing — the version is read off the log the history was just read from.
  private struct Reading: Sendable {
    let jobs: JobLogReader.Reading
    let reader: JobLogReader
    let version: RunnerVersion?
  }

  /// One scan's answer. A named type rather than a tuple because it crosses a
  /// thread boundary and has to be `Sendable` where a caller can see it.
  private struct Scan: Sendable {
    let found: DiscoveryResult
    let states: [RunnerState]
    let jobs: [JobLogReader.Reading]
    let readers: [String: JobLogReader]
    let versions: [RunnerVersion?]
    /// The conservative instant just before discovery began. This dates
    /// absence; present runners use their exact stamps below.
    let discoveryStartedAt: Date
    /// When launchd answered for each corresponding runner.
    let readAt: [Date]
    /// When the source completing each corresponding state answered.
    let stateReadAt: [Date]
  }

  /// - Parameter startedAt: when this scan began. This is the fleet-level
  ///   freshness stamp; each snapshot uses its corresponding per-runner probe
  ///   time from `Scan.readAt` for action ordering and elapsed job time.
  private func apply(_ scan: Scan, startedAt: Date) {
    let resolvedLabels = Set(scan.found.runners.map(\.label))
    // An action is direct evidence that its label still belongs to this
    // lifecycle. Absence whose conservative stamp is no later than completion
    // cannot revoke that evidence merely because another runner delayed the
    // scan's arrival. Equality stays protected because a coarse clock cannot
    // order the two facts.
    let labelsProtectedFromAbsence = Set(
      serviceActionsInFlight.filter { label in
        guard let completedAt = serviceActionCompletions[label] else { return true }
        return scan.discoveryStartedAt <= completedAt
      })
    let retainedLabels: Set<String>
    if let possiblyInstalledLabels = scan.found.possiblyInstalledLabels {
      retainedLabels =
        resolvedLabels
        .union(possiblyInstalledLabels)
        .union(labelsProtectedFromAbsence)
      knownInstalledLabels = retainedLabels
    } else {
      knownInstalledLabels.formUnion(resolvedLabels)
      retainedLabels = knownInstalledLabels
    }
    // A runner that has been uninstalled since it was started would otherwise
    // leave its deadline behind, with nothing left to ever read and clear it.
    settling.keepOnly(retainedLabels)
    operations = operations.filter {
      retainedLabels.contains($0.key)
        && $0.value.isReceiptRetained(atScanWallClock: startedAt)
    }
    // And its log reader would hold a few hundred parsed jobs for a runner
    // that no longer exists, for as long as the app runs.
    jobLogs = scan.readers.filter { retainedLabels.contains($0.key) }
    watcher.keepOnly(retainedLabels)
    // And its measured four gigabytes would sit in memory for the life of the
    // app, describing a directory that may well have been deleted with it.
    housekeeping.keepOnly(retainedLabels)
    releaseServiceActionsObserved(in: scan, retainedLabels: retainedLabels)
    let repeated = RunnerSnapshot.repeatedNames(among: scan.found.runners)
    let previousVersions = snapshots.reduce(into: [String: RunnerVersion]()) {
      versions, snapshot in
      if let version = snapshot.version { versions[snapshot.runner.label] = version }
    }
    snapshots = scan.found.runners.indices.map { index in
      let runner = scan.found.runners[index]
      let readAt = scan.readAt[index]
      let jobReading = scan.jobs[index]
      return RunnerSnapshot(
        runner: runner,
        display: settling.display(scan.states[index], for: runner.label, readAt: readAt),
        // Only where the name alone would not say which runner this is.
        qualifier: repeated.contains(runner.displayName)
          ? runner.scope.displayName : nil,
        jobs: jobReading.history,
        readAt: readAt,
        isJobHistoryAvailable: jobReading.isAvailable,
        stateReadAt: scan.stateReadAt[index],
        version: jobReading.isAvailable
          ? scan.versions[index] : previousVersions[runner.label],
        isServiceActionReserved: serviceActionsInFlight.contains(runner.label),
        operation: operations[runner.label])
    }
    activityEvidence = activityEvidence.filter { retainedLabels.contains($0.key) }
    for snapshot in snapshots {
      activityEvidence[snapshot.runner.label] =
        snapshot.display.resolvedState == .busy
        || (snapshot.display.resolvedState != .stopped && snapshot.jobs.running != nil)
    }
    notice = FleetNotice.resolving(
      runners: scan.found.runners, unreadable: scan.found.unreadable,
      failure: scan.found.failure)
    lastReadAt = startedAt
    // Read from what the menu is about to show rather than from the scan, so a
    // runner the settling window is covering for cannot be announced as
    // disconnected while the menu says it is starting.
    notifications.deliver(watcher.events(in: snapshots))
    sleep.update(busy: activityEvidence.values.contains(true))
  }

  /// Releases a runner only after apply has consumed local evidence newer than
  /// its action. Ownership serializes mutations, rather than certifying a
  /// particular state: once any dated local probe has been applied, even an
  /// unreadable one, the UI may offer recovery actions again. FleetWatcher
  /// independently retains an expected-stop intent until state evidence can
  /// settle it. Discovery removal is terminal only when its dated enumeration
  /// is new enough; `retainedLabels` preserves stale or inconclusive absence.
  private func releaseServiceActionsObserved(
    in scan: Scan, retainedLabels: Set<String>
  ) {
    for label in Array(serviceActionsInFlight) {
      guard let completedAt = serviceActionCompletions[label] else { continue }
      guard retainedLabels.contains(label) else {
        releaseServiceAction(for: label)
        continue
      }
      guard let index = scan.found.runners.firstIndex(where: { $0.label == label }),
        scan.readAt[index] >= completedAt
      else { continue }
      releaseServiceAction(for: label)
    }
  }

  private func releaseServiceAction(for label: String) {
    serviceActionsInFlight.remove(label)
    serviceActionCompletions.removeValue(forKey: label)
  }

  /// Whether some runner's job has already taken longer than that job usually
  /// takes here. What turns the thermal line from a fact about the hardware
  /// into an explanation of what the user is looking at.
  var isOverrunning: Bool {
    snapshots.contains { $0.jobProgress?.isOverTypical == true }
  }

  // MARK: - Presenting

  /// The bounded menu projection, built only from values the latest scan has
  /// already read.
  func quickMenuPresentation(
    thermalLines: [String], now: Date = Date()
  ) -> QuickMenuPresentation {
    QuickMenuPresentation.building(
      snapshots: snapshots, notice: notice, thermalLines: thermalLines,
      readAt: lastReadAt, now: now)
  }

  /// The complete card projection, built only from model and housekeeping
  /// memory. Reading it never probes GitHub, launchd, or disk.
  func controlCenterCards(now: Date = Date()) -> [RunnerCardPresentation] {
    snapshots.map { snapshot in
      RunnerCardPresentation.building(
        snapshot, measurement: housekeeping.measurement(for: snapshot.runner),
        latestRelease: latestRelease,
        isMaintenanceWorking: housekeeping.isWorking(on: snapshot.runner),
        maintenanceNotice: housekeeping.notice(for: snapshot.runner), now: now)
    }
  }

  /// The complete Control Center projection. Like the card compatibility
  /// accessor above, this reads only values already held by the model.
  func controlCenterPresentation(now: Date = Date()) -> ControlCenterPresentation {
    let cards = controlCenterCards(now: now)
    return ControlCenterPresentation(
      header: .building(snapshots: snapshots, readAt: lastReadAt, now: now),
      cards: cards,
      empty: cards.isEmpty ? .building(notice: notice) : nil,
      notice: .building(notice: notice))
  }

  // MARK: - Acting

  private func acquireServiceAction(for label: String) -> Bool {
    guard serviceActionsInFlight.insert(label).inserted else { return false }
    // The action itself is direct evidence that this label belongs to the
    // lifecycle state below. An inconclusive discovery must retain it even if
    // the action was invoked before a prior scan had recorded the label.
    knownInstalledLabels.insert(label)
    snapshots = snapshots.map { snapshot in
      guard snapshot.runner.label == label else { return snapshot }
      return RunnerSnapshot(
        runner: snapshot.runner, display: snapshot.display,
        qualifier: snapshot.qualifier, jobs: snapshot.jobs,
        readAt: snapshot.readAt,
        isJobHistoryAvailable: snapshot.isJobHistoryAvailable,
        stateReadAt: snapshot.stateReadAt,
        version: snapshot.version,
        isServiceActionReserved: true, operation: operations[label])
    }
    return true
  }

  /// The one way the menu acts on a runner, so the view has nothing to wire
  /// up wrongly.
  func perform(_ kind: RunnerRow.Action.Kind, on runner: DiscoveredRunner) {
    perform(kind, onRunnerID: runner.label)
  }

  /// Presentation rows carry durable runner identifiers rather than mutable
  /// machine values. Every route, including Start and navigation, resolves the
  /// latest snapshot and rechecks its model-owned capability here.
  func perform(_ kind: RunnerRow.Action.Kind, onRunnerID id: String) {
    guard let snapshot = snapshots.first(where: { $0.id == id }) else { return }
    perform(kind, on: snapshot)
  }

  private func perform(_ kind: RunnerRow.Action.Kind, on snapshot: RunnerSnapshot) {
    switch kind {
    case .start: start(snapshot)
    case .stop: stop(snapshot)
    case .restart: restart(snapshot)
    case .openOnGitHub: openOnGitHub(snapshot)
    }
  }

  func performMaintenance(_ kind: MaintenanceOffer.Kind, onRunnerID id: String) {
    guard let snapshot = snapshots.first(where: { $0.id == id }) else { return }
    housekeeping.perform(kind, on: snapshot)
  }

  /// No hop anywhere in here: every one of the controller's entry points is
  /// `async` and makes its own, which is where it belongs — the thread a
  /// blocking call needs is the callee's business, not something each caller
  /// has to remember.
  func start(_ runner: DiscoveredRunner) {
    perform(.start, onRunnerID: runner.label)
  }

  private func start(_ snapshot: RunnerSnapshot) {
    guard canPerformServiceAction(.start, on: snapshot),
      acquireServiceAction(for: snapshot.runner.label)
    else { return }
    dispatchStart(on: snapshot.runner)
  }

  private func dispatchStart(on runner: DiscoveredRunner) {
    perform(action: .start, on: runner, thenSettles: true) {
      controller, directory in
      try await controller.start(in: directory)
    }
  }

  func stop(_ runner: DiscoveredRunner) {
    perform(.stop, onRunnerID: runner.label)
  }

  private func stop(_ snapshot: RunnerSnapshot) {
    requestDisruptiveAction(.stop, on: snapshot)
  }

  private func dispatchStop(on runner: DiscoveredRunner) {
    // Acquired before either side effect: an ignored overlapping Stop must not
    // close another action's settling window or mint a stop intent of its own.
    settling.close(for: runner.label)
    // Told before the command runs rather than after it returns: `svc.sh stop`
    // takes a moment and a scan can land inside it, and a stop this app ordered
    // must never be reported back to the person who ordered it — not even when
    // the reading arrives early.
    let expectedStop = watcher.expectStop(for: runner.label, action: .stop, at: clock())
    perform(action: .stop, on: runner, thenSettles: false, expectedStop: expectedStop) {
      controller, directory in
      try await controller.stop(in: directory)
    }
  }

  func restart(_ runner: DiscoveredRunner) {
    perform(.restart, onRunnerID: runner.label)
  }

  private func restart(_ snapshot: RunnerSnapshot) {
    requestDisruptiveAction(.restart, on: snapshot)
  }

  private func dispatchRestart(on runner: DiscoveredRunner) {
    // A restart takes the service down first, so it looks exactly like a stop
    // to anything reading `launchctl` in the 1.5s gap.
    let expectedStop = watcher.expectStop(
      for: runner.label, action: .restart, at: clock())
    perform(action: .restart, on: runner, thenSettles: true, expectedStop: expectedStop) {
      controller, directory in
      try await controller.restart(in: directory)
    }
  }

  func openOnGitHub(_ runner: DiscoveredRunner) {
    perform(.openOnGitHub, onRunnerID: runner.label)
  }

  private func openOnGitHub(_ snapshot: RunnerSnapshot) {
    guard snapshot.row.action(.openOnGitHub)?.isEnabled == true else { return }
    opener.open(snapshot.runner.scope.preferredGitHubURL)
  }

  private func canPerformServiceAction(
    _ action: ServiceOperationAction, on snapshot: RunnerSnapshot
  ) -> Bool {
    let kind: RunnerRow.Action.Kind =
      switch action {
      case .start: .start
      case .stop: .stop
      case .restart: .restart
      }
    let label = snapshot.runner.label
    return snapshot.row.action(kind)?.isEnabled == true
      && !serviceActionsInFlight.contains(label)
      && !serviceConfirmationsInFlight.contains(label)
  }

  private func requestDisruptiveAction(
    _ action: ServiceOperationAction, on snapshot: RunnerSnapshot
  ) {
    guard canPerformServiceAction(action, on: snapshot) else { return }
    guard let prompt = ServiceActionPrompt(action: action, snapshot: snapshot) else {
      guard acquireServiceAction(for: snapshot.runner.label) else { return }
      dispatch(action, on: snapshot.runner)
      return
    }

    let label = snapshot.runner.label
    guard serviceConfirmationsInFlight.insert(label).inserted else { return }
    let confirmation = serviceConfirmation
    let id = UUID()
    serviceConfirmationTasks[id] = Task { [weak self, confirmation] in
      let accepted = await confirmation.confirm(prompt)
      guard let self else { return }
      finishServiceConfirmation(
        id: id, label: label, prompt: prompt, accepted: accepted)
    }
  }

  private func finishServiceConfirmation(
    id: UUID, label: String, prompt: ServiceActionPrompt, accepted: Bool
  ) {
    defer {
      serviceConfirmationsInFlight.remove(label)
      serviceConfirmationTasks[id] = nil
    }
    guard !Task.isCancelled, accepted,
      let snapshot = snapshots.first(where: { $0.id == label }),
      prompt.stillMatches(snapshot),
      canPerformServiceActionIgnoringConfirmation(prompt.action, on: snapshot),
      acquireServiceAction(for: label)
    else { return }
    // Main-actor code from the latest lookup through acquisition and dispatch:
    // no suspension or re-entrancy point can invalidate the checked snapshot.
    dispatch(prompt.action, on: snapshot.runner)
  }

  private func canPerformServiceActionIgnoringConfirmation(
    _ action: ServiceOperationAction, on snapshot: RunnerSnapshot
  ) -> Bool {
    let kind: RunnerRow.Action.Kind =
      switch action {
      case .start: .start
      case .stop: .stop
      case .restart: .restart
      }
    let label = snapshot.runner.label
    return snapshot.row.action(kind)?.isEnabled == true
      && !serviceActionsInFlight.contains(label)
  }

  private func dispatch(
    _ action: ServiceOperationAction, on runner: DiscoveredRunner
  ) {
    switch action {
    case .start: dispatchStart(on: runner)
    case .stop: dispatchStop(on: runner)
    case .restart: dispatchRestart(on: runner)
    }
  }

  private func perform(
    action: ServiceOperationAction,
    on runner: DiscoveredRunner,
    thenSettles: Bool,
    expectedStop: ExpectedStopHandle? = nil,
    _ work: @escaping @Sendable (ServiceController, URL) async throws -> Void
  ) {
    let controller = controller
    let directory = runner.directory
    let label = runner.label
    let id = UUID()
    publishOperation(
      .init(action: action, phase: .inFlight, changedAt: clock()), for: label)
    actions[id] = Task {
      var ranSomething = true
      var stopResult = ExpectedStopResult.none
      do {
        try await work(controller, directory)
        publishOperation(
          .init(action: action, phase: .requestAccepted, changedAt: clock()), for: label)
        if expectedStop != nil { stopResult = .completed(.actionCompleted) }
      } catch let failure as RestartStartFailure {
        publishOperation(
          .init(
            action: action,
            phase: failure.timedOut
              ? .uncertain(.restartStartTimedOut)
              : .failed(.restartStartFailed),
            changedAt: clock()),
          for: label)
        // Stop completed before ServiceController attempted Start. Whatever
        // happened in the second half, a stopped re-probe belongs to this
        // restart and must retain its expected-stop intent.
        if expectedStop != nil {
          stopResult = .completed(
            failure.timedOut ? .restartStartUncertain : .restartStartFailed)
        }
        ranSomething = failure.timedOut
      } catch CommandError.timedOut {
        publishOperation(
          .init(action: action, phase: .uncertain(.commandTimedOut), changedAt: clock()),
          for: label)
        // The command was killed at the deadline, which says nothing at all
        // about whether it worked. `svc.sh start` is a `launchctl load` and a
        // handful of shell; when it takes more than thirty seconds it is the
        // machine that is slow, and the load has usually already happened —
        // which is precisely when a runner needs the longest to register, and
        // so needs the window most. Treating this as a failure raised the
        // warning triangle over a start that had gone through.
        //
        // A window opened over a start that did not take costs thirty seconds
        // of "Starting…" and then the truth, because the window only ever
        // holds back `.disconnected` and a failed start reports `.stopped`.
        // That is the cheaper of the two mistakes by a wide margin.
        if expectedStop != nil { stopResult = .completed(.stopUncertain) }
      } catch ServiceControlError.scriptMissing {
        publishOperation(
          .init(action: action, phase: .failed(.scriptMissing), changedAt: clock()),
          for: label)
        ranSomething = false
        if expectedStop != nil { stopResult = .cancelled }
      } catch CommandError.couldNotLaunch {
        publishOperation(
          .init(action: action, phase: .failed(.commandCouldNotLaunch), changedAt: clock()),
          for: label)
        ranSomething = false
        if expectedStop != nil { stopResult = .cancelled }
      } catch {
        publishOperation(
          .init(action: action, phase: .failed(.unexpectedFailure), changedAt: clock()),
          for: label)
        // This is a definite failure rather than a timeout. A missing `svc.sh`
        // throws before a process is launched, and opening a window here would
        // dress a half-uninstalled runner up as "Starting…" for thirty seconds
        // over an action that never happened.
        ranSomething = false
        if expectedStop != nil { stopResult = .cancelled }
      }
      let completedAt = clock()
      switch stopResult {
      case .completed(let outcome):
        if let expectedStop {
          watcher.completeExpectedStop(expectedStop, outcome: outcome, at: completedAt)
        }
      case .cancelled:
        if let expectedStop { watcher.cancelExpectedStop(expectedStop) }
      case .none:
        break
      }
      if thenSettles && ranSomething { settling.open(for: label, at: completedAt) }
      serviceActionCompletions[label] = completedAt
      // `svc.sh` returns before launchd has settled, so an immediate re-probe
      // reports the state we just left.
      try? await Task.sleep(for: .seconds(probeDelay))
      refresh()
      actions[id] = nil
    }
  }

  private func publishOperation(_ operation: ServiceOperation, for label: String) {
    operations[label] = operation
    snapshots = snapshots.map { snapshot in
      guard snapshot.runner.label == label else { return snapshot }
      return RunnerSnapshot(
        runner: snapshot.runner, display: snapshot.display,
        qualifier: snapshot.qualifier, jobs: snapshot.jobs, readAt: snapshot.readAt,
        isJobHistoryAvailable: snapshot.isJobHistoryAvailable,
        stateReadAt: snapshot.stateReadAt,
        version: snapshot.version,
        isServiceActionReserved: snapshot.isServiceActionReserved,
        operation: operation)
    }
  }
}
