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

private struct FleetMenu: View {
  @ObservedObject var fleet: RunnerFleetModel

  var body: some View {
    // One section per runner. One runner reads as a flat menu; several read as
    // one group each, which is the only way the per-runner buttons make sense.
    ForEach(fleet.snapshots) { snapshot in
      RunnerSection(snapshot: snapshot, fleet: fleet)
      Divider()
    }
    if let notice = fleet.notice {
      NoticeSection(notice: notice)
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
    // `displayName`, not `agentName`: the `.runner` file does not always carry
    // a name, and that runner would render as a blank row followed by four
    // buttons belonging to nobody.
    Text("\(snapshot.runner.displayName) — \(snapshot.display.summary)")
    // Each button reads this runner's own state. Nothing here consults the
    // fleet summary, which is for the icon and only the icon.
    Button(L10n.start) { fleet.start(snapshot.runner) }
      .disabled(!snapshot.display.canStart)
    Button(L10n.stop) { fleet.stop(snapshot.runner) }
      .disabled(!snapshot.display.canStop)
    Button(L10n.restart) { fleet.restart(snapshot.runner) }
      .disabled(!snapshot.display.canRestart)
    Button(L10n.openOnGitHub) { fleet.openSettings(snapshot.runner) }
  }
}

private struct NoticeSection: View {
  let notice: FleetNotice

  var body: some View {
    switch notice {
    case .noRunnersInstalled:
      Text(L10n.noRunnersFound)
    case .unreadable(let paths):
      Text(L10n.someRunnersUnreadable)
      // The path, not the file name. Going and looking at the file is the
      // entire point of printing these, and the file name alone does not say
      // where it is.
      ForEach(paths, id: \.self) { path in
        Text((path.path as NSString).abbreviatingWithTildeInPath)
      }
    }
  }
}
