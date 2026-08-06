import RunnerKit
import SwiftUI

@main
struct RunnerMenubarApp: App {
  @StateObject private var fleet = RunnerFleetModel()

  var body: some Scene {
    MenuBarExtra {
      FleetMenu(fleet: fleet)
    } label: {
      Image(systemName: FleetSummary.symbolName(for: fleet.snapshots.map(\.display)))
    }
  }
}

/// Renders what has already been decided elsewhere. Nothing in this file picks
/// a label, an enabled state or a line of text — `RunnerRow` and
/// `FleetNotice.lines` do, where a test can read them. Every measured bug this
/// unit exists to prevent was a wiring bug, and wiring is all this file is.
private struct FleetMenu: View {
  @ObservedObject var fleet: RunnerFleetModel

  var body: some View {
    // One section per runner. One runner reads as a flat menu; several read as
    // one group each, which is the only way per-runner buttons make sense.
    ForEach(fleet.snapshots) { snapshot in
      RunnerSection(snapshot: snapshot, fleet: fleet)
      Divider()
    }
    if let notice = fleet.notice {
      ForEach(notice.lines, id: \.self) { Text($0) }
      Divider()
    }
    Button(L10n.refreshNow) { fleet.refresh() }
    Button(L10n.quit) { NSApplication.shared.terminate(nil) }
  }
}

private struct RunnerSection: View {
  let snapshot: RunnerSnapshot
  let fleet: RunnerFleetModel

  var body: some View {
    let row = snapshot.row
    Text(row.title)
    ForEach(row.actions, id: \.kind) { action in
      Button(action.label) { fleet.perform(action.kind, on: snapshot.runner) }
        .disabled(!action.isEnabled)
    }
  }
}
