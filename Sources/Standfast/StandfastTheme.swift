import Foundation
import SwiftUI

enum StandfastTheme {
  /// The one thing that moves, and the setting that stops it.
  ///
  /// Only presence is animated: a receipt arriving. State, enablement,
  /// freshness and elapsed times stay instantaneous — the window redraws every
  /// two seconds inside a `TimelineView`, and interpolating any of that would
  /// mean tweening the age of the data on screen.
  enum Motion {
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

  /// A sidebar of runners beside one runner's detail. The minimum is where the
  /// two still fit side by side.
  static let controlCenterMinimumWidth: CGFloat = 680
  static let controlCenterMinimumHeight: CGFloat = 440
  static let controlCenterDefaultWidth: CGFloat = 820
  static let controlCenterDefaultHeight: CGFloat = 600

  /// Settings has one width on every pane and a height per pane: under
  /// `.contentSize` a form with no height collapses. Heights are measured from
  /// renders on macOS 27 in Spanish, General with both notices showing.
  static let settingsPaneWidth: CGFloat = 520
  /// With the title bar and tabs on top, the window is taller than a 1280×720
  /// display. See `settingsPaneHeight` for what a short display gets.
  static let settingsGeneralHeight: CGFloat = 690

  /// What a Settings window adds above its pane: the title bar and the tabs.
  /// On the generous side, since 26 draws both taller: a pane a little shorter
  /// than it could be scrolls, and one a little taller falls off the screen.
  static let settingsWindowChrome: CGFloat = 100
  /// The least a pane is cut to: below this a form shows a row or two.
  static let settingsMinimumPaneHeight: CGFloat = 300

  /// A pane's measured height, or what a short display leaves under the
  /// window's chrome. Under `.contentSize` the window is never shorter than its
  /// pane, so on a 13" MacBook Air at Larger Text, 1024×640, the bottom of
  /// General fell below the screen with switches in it, out of reach. There
  /// the form scrolls instead. Each pane stays one fixed height, so the window
  /// still takes each pane's own size when the tabs switch.
  static func settingsPaneHeight(_ measured: CGFloat, screenHeight: CGFloat?) -> CGFloat {
    guard let screenHeight else { return measured }
    return min(
      measured, max(screenHeight - settingsWindowChrome, settingsMinimumPaneHeight))
  }

  /// One folder fits where the empty line does, then a row each. Past General's
  /// height the form scrolls, so no pane makes the window taller than General.
  static func settingsRunnersHeight(folders: Int) -> CGFloat {
    min(230 + 56 * CGFloat(max(folders - 1, 0)), settingsGeneralHeight)
  }

  /// GitHub with a token and a notice, then a section per GitLab instance, up
  /// to General's height.
  static func settingsAccountsHeight(gitLabInstances: Int) -> CGFloat {
    min(300 + 280 * CGFloat(gitLabInstances), settingsGeneralHeight)
  }
}

// MARK: - What differs between macOS versions, and nothing else

// Every version check lives in this file, of the macOS running and of the SDK
// built against. On 26 and later the system draws glass on the standard
// sidebar, toolbar, menus and alerts; views ask for none.

extension View {
  /// The one action a toolbar puts forward: bordered prominent, not a glass
  /// style. It takes a `ToolbarItem` of its own, out of any group. On macOS
  /// 27 the system draws it as a tinted glass circle on a platter of its own,
  /// beside its neighbours' shared one, not glass on glass (2026-10-12, a
  /// stopped runner's Start). Unchecked on 26.
  @ViewBuilder func primaryToolbarActionStyle(_ isPrimary: Bool) -> some View {
    if isPrimary {
      buttonStyle(.borderedProminent)
    } else {
      self
    }
  }

  /// A bar along a window edge, there only while `item` is: padding around an
  /// empty `if` still takes room. On 26 and later it gets the toolbar's
  /// scroll-edge effect and is not glass; before, the bar material.
  @ViewBuilder func standfastBar<Item, Bar: View>(
    _ edge: VerticalEdge, showing item: Item?, @ViewBuilder content: (Item) -> Bar
  ) -> some View {
    // `#available` asks the running system, not the SDK, and only the macOS 26
    // SDK has `safeAreaBar`. It came with Swift 6.2, so Xcode 16, which the
    // formula still promises, builds the classic bar.
    #if compiler(>=6.2)
      if #available(macOS 26, *) {
        safeAreaBar(edge: edge, spacing: 0) {
          if let item { content(item).standfastBarLayout() }
        }
      } else {
        classicStandfastBar(edge, showing: item, content: content)
      }
    #else
      classicStandfastBar(edge, showing: item, content: content)
    #endif
  }

  /// What `standfastBar` draws before 26, reachable on its own so a test on a
  /// newer Mac can still lay it out.
  func classicStandfastBar<Item, Bar: View>(
    _ edge: VerticalEdge, showing item: Item?, @ViewBuilder content: (Item) -> Bar
  ) -> some View {
    safeAreaInset(edge: edge, spacing: 0) {
      if let item {
        content(item)
          .standfastBarLayout()
          .background(.bar)
          .overlay(alignment: edge == .top ? .bottom : .top) { Divider() }
      }
    }
  }

  private func standfastBarLayout() -> some View {
    padding(.horizontal)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Semantic colours, which the system adapts to every appearance

// System colours only, and each is drawn beside a symbol and text, so the
// colour is never the only thing saying it.

extension StateTone {
  var color: Color {
    switch self {
    case .healthy: .green
    case .active: .blue
    case .attention: .orange
    case .stopped, .neutral: .secondary
    }
  }
}

extension LayerTone {
  var color: Color {
    switch self {
    case .ok: .green
    case .working: .blue
    case .no: .red
    case .unsure: .orange
    case .off: .secondary
    }
  }
}

extension JobOutcomePresentation {
  /// The tone's colour, except that a failed job is red: the one outcome that
  /// is a verdict on the code rather than on this Mac.
  var color: Color {
    isFailure ? .red : tone.color
  }
}

enum ControlCenterAccessibility {
  static let header = "dev.standfast.control-center.header"
  /// The sidebar row that opens the whole fleet rather than one runner.
  static let overview = "dev.standfast.control-center.overview"
  static let refresh = "dev.standfast.control-center.refresh"
  static let notice = "dev.standfast.control-center.notice"
  /// The Mac's heat, on the Overview or over the runner whose job it slows.
  static let thermal = "dev.standfast.control-center.thermal"
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
    /// This runner's row in the sidebar, which stays when another is selected.
    var sidebar: String { "\(root).sidebar" }
    var status: String { "\(root).status" }
    var focus: String { "\(root).focus" }
    var queue: String { "\(root).queue" }
    var start: String { "\(root).action.start" }
    var stop: String { "\(root).action.stop" }
    var restart: String { "\(root).action.restart" }
    var github: String { "\(root).github" }
    var jobs: String { "\(root).jobs" }
    var maintenance: String { "\(root).maintenance" }
    /// Show logs in Finder, beside the maintenance actions. Not one of their
    /// kinds: it changes nothing on disk.
    var logs: String { "\(root).logs" }

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
