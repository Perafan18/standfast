import AppKit
import Foundation
import RunnerKit
import SwiftUI
import Testing

@testable import Standfast

@Test func controlCenterGeometryHoldsASidebarBesideTheDetail() {
  #expect(StandfastTheme.controlCenterMinimumWidth == 680)
  #expect(StandfastTheme.controlCenterMinimumHeight == 440)
  #expect(StandfastTheme.controlCenterDefaultWidth == 820)
  #expect(StandfastTheme.controlCenterDefaultHeight == 600)
  #expect(
    StandfastTheme.controlCenterDefaultWidth
      >= StandfastTheme.controlCenterMinimumWidth)
  #expect(
    StandfastTheme.controlCenterDefaultHeight
      >= StandfastTheme.controlCenterMinimumHeight)
}

// MARK: - UI-027: the disabled control is quiet, not invisible

@Test func aDisabledRunnerControlKeepsItsPlaceAndSaysWhy() {
  let source = standfastSource("ControlCenterView.swift")

  // Disabled, never removed: it keeps its place in the toolbar and its
  // identifier. Taking it out of the tree was a P0 in review, because the gate
  // and the manual matrix both assume a stable tree.
  #expect(source.contains(".disabled(!action.isEnabled)"))
  // And its tooltip gives this runner's reason rather than the verb again: a
  // greyed Start that says "Start build-mac" is a dead end.
  #expect(
    source.contains(
      ".help(action.isEnabled ? action.accessibilityLabel"
        + " : (card.serviceNote ?? card.state))"))
}

// MARK: - Motion, and the setting that switches it off

@Test func reduceMotionIsAnAbsenceOfAnimationAndNotAFasterOne() {
  // The whole contract: with the setting on, the caller gets nil and SwiftUI
  // cuts. A shortened duration is still motion, and this is an operational
  // tool — somebody who turned that setting on did not ask for a quicker
  // slide.
  #expect(
    StandfastTheme.Motion.honouring(StandfastTheme.Motion.receipt, reduceMotion: true)
      == nil)
  // And with it off the receipt arrives as it was drawn, not a cut-down one.
  #expect(
    StandfastTheme.Motion.honouring(StandfastTheme.Motion.receipt, reduceMotion: false)
      == StandfastTheme.Motion.receipt)
}

@Test func onlyReceiptsAreAnimatedAtAll() {
  let card = standfastSource("RunnerCardView.swift")
  let centre = standfastSource("ControlCenterView.swift")

  // State, enablement and freshness stay instantaneous. The window redraws
  // every two seconds inside a `TimelineView`, and a blanket `.animation` would
  // tween "Consultado ahora mismo": the age of the app's own data.
  #expect(card.contains("accessibilityReduceMotion"))
  #expect(card.contains("StandfastTheme.Motion.honouring"))
  #expect(!card.contains(".animation(.default"))
  // The window around the detail moves nothing at all.
  #expect(!centre.contains(".animation("))
  #expect(!centre.contains("withAnimation"))
}

// MARK: - The system draws the look, and one file asks which macOS this is

@Test func nativeLookSourceBans() {
  let names = standfastSourceNames()
  // An empty listing would pass every ban below without reading a line.
  for expected in [
    "StandfastTheme.swift", "ControlCenterView.swift", "RunnerCardView.swift",
    "SettingsView.swift", "QuickMenuView.swift",
  ] {
    #expect(names.contains(expected))
  }

  for name in names {
    let source = standfastSource(name)
    for drawn in ["glassEffect", "GlassEffectContainer"] {
      #expect(!source.contains(drawn), "\(name) draws glass the system should draw")
    }
    // A colour or type size of the app's own must be measured in every
    // appearance and contrast setting. System colours and text styles adapt by
    // themselves, so no file picks its own, the theme included.
    for custom in [
      "Color(.sRGB", "Color(red:", "Color(hue:", "Color(white:", "Material)",
      ".system(size:", "palette.",
    ] {
      #expect(!source.contains(custom), "\(name) picks a look the system should pick")
    }
    for block in toolbarContent(in: source) {
      #expect(!block.contains("#available"), "\(name) asks inside a toolbar builder")
    }
    guard name != "StandfastTheme.swift" else { continue }
    for check in ["#available", "#unavailable"] {
      #expect(!source.contains(check), "\(name) asks which macOS this is by itself")
    }
    for style in [".glassProminent", ".buttonStyle(.glass"] {
      #expect(!source.contains(style), "\(name) picks a glass button outside the theme")
    }
  }

  // The one place that may ask, so the bans above have something to protect.
  #expect(standfastSource("StandfastTheme.swift").contains("#available(macOS 26, *)"))
}

