import SwiftUI

@main
struct RunnerMenubarApp: App {
  @StateObject private var model = RunnerModel()

  var body: some Scene {
    MenuBarExtra {
      Text(model.statusLabel)
      Divider()
      Button("Arrancar") { model.start() }
        .disabled(model.state == .idle || model.state == .busy)
      Button("Parar") { model.stop() }
        .disabled(model.state == .stopped)
      Button("Reiniciar") { model.restart() }
      Divider()
      Button("Abrir en GitHub") { model.openOnGitHub() }
      Button("Actualizar ahora") { model.refresh() }
      Divider()
      Button("Salir") { NSApplication.shared.terminate(nil) }
    } label: {
      Image(systemName: model.symbolName)
    }
  }
}

@MainActor
final class RunnerModel: ObservableObject {
  @Published private(set) var state: RunnerState = .unknown("iniciando")

  private let service = RunnerService(
    runnerDirectory: FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("actions-runner"),
    repository: "Perafan18/nest-rules-app"
  )
  private var timer: Timer?

  init() {
    refresh()
    // 15s: fast enough that "did my build start?" is answered by looking up,
    // slow enough not to spend a GitHub API call every second all day.
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) {
      [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  /// The icon carries the state, because that is the whole point of living in
  /// the menu bar: the answer should be readable without a click.
  var symbolName: String {
    switch state {
    case .idle: return "checkmark.circle"
    case .busy: return "gearshape.2.fill"
    case .disconnected: return "exclamationmark.triangle"
    case .stopped: return "moon.zzz"
    case .unknown: return "questionmark.circle"
    }
  }

  var statusLabel: String {
    switch state {
    case .idle: return "Inactivo — listo para trabajos"
    case .busy: return "Ejecutando un job"
    case .disconnected:
      // Named separately from "stopped" because the fix is different: the
      // process is alive but GitHub will not send it work.
      return "Proceso vivo, pero GitHub no lo ve"
    case .stopped: return "Detenido"
    case .unknown(let why): return "Desconocido — \(why)"
    }
  }

  func refresh() {
    Task.detached { [service] in
      let next = service.currentState()
      await MainActor.run { self.state = next }
    }
  }

  func start() { act { _ = self.service.start() } }
  func stop() { act { _ = self.service.stop() } }
  func restart() { act { _ = self.service.restart() } }

  private func act(_ work: @escaping @Sendable () -> Void) {
    Task.detached {
      work()
      // svc.sh returns before launchd has settled, so an immediate refresh
      // reports the state we just left.
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      await MainActor.run { self.refresh() }
    }
  }

  func openOnGitHub() {
    guard
      let url = URL(
        string:
          "https://github.com/Perafan18/nest-rules-app/settings/actions/runners"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}
