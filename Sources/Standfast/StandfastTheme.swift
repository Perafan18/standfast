import Foundation
import SwiftUI

struct StandfastSRGBColor: Equatable, Sendable {
  static let defaultContrastBacking = StandfastSRGBColor(hex: 0xFFFFFF)

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

  private init(red: Double, green: Double, blue: Double, opacity: Double) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
  }

  func contrastRatio(
    against background: Self,
    backing: Self = StandfastSRGBColor.defaultContrastBacking
  ) -> Double {
    precondition(backing.opacity == 1, "Contrast backing must be opaque")
    let resolvedBackground = background.composited(over: backing)
    let resolvedForeground = composited(over: resolvedBackground)
    let lighter = max(
      resolvedForeground.relativeLuminance,
      resolvedBackground.relativeLuminance)
    let darker = min(
      resolvedForeground.relativeLuminance,
      resolvedBackground.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func composited(over background: Self) -> Self {
    let resolvedOpacity = opacity + background.opacity * (1 - opacity)
    guard resolvedOpacity > 0 else {
      return Self(red: 0, green: 0, blue: 0, opacity: 0)
    }

    return Self(
      red: (red * opacity + background.red * background.opacity * (1 - opacity))
        / resolvedOpacity,
      green: (green * opacity + background.green * background.opacity * (1 - opacity))
        / resolvedOpacity,
      blue: (blue * opacity + background.blue * background.opacity * (1 - opacity))
        / resolvedOpacity,
      opacity: resolvedOpacity)
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
  /// What a card sits on. A window whose background is the same colour as its
  /// cards needs a border around every one of them to say where they end; give
  /// the cards a canvas and the surface does that work by itself.
  let canvas: StandfastSRGBColor
  let surface: StandfastSRGBColor
  let textPrimary: StandfastSRGBColor
  let textSecondary: StandfastSRGBColor
  /// The label of a control that cannot be pressed right now.
  ///
  /// A measured colour per appearance rather than an opacity, because an
  /// opacity is one number pretending to work in two places: 40% of
  /// `textSecondary` measures 2.71:1 on the dark surface and 1.89:1 on white.
  /// Both of these clear 3:1 and sit far below `textPrimary`, so a disabled
  /// control reads as off at a glance and still reads at all — its tooltip is
  /// the one thing that explains why it is off.
  let controlTextDisabled: StandfastSRGBColor
  let structuralBorder: StandfastSRGBColor
  /// A separator that groups and means nothing. Deliberately quieter than
  /// `structuralBorder`: when every line is drawn at the same weight, none of
  /// them tells you which boundary matters.
  let divider: StandfastSRGBColor
  let primaryButton: StandfastSRGBColor
  let primaryButtonText: StandfastSRGBColor
  let healthyBadge: StandfastSRGBColor
  let attentionForeground: StandfastSRGBColor
  let attentionBackground: StandfastSRGBColor
  /// Attention as it reads *on the card surface*, not inside a pill.
  ///
  /// `attentionForeground` is built to sit on `attentionBackground`; in dark
  /// mode it is nearly white, so a title recoloured with it changes by 1.04:1
  /// — invisible. One value per appearance because a single one cannot serve
  /// both: the dark candidate measures 2.06:1 on white.
  let attentionOnSurface: StandfastSRGBColor
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

  /// AppKit's own bordered push button reports an intrinsic height of 24 pt.
  /// The 44 pt this replaced is the iOS *touch* target, and on a pointer-driven
  /// Mac it makes every control read as a ported phone button. This keeps a few
  /// points of comfort over the system's own height without leaving it behind.
  /// The eight roles this app writes in, chosen once.
  ///
  /// Every view used to pick a system style by hand, which is how `scope`
  /// ended up at 11 pt under a 15 pt name, and how the badge — the only
  /// coloured object on a card — ended up the smallest text on screen.
  ///
  /// Semantic styles rather than fixed point sizes, deliberately: the manual
  /// accessibility matrix still owes the maximum-text-size axis, and
  /// `.system(size:)` would quietly opt this app out of it. The sizes in the
  /// comments are what macOS resolves them to at the default setting.
  enum Typography {
    /// 22 · the window's own answer, which has to outrank a runner's name.
    static let display = Font.title.weight(.semibold)
    /// 15 · a runner's name.
    static let title = Font.title3.weight(.semibold)
    /// 13 medium · the state or job in focus.
    static let bodyEmphasized = Font.body.weight(.medium)
    /// 13 · copy.
    static let body = Font.body
    /// 12 · scope, explanations, the detail under a receipt. Was 11.
    static let secondary = Font.callout
    /// 11 · freshness and durations, with digits that do not jitter.
    static let meta = Font.subheadline.monospacedDigit()
    /// 11 semibold · the pill. Was 10.
    static let badge = Font.subheadline.weight(.semibold)
    /// 10 · footers.
    static let micro = Font.caption
  }

  /// The two things that move, and the setting that stops them.
  ///
  /// Only presence and geometry are animated: a card folding, a receipt
  /// arriving. State, enablement, freshness and elapsed times stay
  /// instantaneous — the window redraws every two seconds inside a
  /// `TimelineView`, and interpolating any of that would mean tweening the
  /// age of the data on screen.
  enum Motion {
    /// 180 ms. Geometry, so it needs long enough to be followed by an eye.
    static let fold = Animation.easeOut(duration: 0.18)
    /// 140 ms. Presence, which only has to stop being abrupt.
    static let receipt = Animation.easeOut(duration: 0.14)

    /// Nil when Reduce Motion is on, which SwiftUI reads as "cut".
    ///
    /// Not a shorter duration: a quicker slide is still a slide, and somebody
    /// who turned that setting on did not ask for a faster one.
    static func honouring(_ animation: Animation, reduceMotion: Bool) -> Animation? {
      reduceMotion ? nil : animation
    }
  }

  static let controlMinimumHeight: CGFloat = 28

  static let controlCenterMinimumWidth: CGFloat = 520
  static let controlCenterDefaultWidth: CGFloat = 540
  static let controlCenterDefaultHeight: CGFloat = 720
  static let settingsMinimumWidth: CGFloat = 460
  static let settingsIdealWidth: CGFloat = 480
  static let settingsMaximumWidth: CGFloat = 520
  static let settingsDefaultHeight: CGFloat = 680

  static func palette(
    for appearance: Appearance, increasedContrast: Bool = false,
    reduceTransparency _: Bool = false
  ) -> StandfastPalette {
    switch appearance {
    case .dark:
      StandfastPalette(
        canvas: StandfastSRGBColor(hex: 0x121518),
        surface: StandfastSRGBColor(hex: 0x1B2024),
        textPrimary: StandfastSRGBColor(hex: 0xF5F7F8),
        textSecondary: StandfastSRGBColor(hex: 0xC2C8CE),
        // 3.47:1 against surface — `textSecondary` at 50%, resolved to a hex.
        controlTextDisabled: StandfastSRGBColor(hex: 0x6E7479),
        structuralBorder: StandfastSRGBColor(
          hex: increasedContrast ? 0x8996A1 : 0x6E7B86),
        // 1.65:1 against the card — enough to group, too little to compete.
        divider: StandfastSRGBColor(hex: 0x3A444D),
        // The candidate 0A5FC7 misses 3:1 against the dark surface. This is
        // the nearest measured step that clears that boundary and keeps white
        // button copy above 4.5:1.
        primaryButton: StandfastSRGBColor(hex: 0x0A66D2),
        primaryButtonText: StandfastSRGBColor(hex: 0xFFFFFF),
        healthyBadge: StandfastSRGBColor(hex: 0x0D6B39),
        attentionForeground: StandfastSRGBColor(hex: 0xFFF0DF),
        attentionBackground: StandfastSRGBColor(hex: 0xB04B00),
        // 7.99:1 against surface, and it beats the healthy badge (2.49:1) it
        // was losing to in the failed-action frame.
        attentionOnSurface: StandfastSRGBColor(hex: 0xFF9F0A),
        stoppedBadge: StandfastSRGBColor(hex: 0x4F5B66))
    case .light:
      StandfastPalette(
        canvas: StandfastSRGBColor(hex: 0xF4F6F8),
        surface: StandfastSRGBColor(hex: 0xFFFFFF),
        textPrimary: StandfastSRGBColor(hex: 0x14171A),
        textSecondary: StandfastSRGBColor(hex: 0x4F5B66),
        // 3.41:1 against white — the same perceptual weight as the dark one,
        // which needed a different opacity to get there.
        controlTextDisabled: StandfastSRGBColor(hex: 0x848C94),
        structuralBorder: StandfastSRGBColor(
          hex: increasedContrast ? 0x4F5B66 : 0x65717C),
        divider: StandfastSRGBColor(hex: 0xD7DEE5),
        primaryButton: StandfastSRGBColor(hex: 0x005AC6),
        primaryButtonText: StandfastSRGBColor(hex: 0xFFFFFF),
        healthyBadge: StandfastSRGBColor(hex: 0x0D6B39),
        attentionForeground: StandfastSRGBColor(hex: 0x853800),
        attentionBackground: StandfastSRGBColor(hex: 0xFFF0DF),
        // 8.19:1 on white. The dark orange would be 2.06:1 here.
        attentionOnSurface: StandfastSRGBColor(hex: 0x853800),
        stoppedBadge: StandfastSRGBColor(hex: 0xDCE2E7))
    }
  }
}

enum ControlCenterAccessibility {
  static let header = "dev.standfast.control-center.header"
  static let refresh = "dev.standfast.control-center.refresh"
  static let notice = "dev.standfast.control-center.notice"
  static let installGuide = "dev.standfast.control-center.install-guide"

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
    /// The control that folds this card. Hung off `card` rather than the
    /// identity row it sits in: the row keeps its own status identity, and a
    /// fold has to stay reachable by name when everything below it is hidden.
    var fold: String { "\(card).fold" }
    var status: String { "\(root).status" }
    var focus: String { "\(root).focus" }
    var queue: String { "\(root).queue" }
    var start: String { "\(root).action.start" }
    var stop: String { "\(root).action.stop" }
    var restart: String { "\(root).action.restart" }
    var github: String { "\(root).github" }
    var jobs: String { "\(root).jobs" }
    var maintenance: String { "\(root).maintenance" }

    func maintenanceAction(_ kind: MaintenanceOffer.Kind) -> String {
      let stableKind =
        switch kind {
        case .measure: "measure"
        case .cleanToolCache: "clean-tool-cache"
        case .cleanActionCache: "clean-action-cache"
        case .cleanStandfastTrash: "clean-standfast-trash"
        case .trimLogs: "trim-logs"
        }
      return "\(maintenance).action.\(stableKind)"
    }

    func job(_ identity: JobRow.ID) -> String {
      let stableTime = String(
        format: "%016llx", identity.startedAt.timeIntervalSinceReferenceDate.bitPattern)
      return "\(jobs).job.\(stableTime).\(identity.occurrence)"
    }
  }
}