/// Every `.toolbar {` and `ToolbarContent {` body in a source, braces matched.
/// A version check in one warns on a macOS 14 target, and warnings fail CI.
private func toolbarContent(in source: String) -> [Substring] {
  [".toolbar {", "ToolbarContent {"].flatMap { opener in
    source.ranges(of: opener).map { found in
      var depth = 0
      var index = source.index(before: found.upperBound)
      while index < source.endIndex {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" { depth -= 1 }
        index = source.index(after: index)
        if depth == 0 { break }
      }
      return source[found.lowerBound..<index]
    }
  }
}

@Test func aSymbolOnlyTheMacOS26SDKHasStillBuildsOnXcode16() {
  // `#available` guards the running system, not the SDK, so outside a compiler
  // check one of these fails the build on the Xcode 16 the formula promises.
  let names = standfastSourceNames()
  #expect(names.contains("StandfastTheme.swift"))
  let newerSDK = [
    "safeAreaBar(", "ToolbarSpacer", "scrollEdgeEffectStyle", "backgroundExtensionEffect",
    ".glassProminent",
  ]

  for name in names {
    let source = standfastSource(name)
    for symbol in newerSDK {
      for found in source.ranges(of: symbol) {
        let opened = source[..<found.lowerBound].range(
          of: "#if compiler(>=6.2)", options: .backwards)
        let guarded = opened.map { opened in
          let between = source[opened.upperBound..<found.lowerBound]
          return !between.contains("#else") && !between.contains("#endif")
        }
        #expect(guarded == true, "\(name) names \(symbol) where Xcode 16 cannot build it")
      }
    }
  }
}

// MARK: - System colours, pinned as literals and never built from the mapping

@Test func theGitHubRowTellsANoApartFromNobodyKnowing() {
  // Offline is GitHub's answer, and it is no. Not answering, rate limited or
  // not asked is nobody knowing, and that runner may be fine.
  #expect(LayerTone.no.color == .red)
  #expect(LayerTone.unsure.color == .orange)
  #expect(LayerTone.ok.color == .green)
  #expect(LayerTone.working.color == .blue)
  #expect(LayerTone.off.color == .secondary)
}

@Test func theSummaryTonesKeepTheirSingleAttentionColour() {
  #expect(StateTone.healthy.color == .green)
  #expect(StateTone.active.color == .blue)
  #expect(StateTone.attention.color == .orange)
  #expect(StateTone.stopped.color == .secondary)
  #expect(StateTone.neutral.color == .secondary)
}

@Test func onlyAJobWhoseOwnStepsFailedIsRed() {
  func color(_ result: JobResult?) -> Color {
    JobRecord(name: "testflight", startedAt: .distantPast, result: result)
      .outcomePresentation.color
  }

  #expect(color(.failed) == .red)
  // Interrupted: the machine lost the job, which is attention and no verdict.
  #expect(color(nil) == .orange)
  #expect(color(.succeeded) == .green)
  #expect(color(.canceled) == .secondary)
  #expect(color(.other("Skipped")) == .secondary)
}

// MARK: - A bar of the app's own takes room only when it has something to say

@MainActor
private func fittedHeight(_ view: some View) -> CGFloat {
  NSHostingView(rootView: view.frame(width: 320)).fittingSize.height
}

@Test @MainActor func aBarWithNothingToSayTakesNoRoomOnEitherSideOf26() {
  // An empty `if` inside a padded bar measured 16 pt taller than no bar: a
  // strip of material over the form, about nothing. `standfastBar` is the 26
  // path on a newer Mac, `classicStandfastBar` what 14 and 15 draw.
  let quiet: String? = nil
  let hot: String? = "This Mac is under heavy thermal pressure"
  let content = Text("build-mac")
  let bare = fittedHeight(content)

  #expect(fittedHeight(content.standfastBar(.top, showing: quiet) { Text($0) }) == bare)
  #expect(
    fittedHeight(content.classicStandfastBar(.top, showing: quiet) { Text($0) }) == bare)
  #expect(fittedHeight(content.standfastBar(.top, showing: hot) { Text($0) }) > bare)
  #expect(
    fittedHeight(content.classicStandfastBar(.bottom, showing: hot) { Text($0) }) > bare)
}

@Test func everyFormFooterIsSetTheWayMacOS26SetsIt() {
  // macOS 14 and 15 put a footer's text at body size against the trailing
  // edge, where 26 sets it small from the leading one. Each footer of the
  // runner's page takes the style, and every Settings footer is one view.
  let card = standfastSource("RunnerCardView.swift")
  let settings = standfastSource("SettingsView.swift")
  let footers = card.components(separatedBy: "} footer: {").count - 1

  #expect(footers == 3)
  #expect(card.components(separatedBy: ".formFooterStyle()").count - 1 == footers)
  for block in settings.components(separatedBy: "} footer: {").dropFirst() {
    let content = block.prefix(while: { $0 != "}" })
    #expect(content.contains("supportingText(") || content.contains("SettingsFooter("))
  }
  #expect(settings.contains("    .formFooterStyle()\n  }\n}"))
  #expect(settings.contains("SettingsFooter(footer: presentation.footer"))
}
