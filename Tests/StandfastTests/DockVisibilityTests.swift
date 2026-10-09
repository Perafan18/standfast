import AppKit
import Foundation
import Testing

@testable import Standfast

@MainActor
@Test func aFreshMacKeepsStandfastOutOfTheDock() {
  let policy = RecordingActivationPolicy()

  let dock = DockVisibility(policy: policy, defaults: scratchDefaults())

  // The bundle says `LSUIElement`, the icon lives in the menu bar, and the
  // strict gate refuses a build that takes a Dock tile it never asked for.
  // Somebody who wants the tile turns it on; nobody gets it by surprise.
  #expect(dock.isVisible == false)
  #expect(policy.applied == [.menuBarOnly])
}

@MainActor
@Test func turningItOnTakesTheDockTileAndRemembersIt() {
  let defaults = scratchDefaults()
  let policy = RecordingActivationPolicy()
  let dock = DockVisibility(policy: policy, defaults: defaults)

  dock.setVisible(true)

  #expect(dock.isVisible)
  #expect(policy.applied.last == .dock)
  #expect(defaults.bool(forKey: DockVisibility.defaultsKey))
}

@MainActor
@Test func turningItOffGivesTheTileBack() {
  let defaults = scratchDefaults()
  defaults.set(true, forKey: DockVisibility.defaultsKey)
  let policy = RecordingActivationPolicy()
  let dock = DockVisibility(policy: policy, defaults: defaults)

  dock.setVisible(false)

  #expect(dock.isVisible == false)
  #expect(policy.applied.last == .menuBarOnly)
  #expect(defaults.bool(forKey: DockVisibility.defaultsKey) == false)
}

@MainActor
@Test func theSettingIsAppliedAtLaunchAndNotWhenSomebodyOpensSettings() {
  let defaults = scratchDefaults()
  defaults.set(true, forKey: DockVisibility.defaultsKey)
  let policy = RecordingActivationPolicy()

  // A preference that only takes effect the next time you touch the switch is
  // a preference the app forgot. `LSUIElement` decides how the process starts;
  // this is what moves it afterwards, so it has to run at launch.
  _ = DockVisibility(policy: policy, defaults: defaults)

  #expect(policy.applied == [.dock])
}

@MainActor
@Test func settingsIsWhereTheDockTileIsTurnedOn() {
  let source = standfastSource("SettingsView.swift")

  // The switch has to be somewhere a user can find it without being told, and
  // Settings is the only surface in this app that holds preferences at all.
  #expect(source.contains("dock.setVisible"))
  #expect(source.contains("SettingsAccessibility.appearanceShowInDock"))
}

/// `NSApplication`, as far as the activation policy goes, down to the part
/// that matters here: leaving `.regular` deactivates the app.
@MainActor
private final class FakeApplication: ActivationPolicyApplying {
  private(set) var isActive: Bool
  private(set) var calls: [String] = []

  init(isActive: Bool) { self.isActive = isActive }

  func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
    calls.append(policy == .regular ? "regular" : "accessory")
    if policy == .accessory { isActive = false }
    return true
  }

  func activate() {
    calls.append("activate")
    isActive = true
  }
}

@MainActor
@Test func turningTheTileOffKeepsTheSettingsWindowInFront() {
  let application = FakeApplication(isActive: true)

  AppActivationPolicy(application: { application }).apply(.menuBarOnly)

  // The switch lives in Settings. Without the activation the previous app
  // comes forward over it, and with no tile and no ⌘-Tab entry the only way
  // back is the menu bar.
  #expect(application.calls == ["accessory", "activate"])
  #expect(application.isActive)
}

@MainActor
@Test func theLaunchTimeApplyNeverTakesFocusFromWhateverIsInFront() {
  let application = FakeApplication(isActive: false)

  AppActivationPolicy(application: { application }).apply(.menuBarOnly)

  #expect(application.calls == ["accessory"])
}
