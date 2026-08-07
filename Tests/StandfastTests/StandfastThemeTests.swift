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

@Test func spacingRadiiAndStrokesUseTheMeasuredTokenScale() {
  #expect(StandfastTheme.Spacing.all == [4, 8, 12, 16, 20, 24, 32])
  #expect(StandfastTheme.Radius.all == [10, 16])
  #expect(StandfastTheme.Stroke.structural == 1)
  #expect(StandfastTheme.Stroke.separator == 0.5)
}
