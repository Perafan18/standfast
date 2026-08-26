import Foundation
import Testing

@testable import Standfast

@Test func measuredPalettesKeepEveryTextPairAtOrAboveAAContrast() {
  let dark = StandfastTheme.palette(for: .dark)
  let light = StandfastTheme.palette(for: .light)

  #expect(dark.textPrimary.contrastRatio(against: dark.surface) >= 4.5)
  #expect(dark.textSecondary.contrastRatio(against: dark.surface) >= 4.5)
  #expect(dark.attentionForeground.contrastRatio(against: dark.surface) >= 4.5)
  #expect(light.textPrimary.contrastRatio(against: light.surface) >= 4.5)
  #expect(light.textSecondary.contrastRatio(against: light.surface) >= 4.5)
  #expect(light.attentionForeground.contrastRatio(against: light.surface) >= 4.5)
  #expect(dark.primaryButtonText.contrastRatio(against: dark.primaryButton) >= 4.5)
  #expect(light.primaryButtonText.contrastRatio(against: light.primaryButton) >= 4.5)
}

@Test func contrastCompositesTransparentForegroundOverTheResolvedBackground() {
  let white = StandfastSRGBColor(hex: 0xFFFFFF)
  let transparentBlack = StandfastSRGBColor(hex: 0x000000, opacity: 0)
  let halfBlack = StandfastSRGBColor(hex: 0x000000, opacity: 0.5)

  #expect(transparentBlack.contrastRatio(against: white) == 1)
  #expect(abs(halfBlack.contrastRatio(against: white) - 3.97665) < 0.00001)
}

@Test func contrastResolvesTransparentBackgroundOverAnOpaqueBacking() {
  let black = StandfastSRGBColor(hex: 0x000000)
  let white = StandfastSRGBColor(hex: 0xFFFFFF)
  let transparentWhite = StandfastSRGBColor(hex: 0xFFFFFF, opacity: 0)

  #expect(StandfastSRGBColor.defaultContrastBacking == white)
  #expect(StandfastSRGBColor.defaultContrastBacking.opacity == 1)
  #expect(black.contrastRatio(against: transparentWhite) == 21)
  #expect(black.contrastRatio(against: transparentWhite, backing: black) == 1)
}

@Test func measuredPalettesKeepStructureAndControlsPerceivable() {
  let dark = StandfastTheme.palette(for: .dark)
  let light = StandfastTheme.palette(for: .light)

  #expect(dark.structuralBorder.contrastRatio(against: dark.surface) >= 3.0)
  #expect(light.structuralBorder.contrastRatio(against: light.surface) >= 3.0)
  #expect(dark.primaryButton.contrastRatio(against: dark.surface) >= 3.0)
  #expect(light.primaryButton.contrastRatio(against: light.surface) >= 3.0)
}

@Test func everyStateBadgeKeepsItsTextReadableWithoutRelyingOnColor() {
  let tones: [StateTone] = [.healthy, .active, .attention, .stopped, .neutral]

  for appearance in StandfastTheme.Appearance.allCases {
    let palette = StandfastTheme.palette(for: appearance)
    for tone in tones {
      let badge = palette.badge(for: tone)
      #expect(badge.foreground.contrastRatio(against: badge.background) >= 4.5)
      #expect(
        badge.border.contrastRatio(against: palette.surface) >= 3.0)
    }
  }
}

@Test func increasedContrastNeverWeakensTheStructuralBoundary() {
  for appearance in StandfastTheme.Appearance.allCases {
    let standard = StandfastTheme.palette(for: appearance)
    let increased = StandfastTheme.palette(for: appearance, increasedContrast: true)

    #expect(
      increased.structuralBorder.contrastRatio(against: increased.surface)
        >= standard.structuralBorder.contrastRatio(against: standard.surface))
  }
}

@Test func reducedTransparencyKeepsEverySurfaceFullyOpaque() {
  for appearance in StandfastTheme.Appearance.allCases {
    let standard = StandfastTheme.palette(for: appearance)
    let reduced = StandfastTheme.palette(for: appearance, reduceTransparency: true)

    #expect(standard.surface.opacity == 1.0)
    #expect(reduced.surface.opacity == 1.0)
  }
}

