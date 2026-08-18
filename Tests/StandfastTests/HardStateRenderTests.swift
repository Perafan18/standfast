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

@MainActor
private func render(
  _ view: some View, to url: URL, width: CGFloat = 640, height: CGFloat = 720
) throws {
  // 640, not the 540 token: macOS restores the Control Center at 640 and that
  // is the width a person actually looks at. At 540 the header stacks
  // vertically, which would put a layout on screen that no user sees.
  let size = NSSize(width: width, height: height)
  let hosting = NSHostingView(
    rootView:
      view
      .frame(width: size.width, height: size.height)
      .environment(\.colorScheme, .dark))
  hosting.frame = NSRect(origin: .zero, size: size)
  hosting.layoutSubtreeIfNeeded()
  hosting.displayIfNeeded()
  let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
  hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: url)
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
    versions: sandbox.versions, releases: sandbox.releases, opener: FakeURLOpener(),
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

  // 0b. The other window. Settings takes its own size, not the Control
  // Center's.
  try render(
    SettingsView(
      loginItem: LoginItem(), notifications: healthyFleet.notifications,
      sleep: healthyFleet.sleep,
      infoDictionary: ["CFBundleShortVersionString": "0.5.0", "CFBundleVersion": "5"]),
    to: directory.appendingPathComponent("0c-ajustes.png"),
    width: StandfastTheme.settingsIdealWidth,
    height: StandfastTheme.settingsDefaultHeight)

  // 1. A runner GitHub cannot see. The reason somebody opens this window.
  let disconnected = try FleetSandbox(serviceRunning: true)
  defer { disconnected.cleanUp() }
  _ = try disconnected.addRunner(name: "mac-mini-m4", scope: "acme-widget")
  disconnected.set(remote: .success(RemoteStatus(online: false, busy: false)))
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

  // 5. A Mac with nothing installed: the first thing a new user sees.
  let empty = try FleetSandbox()
  defer { empty.cleanUp() }
  let emptyFleet = fleet(empty)
  await emptyFleet.quiesce()
  try render(
    ControlCenterView(fleet: emptyFleet),
    to: directory.appendingPathComponent("E-sin-runners.png"))

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
}
