import AppKit
import SwiftUI

/// The selected runner, as the Runner menu and a sidebar row's context menu
/// read it. Slimmer than the card, which changes every two seconds while a job
/// runs: this changes only when what can be done to it does.
struct RunnerCommandTarget: Equatable {
  struct Action: Equatable, Identifiable {
    let kind: RunnerRow.Action.Kind
    let label: String
    let isEnabled: Bool

    var id: RunnerRow.Action.Kind { kind }
  }

  let id: String
  let title: String
  /// Start, Stop, Restart and the destination, named and enabled as the
  /// toolbar has them.
  let actions: [Action]
  /// Whether this runner has a log folder of its own. Which folder is the
  /// model's to find again, from the latest scan, when asked.
  let canShowLogs: Bool

  init(_ card: RunnerCardPresentation) {
    id = card.id
    title = card.title
    actions = card.actions.map {
      Action(kind: $0.kind, label: $0.label, isEnabled: $0.isEnabled)
    }
    canShowLogs = card.diagnosticsDirectory != nil
  }

  /// What a context menu offers: only what can be done now. It lists what
  /// applies to the row under the pointer, and a greyed line there has no
  /// tooltip to say why.
  var availableActions: [Action] { actions.filter(\.isEnabled) }

  /// Every kind, selected or not: a menu bar menu keeps its lines and greys
  /// what does not apply, so it can be learnt. Unselected, each wears its
  /// general name, which names no host: a Mac may run only GitLab.
  static func menuActions(for target: Self?) -> [Action] {
    RunnerRow.Action.Kind.allCases.map { kind in
      target?.actions.first { $0.kind == kind }
        ?? Action(kind: kind, label: generalLabel(kind), isEnabled: false)
    }
  }

  private static func generalLabel(_ kind: RunnerRow.Action.Kind) -> String {
    switch kind {
    case .start: L10n.serviceStart
    case .stop: L10n.serviceStop
    case .restart: L10n.serviceRestart
    case .openOnGitHub: L10n.openInBrowser
    }
  }
}

extension FocusedValues {
  /// The runner the key Control Center has selected. Nil on its Overview, in
  /// any other window, and with no Control Center open.
  var selectedRunner: RunnerCommandTarget? {
    get { self[SelectedRunnerKey.self] }
    set { self[SelectedRunnerKey.self] = newValue }
  }

  private struct SelectedRunnerKey: FocusedValueKey {
    typealias Value = RunnerCommandTarget
  }
}

/// The toolbar's twin in the menu bar, which shows while the Dock tile does.
/// Refresh takes no ⌘R here: the toolbar's button holds it, and that one
/// answers without a Dock tile too.
struct RunnerCommands: Commands {
  let fleet: RunnerFleetModel
  @FocusedValue(\.selectedRunner) private var runner

  var body: some Commands {
    CommandMenu(L10n.runnerMenu) {
      let actions = RunnerCommandTarget.menuActions(for: runner)
      ForEach(actions.filter { $0.kind != .openOnGitHub }) { item($0) }
      Divider()
      ForEach(actions.filter { $0.kind == .openOnGitHub }) { item($0) }
      Button(L10n.showLogsInFinder) {
        if let runner { fleet.showLogs(onRunnerID: runner.id) }
      }
      .disabled(runner?.canShowLogs != true)
      Divider()
      Button(L10n.refreshNow) { fleet.refresh() }
    }
  }

  /// Through the model, as the toolbar goes, so a Stop that would interrupt a
  /// job still asks first.
  private func item(_ action: RunnerCommandTarget.Action) -> some View {
    Button(action.label) {
      if let runner { fleet.perform(action.kind, onRunnerID: runner.id) }
    }
    .disabled(!action.isEnabled)
  }
}

/// A sidebar row's context menu: what can be done to that runner now, then
/// its logs and its name.
struct RunnerContextMenu: View {
  let target: RunnerCommandTarget
  let fleet: RunnerFleetModel

  var body: some View {
    // Through the model, as the toolbar goes, so a Stop that would interrupt a
    // job still asks first.
    ForEach(target.availableActions) { action in
      Button(action.label) { fleet.perform(action.kind, onRunnerID: target.id) }
    }
    Divider()
    if target.canShowLogs {
      Button(L10n.showLogsInFinder) { fleet.showLogs(onRunnerID: target.id) }
    }
    Button(L10n.copyName) { copy(target.title) }
  }

  private func copy(_ name: String) {
    let pasteboard = NSPasteboard.general
    // The pasteboard takes a write only once its old contents are cleared.
    pasteboard.clearContents()
    pasteboard.setString(name, forType: .string)
  }
}
