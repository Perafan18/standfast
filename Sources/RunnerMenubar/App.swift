import RunnerKit
import SwiftUI

@main
struct RunnerMenubarApp: App {
  @StateObject private var model = RunnerModel()

  var body: some Scene {
    MenuBarExtra {
      Text(model.statusLabel)
      Divider()
      Button("Arrancar") { model.start() }
        .disabled(model.summary == .idle || model.summary == .busy)
      Button("Parar") { model.stop() }
        .disabled(model.summary == .stopped)
      Button("Reiniciar") { model.restart() }
      Divider()
      Button("Abrir en GitHub") { model.openOnGitHub() }
        .disabled(model.runners.isEmpty)
      Button("Actualizar ahora") { model.refresh() }
      Divider()
      Button("Salir") { NSApplication.shared.terminate(nil) }
    } label: {
      Image(systemName: model.symbolName)
    }
  }
}

/// PROVISIONAL — Unit 5 replaces this whole file with the multi-runner UI.
///
/// It exists in this shape for one reason: `swift test` builds every target in
/// the package, so leaving this file broken after `RunnerService` was split
/// into discovery, probe, controller and GitHub client would mean not a single
/// test in the suite could run. The menu is the previous one verbatim, still in
/// Spanish, rewired with the least code that makes it true. Nothing here is
/// meant to survive.
///
/// The one behaviour change forced by discovery: there is no longer "the"
/// runner. The buttons act on every runner found, which on a one-runner
/// machine is exactly what they did before.
@MainActor
final class RunnerModel: ObservableObject {
  @Published private(set) var runners: [DiscoveredRunner] = []
  @Published private(set) var states: [RunnerState] = []

  private let discovery = RunnerDiscovery()
  private let resolver = RunnerStateResolver()
  private let controller = ServiceController()
  private var timer: Timer?

  init() {
    refresh()
    // 15s: fast enough that "did my build start?" is answered by looking up,
    // slow enough not to spend a GitHub API call every second all day.
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  /// Nil when this Mac has no runners at all, which is not an error state.
  var summary: RunnerState? { states.first }

  /// The icon carries the state, because that is the whole point of living in
  /// the menu bar: the answer should be readable without a click.
  var symbolName: String {
    switch summary {
    case .idle?: "checkmark.circle"
    case .busy?: "gearshape.2.fill"
    case .disconnected?: "exclamationmark.triangle"
    case .stopped?: "moon.zzz"
    case .unknown?, nil: "questionmark.circle"
    }
  }

  var statusLabel: String {
    switch summary {
    case .idle?: "Inactivo — listo para trabajos"
    case .busy?: "Ejecutando un job"
    // Named separately from "stopped" because the fix is different: the
    // process is alive but GitHub will not send it work.
    case .disconnected?: "Proceso vivo, pero GitHub no lo ve"
    case .stopped?: "Detenido"
    case .unknown(.cliUnavailable)?: "Desconocido — falta gh"
    case .unknown(.notAuthenticated)?: "Desconocido — gh sin credenciales"
    case .unknown(.noAnswer)?: "Desconocido — sin respuesta de GitHub"
    case nil: "No hay runners instalados"
    }
  }

  func refresh() {
    Task.detached { [discovery, resolver] in
      let found = discovery.discover()
      let states = found.runners.map { resolver.state(for: $0) }
      await MainActor.run {
        self.runners = found.runners
        self.states = states
      }
    }
  }

  func start() { act { try $0.start(in: $1.directory) } }
  func stop() { act { try $0.stop(in: $1.directory) } }
  func restart() { act { try await $0.restart(in: $1.directory) } }

  private func act(
    _ work: @escaping @Sendable (ServiceController, DiscoveredRunner) async throws -> Void
  ) {
    Task.detached { [controller, runners] in
      for runner in runners { try? await work(controller, runner) }
      // `svc.sh start` exits 0 even when the launchctl underneath it printed a
      // failure, so its exit code says nothing. Re-probing is the only honest
      // feedback, and launchd needs a moment before it answers truthfully.
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run { self.refresh() }
    }
  }

  func openOnGitHub() {
    guard let scope = runners.first?.scope else { return }
    NSWorkspace.shared.open(scope.settingsURL)
  }
}
