import AppKit
import Foundation
import RunnerKit
import SwiftUI
import Testing

@testable import Standfast

/// Renders the Control Center in the states a screenshot of a working Mac
/// never shows.
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
  width: CGFloat = StandfastTheme.controlCenterDefaultWidth,
  height: CGFloat = 720,
  appearance: RenderAppearance = .dark
) throws {
  // The token, and it is the token because that is what was measured. This
  // used to say 640 with a note that macOS restores the Control Center wider
  // than the token asks. It does not. What was actually on that Mac was a
  // saved `NSWindow Frame control-center` of 640×720 from an earlier session;
  // delete it and the window opens at exactly the token, which is what anybody
  // installing this app for the first time sees.
  //
  // The other half of that note — that the header stacks vertically at 540 —
  // was true and is not any more. UI-041 made the header the short form, and
  // it now sits on one line beside Refresh at this width.
  let size = NSSize(width: width, height: height)
  let hosting = NSHostingView(
    rootView:
      view
      .frame(width: size.width, height: size.height)
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

@Test @MainActor func renderTheStatesAScreenshotOfAWorkingMacNeverShows() async throws {
  guard let directory = renderDirectory else { return }
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true)

  // 0. The everyday shape: two healthy runners, which is what the window looks
  // like on the Mac it was built against and the baseline every other state is
  // judged against.
  let healthy = try FleetSandbox(serviceRunning: true)
  defer { healthy.cleanUp() }
  _ = try healthy.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  _ = try healthy.addRunner(name: "mac-mini-m4-build", scope: "acme-tooling")
  let healthyFleet = fleet(healthy)
  await healthyFleet.quiesce()
  try render(
    ControlCenterView(fleet: healthyFleet),
    to: directory.appendingPathComponent("0-normal.png"))
  try render(
    ControlCenterView(fleet: healthyFleet),
    to: directory.appendingPathComponent("0-normal.png"), appearance: .light)

  // 0b. The other window. Settings takes its own size, not the Control
  // Center's.
  let githubWithout = await settledAccess(nil)
  try render(
    SettingsView(
      loginItem: LoginItem(), notifications: healthyFleet.notifications,
      sleep: healthyFleet.sleep, github: githubWithout,
      gitLab: GitLabInstanceCards(cards: []),
      manualRunners: ManualRunnerDirectories(defaults: renderDefaults()),
      dock: unattendedDockVisibility(),
      infoDictionary: ["CFBundleShortVersionString": "0.5.0", "CFBundleVersion": "5"]),
    to: directory.appendingPathComponent("0c-ajustes.png"),
    width: StandfastTheme.settingsIdealWidth,
    height: StandfastTheme.settingsDefaultHeight)

  // 0d. The same window on a Mac that has a token. The Remove button only
  // exists in this state, so the screenshot without it proves nothing about
  // whether it fits.
  let githubWithToken = await settledAccess("ghp_example")
  let gitLabBeside = await settledAccess(nil)
  try render(
    SettingsView(
      loginItem: LoginItem(), notifications: healthyFleet.notifications,
      sleep: healthyFleet.sleep,
      github: githubWithToken,
      // The GitLab card too: this render is the crowded one on purpose, every
      // optional section at once, because that is the layout worth doubting.
      gitLab: GitLabInstanceCards(cards: [
        GitLabInstanceAccess(
          instance: GitLabInstance(url: "https://gitlab.example.com")!,
          access: gitLabBeside)
      ]),
      // With one added, so the row and its Remove button are in the picture.
      manualRunners: renderRunners(["/Users/ci/actions-runner-by-hand"]),
      dock: unattendedDockVisibility(),
      infoDictionary: ["CFBundleShortVersionString": "0.5.0", "CFBundleVersion": "5"]),
    to: directory.appendingPathComponent("0d-ajustes-con-token.png"),
    width: StandfastTheme.settingsIdealWidth,
    height: StandfastTheme.settingsDefaultHeight)

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
    ControlCenterView(fleet: disconnectedFleet),
    to: directory.appendingPathComponent("A-desconectado.png"))

  // 2. A job running right now.
  let busy = try FleetSandbox(serviceRunning: true)
  defer { busy.cleanUp() }
  _ = try busy.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  busy.set(remote: .success(RemoteStatus(online: true, busy: true)))
  let busyFleet = fleet(busy)
  await busyFleet.quiesce()
  try render(
    ControlCenterView(fleet: busyFleet),
    to: directory.appendingPathComponent("B-ejecutando.png"))

  // 3. The service is not running at all.
  let stopped = try FleetSandbox(serviceRunning: false)
  defer { stopped.cleanUp() }
  _ = try stopped.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  let stoppedFleet = fleet(stopped)
  await stoppedFleet.quiesce()
  try render(
    ControlCenterView(fleet: stoppedFleet),
    to: directory.appendingPathComponent("C-detenido.png"))

  // 4. GitHub answered with an error: state that could not be read at all.
  let unreadable = try FleetSandbox(serviceRunning: true)
  defer { unreadable.cleanUp() }
  _ = try unreadable.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  unreadable.set(remote: .failure(.notAuthenticated))
  let unreadableFleet = fleet(unreadable)
  await unreadableFleet.quiesce()
  try render(
    ControlCenterView(fleet: unreadableFleet),
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
    ControlCenterView(fleet: byHandFleet),
    to: directory.appendingPathComponent("C2-arrancado-a-mano.png"))

  // 3c. A GitLab runner beside a GitHub one. The second provider's whole
  // pitch is that the same window answers the same question about both — so
  // the picture has to hold both: GitLab badge vocabulary, dead controls with
  // GitLab's own note, and the instance host where the scope would be.
  let mixed = try FleetSandbox(serviceRunning: true)
  defer { mixed.cleanUp() }
  _ = try mixed.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  try mixed.addGitLabRunner(name: "mac-gitlab", id: 91, host: "gitlab.example.com")
  let mixedFleet = fleet(mixed)
  await mixedFleet.quiesce()
  try render(
    ControlCenterView(fleet: mixedFleet),
    to: directory.appendingPathComponent("C3-gitlab-junto-a-github.png"),
    height: 900)

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
    ControlCenterView(fleet: localUnreadableFleet),
    to: directory.appendingPathComponent("D2-servicio-local-ilegible.png"))

  // 5. A Mac with nothing installed: the first thing a new user sees.
  let empty = try FleetSandbox()
  defer { empty.cleanUp() }
  let emptyFleet = fleet(empty)
  await emptyFleet.quiesce()
  try render(
    ControlCenterView(fleet: emptyFleet),
    to: directory.appendingPathComponent("E-sin-runners.png"))
  try render(
    ControlCenterView(fleet: emptyFleet),
    to: directory.appendingPathComponent("E-sin-runners.png"), appearance: .light)

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
    ControlCenterView(fleet: failingFleet),
    to: directory.appendingPathComponent("F-accion-fallida.png"))
  try render(
    ControlCenterView(fleet: failingFleet),
    to: directory.appendingPathComponent("F-accion-fallida.png"), appearance: .light)
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
