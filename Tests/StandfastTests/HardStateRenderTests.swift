import AppKit
import Foundation
import RunnerKit
import SwiftUI
import Testing

@testable import Standfast

/// Renders a runner's detail in the states a screenshot of a working Mac never
/// shows.
///
/// Codex, given only happy-path captures on 2026-08-16: "no he visto los
/// estados difíciles. Una captura feliz no demuestra cómo maneja desconexión,
/// fallo, datos obsoletos, un job activo o acciones que fallan." He is right,
/// and those states are exactly where an operational tool earns or loses
/// trust — so they get rendered rather than described.
///
/// Off by default. Set `STANDFAST_RENDER_DIR` to a writable directory to
/// produce the PNGs; without it the whole suite skips this file, because
/// writing images is not something a test run should do behind your back.
private var renderDirectory: URL? {
  ProcessInfo.processInfo.environment["STANDFAST_RENDER_DIR"]
    .map { URL(fileURLWithPath: $0) }
}

/// The appearances a render can be taken in.
///
/// Dark was the only one for a long time, which meant every judgement about
/// this app's look was a judgement about half of it. The light palette has its
/// own measured values — and the table that reviewed this app found a token
/// that reads at 7.99:1 in one appearance and 2.06:1 in the other, which is
/// exactly the kind of thing a dark-only render cannot show.
/// Increase Contrast is deliberately absent: `colorSchemeContrast` is
/// read-only in SwiftUI, so it cannot be injected into a render. That axis
/// stays what it already was — a person toggling it in System Settings with
/// the window open, which is also the only way to test its hot path (UI-021).
private struct RenderAppearance {
  let suffix: String
  let scheme: ColorScheme

  static let dark = RenderAppearance(suffix: "", scheme: .dark)
  static let light = RenderAppearance(suffix: "-claro", scheme: .light)
}

@MainActor
private func render(
  _ view: some View, to url: URL,
  width: CGFloat = 560,
  height: CGFloat = 700,
  appearance: RenderAppearance = .dark
) throws {
  // About the detail column at the window's default size. The split view, its
  // toolbar and their glass do not draw offscreen, so the detail is rendered
  // on its own.
  let size = NSSize(width: width, height: height)
  let hosting = NSHostingView(
    rootView:
      view
      .frame(width: size.width, height: size.height)
      // Offscreen there is no window behind the view, and a view that draws
      // no background of its own, as the system's empty state does not,
      // would sit on a canvas of the wrong appearance.
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, appearance.scheme))
  hosting.frame = NSRect(origin: .zero, size: size)
  hosting.layoutSubtreeIfNeeded()
  hosting.displayIfNeeded()
  let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
  hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  let named =
    appearance.suffix.isEmpty
    ? url
    : url
      .deletingLastPathComponent()
      .appendingPathComponent(
        url.deletingPathExtension().lastPathComponent + appearance.suffix + ".png")
  try png.write(to: named)
}

/// Says yes to every prompt: these renders are about the state the window
/// ends up in, not about the confirmation dialog on the way there.
@MainActor
private struct RenderConfirmation: ServiceActionConfirming {
  func confirm(_ prompt: ServiceActionPrompt) async -> ServiceActionConfirmationResult {
    .accepted
  }
}

@MainActor
private func fleet(_ sandbox: FleetSandbox) -> RunnerFleetModel {
  RunnerFleetModel(
    discover: sandbox.discover, resolver: sandbox.resolver,
    controller: ServiceController(commandRunner: sandbox.svcDrivingCommandRunner),
    notifications: NotificationSettings(
      delivery: FakeNotificationDelivery(), defaults: scratchDefaults()),
    sleep: SleepGuard(activity: FakeSleepPreventer(), defaults: scratchDefaults()),
    versions: sandbox.versions, releases: sandbox.releases,
    queues: sandbox.queuedWork, opener: FakeURLOpener(),
    serviceConfirmation: RenderConfirmation(), refreshInterval: nil)
}

