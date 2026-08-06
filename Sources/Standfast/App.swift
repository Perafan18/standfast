import RunnerKit
import SwiftUI

@main
struct StandfastApp: App {
  @StateObject private var fleet = RunnerFleetModel()
  @StateObject private var loginItem = LoginItem()
  /// Not handed to the model: how hot the Mac is has nothing to do with
  /// runners, and the one place the two meet is the menu line below.
  @StateObject private var thermal = ThermalMonitor()

  var body: some Scene {
    MenuBarExtra {
      FleetMenu(
        fleet: fleet, loginItem: loginItem, thermal: thermal,
        // Owned by the model, which is what makes "a scan produced an event"
        // testable. Observed separately because a nested `ObservableObject`
        // does not tell the view anything by itself.
        notifications: fleet.notifications, sleep: fleet.sleep,
        housekeeping: fleet.housekeeping)
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
  @ObservedObject var thermal: ThermalMonitor
  @ObservedObject var notifications: NotificationSettings
  @ObservedObject var sleep: SleepGuard
  @ObservedObject var housekeeping: HousekeepingModel

  var body: some View {
    // One section per runner. One runner reads as a flat menu; several read as
    // one group each, which is the only way per-runner buttons make sense.
    ForEach(fleet.snapshots) { snapshot in
      RunnerSection(
        snapshot: snapshot, fleet: fleet, housekeeping: housekeeping,
        latestRelease: fleet.latestRelease)
      Divider()
    }
    if let notice = fleet.notice {
      ForEach(notice.lines, id: \.self) { Text($0) }
      Divider()
    }
    // Empty unless macOS is actually throttling, which is the only time the
    // temperature explains anything the user can see.
    let heat = ThermalNotice.lines(
      pressure: thermal.pressure, overrunning: fleet.isOverrunning)
    if !heat.isEmpty {
      ForEach(heat, id: \.self) { Text($0) }
      Divider()
    }
    // `Date()` here rather than a stored value: this is the one line whose
    // whole job is to age, and the menu's body is re-evaluated when it opens,
    // which is the only moment anybody reads it.
    Text(FleetStatus.lastCheckedLine(readAt: fleet.lastReadAt, now: Date()))
    Button(L10n.refreshNow) { fleet.refresh() }
    Divider()
    // A submenu, so three switches nobody has turned on cost one row. The
    // permission prompt is not here: it belongs to the moment a switch goes on,
    // which is the first time this app has earned the right to ask.
    Menu(L10n.notifyMe) {
      ForEach(NotificationKind.allCases, id: \.self) { kind in
        Toggle(
          kind.menuLabel,
          isOn: Binding(
            get: { notifications.isEnabled(kind) },
            set: { notifications.setEnabled(kind, $0) }))
      }
      if let notice = notifications.notice { Text(notice) }
    }
    Toggle(
      L10n.preventSleep,
      isOn: Binding(get: { sleep.isEnabled }, set: { sleep.setEnabled($0) }))
    // Said only to somebody who has switched it on: `beginActivity` holds off
    // idle sleep and nothing else, and a MacBook whose lid is closed sleeps
    // anyway. Better here than discovered by a build that died overnight.
    if sleep.isEnabled { Text(L10n.preventSleepLidNotice) }
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
  let housekeeping: HousekeepingModel
  let latestRelease: RunnerVersion?

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
    // `Date()` here rather than a stored value, for the same reason the
    // last-checked line uses it: the only thing in here that ages is how old
    // the measurement is, and the menu's body is re-evaluated when it opens.
    let section = MaintenanceSection.building(
      snapshot, measurement: housekeeping.measurement(for: snapshot.runner),
      latest: latestRelease, isWorking: housekeeping.isWorking(on: snapshot.runner),
      notice: housekeeping.notice(for: snapshot.runner), now: Date())
    Menu(L10n.maintenance) {
      if let version = section.version { Text(version) }
      ForEach(section.usage, id: \.self) { Text($0) }
      Text(section.measured)
      Divider()
      ForEach(section.offers) { offer in
        Button(offer.label) { housekeeping.perform(offer.kind, on: snapshot) }
          .disabled(!offer.isEnabled)
      }
      ForEach(section.notes, id: \.self) { Text($0) }
    }
  }
}