@Test func controlCenterGeometryPreservesTheMeasuredReadableWidth() {
  #expect(StandfastTheme.controlCenterMinimumWidth == 520)
  #expect(StandfastTheme.controlCenterDefaultWidth == 540)
  #expect(StandfastTheme.controlCenterDefaultHeight == 720)
  #expect(
    StandfastTheme.controlCenterDefaultWidth
      >= StandfastTheme.controlCenterMinimumWidth)
}

@Test func settingsGeometryStaysInsideTheCompactMeasuredRange() {
  #expect(StandfastTheme.settingsMinimumWidth == 460)
  #expect(StandfastTheme.settingsIdealWidth == 480)
  #expect(StandfastTheme.settingsMaximumWidth == 520)
  #expect(StandfastTheme.settingsDefaultHeight == 680)
  #expect(
    StandfastTheme.settingsMinimumWidth < StandfastTheme.settingsIdealWidth)
  #expect(
    StandfastTheme.settingsIdealWidth < StandfastTheme.settingsMaximumWidth)
}

@Test func spacingRadiiAndStrokesUseTheMeasuredTokenScale() {
  #expect(StandfastTheme.Spacing.all == [4, 8, 12, 16, 20, 24, 32])
  #expect(StandfastTheme.Radius.all == [10, 16])
  #expect(StandfastTheme.Stroke.structural == 1)
  #expect(StandfastTheme.Stroke.separator == 0.5)
}

// MARK: - UI-027: the disabled control is quiet, not invisible

@Test func theDisabledControlIsLegibleAndStillClearlyQuieter() {
  let dark = StandfastTheme.palette(for: .dark)
  let light = StandfastTheme.palette(for: .light)

  // A greyed control still has a job: its tooltip says why it cannot be
  // pressed, and somebody has to be able to read the label to know which
  // control that is. Measured in BOTH appearances, which is the trap the
  // agents' table documented — the 40% opacity first proposed measures
  // 2.71:1 on the dark surface and 1.89:1 on white.
  #expect(dark.controlTextDisabled.contrastRatio(against: dark.surface) >= 3)
  #expect(light.controlTextDisabled.contrastRatio(against: light.surface) >= 3)

  // And far enough below the enabled label that the difference is the first
  // thing you see, not something you work out by reading. `Arrancar` disabled
  // used to look almost exactly like `Parar` enabled.
  #expect(
    dark.textPrimary.contrastRatio(against: dark.surface)
      >= 3 * dark.controlTextDisabled.contrastRatio(against: dark.surface))
  #expect(
    light.textPrimary.contrastRatio(against: light.surface)
      >= 3 * light.controlTextDisabled.contrastRatio(against: light.surface))
}

@Test func theCardSpendsThatTokenOnTheControlsAndNotOnTheText() {
  let source = standfastSource("RunnerCardView.swift")

  // Tint only. The disabled button keeps its place in the layout and its
  // accessibility identifier: taking it out of the tree is what the review
  // called a P0, because the strict gate and the manual matrix both assume a
  // stable tree.
  #expect(source.contains("controlTextDisabled"))
  #expect(source.contains(".disabled(!action.isEnabled)"))
}

// MARK: - The failed receipt gets a colour of its own, measured on the surface

@Test func attentionOnSurfaceIsReadableWhereACardActuallyPutsIt() {
  let dark = StandfastTheme.palette(for: .dark)
  let light = StandfastTheme.palette(for: .light)

  // `attentionBackground` is the fill of a pill and `attentionForeground` is
  // what sits inside it — in dark mode that one is #FFF0DF, which against the
  // #F5F7F8 a title already uses measures 1.04:1. Recolouring a title with it
  // would be invisible. This token exists to be legible *on the surface*, and
  // it is a different value per appearance because a single one cannot be: the
  // dark candidate measures 2.06:1 on white.
  #expect(dark.attentionOnSurface.contrastRatio(against: dark.surface) >= 4.5)
  #expect(light.attentionOnSurface.contrastRatio(against: light.surface) >= 4.5)

  // And it has to beat the healthy badge it competes with in that frame,
  // which is the whole reason the failure was getting lost.
  #expect(
    dark.attentionOnSurface.contrastRatio(against: dark.surface)
      > dark.healthyBadge.contrastRatio(against: dark.surface))
}