/// A runner's detail as the window draws it once selected, with nothing hot.
@MainActor
private func detail(
  of fleet: RunnerFleetModel,
  where isWanted: (RunnerCardPresentation) -> Bool = { _ in true }
) throws -> some View {
  let wanted = fleet.controlCenterPresentation(now: Date()).cards.first(where: isWanted)
  let card = try #require(wanted)
  return RunnerCardView(
    card: card, thermalLine: nil, performMaintenance: { _ in }, showLogs: {})
}

@Test @MainActor func renderTheStatesAScreenshotOfAWorkingMacNeverShows() async throws {
  guard let directory = renderDirectory else { return }
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true)

  // 0. The everyday shape: one of two healthy runners, which is what the
  // window shows on the Mac it was built against and the baseline every other
  // state is judged against.
  let healthy = try FleetSandbox(serviceRunning: true)
  defer { healthy.cleanUp() }
  _ = try healthy.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  _ = try healthy.addRunner(name: "mac-mini-m4-build", scope: "acme-tooling")
  let healthyFleet = fleet(healthy)
  await healthyFleet.quiesce()
  try render(
    detail(of: healthyFleet),
    to: directory.appendingPathComponent("0-normal.png"))
  try render(
    detail(of: healthyFleet),
    to: directory.appendingPathComponent("0-normal.png"), appearance: .light)

  // 0b. The other window, a pane at a time: each is the size the window takes
  // while it shows, and the tabs above them belong to the window, which an
  // offscreen render does not draw. General is where Settings always opens.
  let settingsVersion = ["CFBundleShortVersionString": "0.5.0", "CFBundleVersion": "5"]
  try render(
    GeneralSettingsPane(
      presentation: SettingsPresentation(
        notificationNotice: nil, loginItemNotice: nil, infoDictionary: settingsVersion),
      notifications: healthyFleet.notifications, sleep: healthyFleet.sleep,
      loginItem: LoginItem(), dock: unattendedDockVisibility()
    )
    .background(Color(nsColor: .windowBackgroundColor)),
    to: directory.appendingPathComponent("0c-ajustes.png"),
    width: StandfastTheme.settingsPaneWidth,
    height: StandfastTheme.settingsGeneralHeight)

  // 0c2. General with the longest notice each section can show. This is the
  // case its height was measured on, so a longer line shows up here first.
  try render(
    GeneralSettingsPane(
      presentation: SettingsPresentation(
        notificationNotice: L10n.notificationsBlocked,
        loginItemNotice: L10n.openAtLoginUnavailable, infoDictionary: settingsVersion),
      notifications: healthyFleet.notifications, sleep: healthyFleet.sleep,
      loginItem: LoginItem(), dock: unattendedDockVisibility()
    )
    .background(Color(nsColor: .windowBackgroundColor)),
    to: directory.appendingPathComponent("0c2-ajustes-con-avisos.png"),
    width: StandfastTheme.settingsPaneWidth,
    height: StandfastTheme.settingsGeneralHeight)

  // 0d. Accounts on a Mac that has a token. The Remove button only exists in
  // this state, so the screenshot without it proves nothing about whether it
  // fits.
  let githubWithToken = await settledAccess("ghp_example")
  let gitLabBeside = await settledAccess(nil)
  try render(
    AccountsSettingsPane(
      presentation: SettingsPresentation(
        githubState: githubWithToken.state, githubNotice: githubWithToken.notice,
        notificationNotice: nil, loginItemNotice: nil, infoDictionary: nil
      ).github,
      github: githubWithToken,
      // The GitLab section too: this render is the crowded one on purpose,
      // every optional section at once, because that is the layout worth
      // doubting.
      gitLab: GitLabInstanceCards(cards: [
        GitLabInstanceAccess(
          instance: GitLabInstance(url: "https://gitlab.example.com")!,
          access: gitLabBeside)
      ])),
    to: directory.appendingPathComponent("0d-ajustes-con-token.png"),
    width: StandfastTheme.settingsPaneWidth,
    height: StandfastTheme.settingsAccountsHeight(gitLabInstances: 1))

  // 0e. Runners with one added, so the row and its Remove button are in the
  // picture.
  try render(
    RunnersSettingsPane(manualRunners: renderRunners(["/Users/ci/actions-runner-by-hand"])),
    to: directory.appendingPathComponent("0e-ajustes-runners.png"),
    width: StandfastTheme.settingsPaneWidth,
    height: StandfastTheme.settingsRunnersHeight(folders: 1))

  // 1. A runner GitHub cannot see, with work piling up behind it. The reason
  // somebody opens this window, and the sentence the queue line exists to make
  // possible: "disconnected" says what broke, "3 jobs are waiting for it" says
  // what that is costing. No screenshot of a healthy Mac contains this.
  let disconnected = try FleetSandbox(serviceRunning: true)
  defer { disconnected.cleanUp() }
  _ = try disconnected.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  disconnected.set(
    remote: .success(
      RemoteStatus(online: false, busy: false, labels: ["self-hosted", "macOS"])))
  disconnected.set(
    queued: .success(
      QueuedWork(
        jobs: (1...3).map {
          QueuedJob(
            id: $0, name: "build", workflowName: "CI", labels: ["self-hosted"],
            queuedAt: nil, url: nil)
        }, isPartial: false)))
  let disconnectedFleet = fleet(disconnected)
  await disconnectedFleet.quiesce()
  try render(
    detail(of: disconnectedFleet),
    to: directory.appendingPathComponent("A-desconectado.png"))

  // 2. A job running right now.
  let busy = try FleetSandbox(serviceRunning: true)
  defer { busy.cleanUp() }
  _ = try busy.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  busy.set(remote: .success(RemoteStatus(online: true, busy: true)))
  let busyFleet = fleet(busy)
  await busyFleet.quiesce()
  try render(
    detail(of: busyFleet),
    to: directory.appendingPathComponent("B-ejecutando.png"))

  // 3. The service is not running at all.
  let stopped = try FleetSandbox(serviceRunning: false)
  defer { stopped.cleanUp() }
  _ = try stopped.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  let stoppedFleet = fleet(stopped)
  await stoppedFleet.quiesce()
  try render(
    detail(of: stoppedFleet),
    to: directory.appendingPathComponent("C-detenido.png"))

  // 4. GitHub answered with an error: state that could not be read at all.
  let unreadable = try FleetSandbox(serviceRunning: true)
  defer { unreadable.cleanUp() }
  _ = try unreadable.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  unreadable.set(remote: .failure(.notAuthenticated))
  let unreadableFleet = fleet(unreadable)
  await unreadableFleet.quiesce()
  try render(
    detail(of: unreadableFleet),
    to: directory.appendingPathComponent("D-estado-ilegible.png"))

  // 3b. A runner nobody registered with launchd. Its controls are dead and the
  // card has to say why, which is the whole difference between a limitation
  // and a bug.
  let byHand = try FleetSandbox(serviceRunning: true)
  defer { byHand.cleanUp() }
  _ = try byHand.addManualRunner(name: "mac-mini-m4", scope: "acme-widget")
  let byHandFleet = fleet(byHand)
  await byHandFleet.quiesce()
  try render(
    detail(of: byHandFleet),
    to: directory.appendingPathComponent("C2-arrancado-a-mano.png"))

  // 3c. A GitLab runner beside a GitHub one, which must read like it: its
  // layer named GitLab, its own note on why the service controls are dead, and
  // the instance host where the scope would be.
  let mixed = try FleetSandbox(serviceRunning: true)
  defer { mixed.cleanUp() }
  _ = try mixed.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  try mixed.addGitLabRunner(name: "mac-gitlab", id: 91, host: "gitlab.example.com")
  let mixedFleet = fleet(mixed)
  await mixedFleet.quiesce()
  try render(
    detail(of: mixedFleet) { $0.group == .gitLab },
    to: directory.appendingPathComponent("C3-gitlab-junto-a-github.png"))

  // 4b. The other layer. `launchctl` refusing to say whether the service is
  // loaded is the one unknown whose instruction points at this Mac rather than
  // at GitHub, and since UI-034 the badge says so — in the longest words any
  // badge on this card carries, which is the reason to look at it rather than
  // assume it fits.
  let localUnreadable = try FleetSandbox()
  defer { localUnreadable.cleanUp() }
  _ = try localUnreadable.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  // `launchctl` that would not answer, which is what this state is.
  localUnreadable.set(serviceRunning: nil)
  let localUnreadableFleet = fleet(localUnreadable)
  await localUnreadableFleet.quiesce()
  try render(
    detail(of: localUnreadableFleet),
    to: directory.appendingPathComponent("D2-servicio-local-ilegible.png"))

  // 5. A Mac with nothing installed: the first thing a new user sees.
  let empty = try FleetSandbox()
  defer { empty.cleanUp() }
  let emptyFleet = fleet(empty)
  await emptyFleet.quiesce()
  let emptyPresentation = emptyFleet.controlCenterPresentation(now: Date())
  let emptyState = try #require(emptyPresentation.empty)
  try render(
    ControlCenterEmptyView(empty: emptyState, header: emptyPresentation.header),
    to: directory.appendingPathComponent("E-sin-runners.png"))
  try render(
    ControlCenterEmptyView(empty: emptyState, header: emptyPresentation.header),
    to: directory.appendingPathComponent("E-sin-runners.png"), appearance: .light)

  // 5b. Discovery that could not list where runners live: the path is the
  // whole message, so it has to fit and stay selectable.
  try render(
    ControlCenterEmptyView(
      empty: .launchAgentsUnavailable(directory: "~/Library/LaunchAgents"),
      header: emptyPresentation.header),
    to: directory.appendingPathComponent("E2-launchagents-ilegible.png"))

  // 5c. Forty runner files that would not read, at the window's least height:
  // the empty state scrolls, icon and title first, rather than run off the
  // window with its last paths.
  try render(
    ControlCenterEmptyView(
      empty: .unreadableRunners(
        paths: (1...40).map { "~/Library/LaunchAgents/actions.runner.acme.mac-\($0).plist" }
      ),
      header: emptyPresentation.header),
    to: directory.appendingPathComponent("E3-muchos-ilegibles.png"),
    height: StandfastTheme.controlCenterMinimumHeight)

  // 6. An action that fails. No `svc.sh` means the controller refuses before
  // running anything, which is the honest way to stage a failed Stop.
  let failing = try FleetSandbox(serviceRunning: true)
  defer { failing.cleanUp() }
  _ = try failing.addRunner(
    name: "mac-mini-m4", scope: "acme-widget", withScript: false)
  let failingFleet = fleet(failing)
  await failingFleet.quiesce()
  failingFleet.perform(.stop, onRunnerID: "actions.runner.acme-widget.mac-mini-m4")
  await failingFleet.quiesce()
  try render(
    detail(of: failingFleet),
    to: directory.appendingPathComponent("F-accion-fallida.png"))
  try render(
    detail(of: failingFleet),
    to: directory.appendingPathComponent("F-accion-fallida.png"), appearance: .light)

  // 7. The Overview with every kind of runner on it at once, a file discovery
  // could not read and a hot Mac: where somebody decides which runner to open.
  try render(
    ControlCenterOverview(
      presentation: crowdedOverview(),
      thermalLines: ThermalNotice.lines(pressure: .serious, overrunning: true),
      select: { _ in }),
    to: directory.appendingPathComponent("G-resumen.png"))
  try render(
    ControlCenterOverview(
      presentation: crowdedOverview(),
      thermalLines: ThermalNotice.lines(pressure: .serious, overrunning: true),
      select: { _ in }),
    to: directory.appendingPathComponent("G-resumen.png"), appearance: .light)

  // 7b. The same Overview as narrow as the detail gets: the window at its
  // least width with the sidebar at its widest. The columns have no room
  // there, and each reading goes under its runner's name.
  try render(
    ControlCenterOverview(
      presentation: crowdedOverview(),
      thermalLines: ThermalNotice.lines(pressure: .serious, overrunning: true),
      select: { _ in }),
    to: directory.appendingPathComponent("G2-resumen-estrecho.png"), width: 360)
}

