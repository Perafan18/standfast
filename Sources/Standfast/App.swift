import RunnerKit
import SwiftUI

@main
struct StandfastApp: App {
  @StateObject private var fleet = RunnerFleetModel()
  @StateObject private var loginItem = LoginItem()

  var body: some Scene {
    MenuBarExtra {
      FleetMenu(fleet: fleet, loginItem: loginItem)
    } label: {
      Image(systemName: FleetSummary.symbolName(for: fleet.snapshots.map(\.display)))
    }
  }
}

/// Renders what has already been decided elsewhere. Nothing in this file picks
/// a label, an enabled state or a line of text — `RunnerRow`, `FleetStatus`
/// and `FleetNotice.lines` do, where a test can read them. Every measured bug
/// this unit exists to prevent was a wiring bug, and wiring is all this file is.
private struct FleetMenu: View {
  @ObservedObject var fleet: RunnerFleetModel
  @ObservedObject var loginItem: LoginItem

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
    // `Date()` here rather than a stored value: this is the one line whose
    // whole job is to age, and the menu's body is re-evaluated when it opens,
    // which is the only moment anybody reads it.
    Text(FleetStatus.lastCheckedLine(readAt: fleet.lastReadAt, now: Date()))
    Button(L10n.refreshNow) { fleet.refresh() }
    Divider()
    Toggle(
      L10n.openAtLogin,
      isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
    if let notice = loginItem.notice { Text(notice) }
    Divider()
    Button(L10n.quit) { NSApplication.shared.terminate(nil) }
  }
}

private struct RunnerSection: View {
  let snapshot: RunnerSnapshot
  let fleet: RunnerFleetModel

  var body: some View {
    let row = snapshot.row
    Text(row.title)
    if let progress = row.progress { Text(progress) }
    ForEach(row.actions, id: \.kind) { action in
      Button(action.label) { fleet.perform(action.kind, on: snapshot.runner) }
        .disabled(!action.isEnabled)
    }
    // A submenu, not five more rows. A menu bar menu that has to be scrolled
    // has stopped being readable at a glance, which is the only thing it is
    // for.
    if !row.recentJobs.isEmpty {
      Menu(L10n.recentJobs) {
        ForEach(row.recentJobs) { Text($0.text) }
      }
    }
  }
}
