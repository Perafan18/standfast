import Foundation
import SwiftUI

struct StandfastSRGBColor: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double
  let opacity: Double

  init(hex: UInt32, opacity: Double = 1) {
    red = Double((hex >> 16) & 0xFF) / 255
    green = Double((hex >> 8) & 0xFF) / 255
    blue = Double(hex & 0xFF) / 255
    self.opacity = opacity
  }

  var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
  }

  func contrastRatio(against other: Self) -> Double {
    let lighter = max(relativeLuminance, other.relativeLuminance)
    let darker = min(relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private var relativeLuminance: Double {
    let components = [red, green, blue].map { component in
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * components[0] + 0.7152 * components[1]
      + 0.0722 * components[2]
  }
}

struct StandfastPalette: Equatable, Sendable {
  let surface: StandfastSRGBColor
  let textPrimary: StandfastSRGBColor
  let textSecondary: StandfastSRGBColor
  let structuralBorder: StandfastSRGBColor
  let primaryButton: StandfastSRGBColor
  let primaryButtonText: StandfastSRGBColor
  let healthyBadge: StandfastSRGBColor
  let attentionForeground: StandfastSRGBColor
  let attentionBackground: StandfastSRGBColor
  let stoppedBadge: StandfastSRGBColor

  struct Badge: Equatable, Sendable {
    let foreground: StandfastSRGBColor
    let background: StandfastSRGBColor
    let border: StandfastSRGBColor
  }

  func badge(for tone: StateTone) -> Badge {
    let colors: (StandfastSRGBColor, StandfastSRGBColor) =
      switch tone {
      case .healthy: (primaryButtonText, healthyBadge)
      case .active: (primaryButtonText, primaryButton)
      case .attention: (attentionForeground, attentionBackground)
      case .stopped, .neutral: (textPrimary, stoppedBadge)
      }
    return Badge(
      foreground: colors.0, background: colors.1, border: structuralBorder)
  }
}

enum StandfastTheme {
  enum Appearance: CaseIterable {
    case light, dark
  }

  enum Spacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let compact: CGFloat = 12
    static let standard: CGFloat = 16
    static let roomy: CGFloat = 20
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let all = [xSmall, small, compact, standard, roomy, large, xLarge]
  }

  enum Radius {
    static let compact: CGFloat = 10
    static let surface: CGFloat = 16
    static let all = [compact, surface]
  }

  enum Stroke {
    static let structural: CGFloat = 1
    static let separator: CGFloat = 0.5
  }

  static let controlCenterMinimumWidth: CGFloat = 520
  static let controlCenterDefaultWidth: CGFloat = 540
  static let controlCenterDefaultHeight: CGFloat = 720

  static func palette(
    for appearance: Appearance, increasedContrast: Bool = false,
    reduceTransparency _: Bool = false
  ) -> StandfastPalette {
    switch appearance {
    case .dark:
      StandfastPalette(
        surface: StandfastSRGBColor(hex: 0x1B2024),
        textPrimary: StandfastSRGBColor(hex: 0xF5F7F8),
        textSecondary: StandfastSRGBColor(hex: 0xC2C8CE),
        structuralBorder: StandfastSRGBColor(
          hex: increasedContrast ? 0x8996A1 : 0x6E7B86),
        // The candidate 0A5FC7 misses 3:1 against the dark surface. This is
        // the nearest measured step that clears that boundary and keeps white
        // button copy above 4.5:1.
        primaryButton: StandfastSRGBColor(hex: 0x0A66D2),
        primaryButtonText: StandfastSRGBColor(hex: 0xFFFFFF),
        healthyBadge: StandfastSRGBColor(hex: 0x0D6B39),
        attentionForeground: StandfastSRGBColor(hex: 0xFFF0DF),
        attentionBackground: StandfastSRGBColor(hex: 0xB04B00),
        stoppedBadge: StandfastSRGBColor(hex: 0x4F5B66))
    case .light:
      StandfastPalette(
        surface: StandfastSRGBColor(hex: 0xFFFFFF),
        textPrimary: StandfastSRGBColor(hex: 0x14171A),
        textSecondary: StandfastSRGBColor(hex: 0x4F5B66),
        structuralBorder: StandfastSRGBColor(
          hex: increasedContrast ? 0x4F5B66 : 0x65717C),
        primaryButton: StandfastSRGBColor(hex: 0x005AC6),
        primaryButtonText: StandfastSRGBColor(hex: 0xFFFFFF),
        healthyBadge: StandfastSRGBColor(hex: 0x0D6B39),
        attentionForeground: StandfastSRGBColor(hex: 0x853800),
        attentionBackground: StandfastSRGBColor(hex: 0xFFF0DF),
        stoppedBadge: StandfastSRGBColor(hex: 0xDCE2E7))
    }
  }
}

enum ControlCenterAccessibility {
  static let header = "dev.standfast.control-center.header"
  static let refresh = "dev.standfast.control-center.refresh"
  static let notice = "dev.standfast.control-center.notice"

  static func runner(_ durableLabel: String) -> RunnerIdentifiers {
    RunnerIdentifiers(encodedLabel: stableHex(durableLabel.utf8))
  }

  private static func stableHex(_ bytes: String.UTF8View) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  struct RunnerIdentifiers: Equatable {
    fileprivate let encodedLabel: String

    private var root: String {
      "dev.standfast.control-center.runner.\(encodedLabel)"
    }

    var card: String { "\(root).card" }
    var status: String { "\(root).status" }
    var focus: String { "\(root).focus" }
    var start: String { "\(root).action.start" }
    var stop: String { "\(root).action.stop" }
    var restart: String { "\(root).action.restart" }
    var github: String { "\(root).github" }
    var jobs: String { "\(root).jobs" }
    var maintenance: String { "\(root).maintenance" }

    func job(_ startedAt: Date) -> String {
      let stableTime = String(
        format: "%016llx", startedAt.timeIntervalSinceReferenceDate.bitPattern)
      return "\(jobs).job.\(stableTime)"
    }
  }
}