/// One runner in each state the Overview orders by, on both services and a
/// fleet slot. Built from snapshots rather than a sandbox, which reads every
/// runner on it the same way.
private func crowdedOverview() -> ControlCenterPresentation {
  let now = Date()
  let gitLab = RunnerScope.gitLab(
    instance: GitLabInstance(url: "https://gitlab.example.com")!)
  func snapshot(
    _ name: String, _ display: DisplayState,
    scope: RunnerScope = .repository(owner: "acme", name: "widget"),
    installation: RunnerInstallation = .launchAgent
  ) -> RunnerSnapshot {
    RunnerSnapshot(
      runner: DiscoveredRunner(
        label: "actions.runner.acme-widget.\(name)",
        directory: URL(fileURLWithPath: "/tmp/\(name)"), agentId: 7,
        agentName: name, scope: scope, installation: installation),
      display: display, readAt: now)
  }
  let snapshots = [
    snapshot("mac-mini-m4", .resolved(.idle)),
    snapshot("mac-mini-m4-build", .resolved(.busy)),
    snapshot("deploy-mac", .resolved(.unknown(.noAnswer))),
    snapshot(
      "mac-gitlab", .resolved(.stopped), scope: gitLab, installation: .gitLabService),
    snapshot("test-mac", .resolved(.disconnected)),
    snapshot(
      "fleet-slot-1", .resolved(.unknown(.managedFleetWaiting)),
      scope: .organization("acme"), installation: .managedFleet),
  ]
  let overview = FleetOverviewPresentation.building(
    snapshots: snapshots,
    notice: .unreadable([
      URL(fileURLWithPath: "/Users/ci/Library/LaunchAgents/actions.runner.acme.old.plist")
    ]))
  return ControlCenterPresentation(
    header: .building(overview: overview, readAt: now, now: now),
    cards: snapshots.map {
      RunnerCardPresentation.building(
        $0, measurement: nil, latestRelease: nil, isMaintenanceWorking: false,
        maintenanceNotice: nil, now: now)
    },
    empty: nil, notice: .building(overview: overview))
}

/// A token that never leaves memory. The render harness must not read or write
/// the Keychain of whoever runs it.
private struct RenderTokenStore: GitHubTokenStoring {
  let stored: String?

  init(_ stored: String?) { self.stored = stored }

  func token() throws -> String? { stored }
  func store(_ token: String) throws {}
  func clear() throws {}
}

/// Read before it is drawn: the Keychain is read off the main actor, and a
/// card rendered first shows the state from before the read answered.
@MainActor
private func settledAccess(_ token: String?) async -> GitHubAccess {
  let access = GitHubAccess(store: RenderTokenStore(token))
  await access.quiesce()
  return access
}

/// Defaults nobody else shares, so a render cannot see — or leave — real
/// settings on the machine running it.
private func renderDefaults() -> UserDefaults {
  UserDefaults(suiteName: "standfast-render-\(UUID().uuidString)")!
}

@MainActor
private func renderRunners(_ paths: [String]) -> ManualRunnerDirectories {
  let subject = ManualRunnerDirectories(defaults: renderDefaults())
  for path in paths { subject.add(URL(fileURLWithPath: path)) }
  return subject
}
