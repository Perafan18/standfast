import AppKit
import SwiftUI

enum SceneTarget: Hashable, Sendable {
  case controlCenter
  case settings

  var accessibilityIdentifier: String {
    switch self {
    case .controlCenter:
      "dev.standfast.scene.control-center"
    case .settings:
      "dev.standfast.scene.settings"
    }
  }
}

@MainActor
final class SceneWindowRegistry {
  private final class WeakWindow {
    weak var value: NSWindow?

    init(_ value: NSWindow) {
      self.value = value
    }
  }

  private var windows: [SceneTarget: WeakWindow] = [:]

  func register(_ window: NSWindow, for target: SceneTarget) {
    window.setAccessibilityIdentifier(target.accessibilityIdentifier)
    windows[target] = WeakWindow(window)
  }

  func window(for target: SceneTarget) -> NSWindow? {
    guard let window = windows[target]?.value else {
      windows.removeValue(forKey: target)
      return nil
    }
    guard window.accessibilityIdentifier() == target.accessibilityIdentifier else {
      windows.removeValue(forKey: target)
      return nil
    }
    return window
  }

  func unregister(_ window: NSWindow, for target: SceneTarget) {
    guard windows[target]?.value === window else { return }
    windows.removeValue(forKey: target)
  }
}

/// Installs a locale-independent identity on the `NSWindow` materialised for a scene.
@MainActor
struct SceneWindowProbe: NSViewRepresentable {
  let target: SceneTarget
  let registry: SceneWindowRegistry

  func makeNSView(context: Context) -> SceneWindowRegistrationView {
    let view = SceneWindowRegistrationView(frame: .zero)
    view.update(target: target, registry: registry)
    return view
  }

  func updateNSView(_ view: SceneWindowRegistrationView, context: Context) {
    view.update(target: target, registry: registry)
  }

  static func dismantleNSView(
    _ view: SceneWindowRegistrationView,
    coordinator: ()
  ) {
    view.unregisterCurrentWindow()
  }
}

@MainActor
final class SceneWindowRegistrationView: NSView {
  private var target: SceneTarget?
  private var registry: SceneWindowRegistry?
  private weak var registeredWindow: NSWindow?

  func update(target: SceneTarget, registry: SceneWindowRegistry) {
    if self.target != target || self.registry !== registry {
      unregisterCurrentWindow()
    }
    self.target = target
    self.registry = registry
    registerCurrentWindow()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if registeredWindow !== window {
      unregisterCurrentWindow()
    }
    registerCurrentWindow()
  }

  func unregisterCurrentWindow() {
    guard let registeredWindow, let target, let registry else { return }
    registry.unregister(registeredWindow, for: target)
    self.registeredWindow = nil
  }

  private func registerCurrentWindow() {
    guard registeredWindow == nil, let window, let target, let registry else { return }
    registry.register(window, for: target)
    registeredWindow = window
  }
}
