import SwiftUI

/// The operational authority: every runner in a sidebar, the selected one's
/// detail as a form, and its service verbs in the window's toolbar.
struct ControlCenterView: View {
  @ObservedObject private var fleet: RunnerFleetModel
  /// Invalidation-only: the body still derives exclusively from the fleet's
  /// complete presentation, which reads this model's published memory.
  @ObservedObject private var housekeeping: HousekeepingModel
  /// Read rather than observed, since an optional cannot be observed: the
  /// timeline below reads it again every two seconds. Nil where nothing
  /// reports heat, as in tests and renders.
  private let thermal: ThermalMonitor?

  /// The selection, per window: it lasts while the window stays open and comes
  /// back only when macOS restores the window. Empty until somebody chooses,
  /// which is what lets a Mac with one runner open on that runner.
  @SceneStorage("controlCenter.selection") private var storedSelection = ""

  init(fleet: RunnerFleetModel, thermal: ThermalMonitor? = nil) {
    self.fleet = fleet
    housekeeping = fleet.housekeeping
    self.thermal = thermal
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 2)) { timeline in
      let presentation = fleet.controlCenterPresentation(now: timeline.date)
      let thermalLines = ThermalNotice.lines(
        pressure: thermal?.pressure ?? ThermalPressure.none,
        overrunning: fleet.isOverrunning)
      let selection = ControlCenterSelection.resolve(
        stored: storedSelection, cards: presentation.cards)
      let selected = presentation.cards.first { selection == .runner($0.id) }

      NavigationSplitView {
        sidebar(presentation, selection: selection, thermalLines: thermalLines)
      } detail: {
        if let empty = presentation.empty {
          ControlCenterEmptyView(empty: empty, header: presentation.header)
        } else if let card = selected {
          RunnerCardView(
            card: card, thermalLine: card.overrunThermalLine(thermalLines: thermalLines),
            performMaintenance: { kind in
              fleet.performMaintenance(kind, onRunnerID: card.id)
            },
            showLogs: { fleet.showLogs(onRunnerID: card.id) }
          )
          // Each runner opens its own sections, not the last one's.
          .id(card.id)
        } else {
          ControlCenterOverview(
            presentation: presentation, thermalLines: thermalLines,
            select: { storedSelection = ControlCenterSelection.runner($0).stored })
        }
      }
      .navigationTitle(selected?.title ?? L10n.controlCenterOverview)
      .navigationSubtitle(presentation.header.freshness)
      .toolbar {
        ControlCenterToolbar(
          card: selected, refresh: { fleet.refresh() },
          perform: { kind, id in fleet.perform(kind, onRunnerID: id) })
      }
      // The Runner menu acts on this, and only while this window is key.
      .focusedSceneValue(\.selectedRunner, selected.map(RunnerCommandTarget.init))
      .frame(
        minWidth: StandfastTheme.controlCenterMinimumWidth,
        minHeight: StandfastTheme.controlCenterMinimumHeight)
    }
  }

  private func sidebar(
    _ presentation: ControlCenterPresentation, selection: ControlCenterSelection,
    thermalLines: [String]
  ) -> some View {
    List(
      selection: Binding<ControlCenterSelection?>(
        get: { selection },
        // A click on empty space clears the list's selection; the detail keeps
        // showing what it showed.
        set: { if let chosen = $0 { storedSelection = chosen.stored } })
    ) {
      OverviewSidebarRow(
        header: presentation.header,
        warningCount: presentation.overviewWarningCount(thermalLines: thermalLines),
        accessibilityValue: presentation.overviewAccessibilityValue(
          thermalLines: thermalLines)
      )
      .tag(ControlCenterSelection.overview)
      ForEach(presentation.sidebar) { section in
        if let title = section.title {
          Section(title) { runnerRows(section) }
        } else {
          Section { runnerRows(section) }
        }
      }
    }
    .listStyle(.sidebar)
    // A right-click leaves the selection where it was: the menu acts on the
    // row clicked, which need not be the runner the detail shows.
    .contextMenu(forSelectionType: ControlCenterSelection.self) { clicked in
      if let card = presentation.cards.first(where: { clicked == [.runner($0.id)] }) {
        RunnerContextMenu(target: RunnerCommandTarget(card), fleet: fleet)
      }
    }
    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
  }

  private func runnerRows(_ section: ControlCenterSidebar.Section) -> some View {
    ForEach(section.cards) { card in
      RunnerSidebarRow(card: card)
        .tag(ControlCenterSelection.runner(card.id))
    }
  }
}

/// The window's toolbar: Refresh always, and the selected runner's verbs and
/// destination while one is selected. Never a version check in here: on a
/// macOS 14 target it warns, and warnings fail the build.
struct ControlCenterToolbar: ToolbarContent {
  let card: RunnerCardPresentation?
  let refresh: () -> Void
  let perform: (RunnerRow.Action.Kind, _ runnerID: String) -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Button(action: refresh) {
        Label(L10n.refreshNow, systemImage: "arrow.clockwise")
      }
      .keyboardShortcut("r")
      .help(L10n.refreshNow)
      .accessibilityIdentifier(ControlCenterAccessibility.refresh)
    }
    if let card {
      let verbs = card.serviceVerbs
      if !verbs.before.isEmpty {
        ToolbarItemGroup(placement: .primaryAction) {
          ForEach(verbs.before) { serviceButton($0, of: card) }
        }
      }
      // Prominent, in an item of its own. Whether macOS 26 still shares a
      // platter with its neighbours is unproven: see `primaryToolbarActionStyle`.
      if let forward = verbs.forward {
        ToolbarItem(placement: .primaryAction) {
          serviceButton(forward, of: card)
            .primaryToolbarActionStyle(true)
        }
      }
      if !verbs.after.isEmpty {
        ToolbarItemGroup(placement: .primaryAction) {
          ForEach(verbs.after) { serviceButton($0, of: card) }
        }
      }
      if let destination = card.action(.openOnGitHub) {
        ToolbarItem(placement: .primaryAction) {
          destinationButton(destination, of: card)
            .primaryToolbarActionStyle(destination.emphasis == .prominent)
        }
      }
    }
  }

  private func serviceButton(
    _ action: RunnerCardAction, of card: RunnerCardPresentation
  ) -> some View {
    Button {
      perform(action.kind, card.id)
    } label: {
      Label(action.label, systemImage: action.symbolName)
    }
    .disabled(!action.isEnabled)
    // A greyed control that will not say why is a dead end. The reason is
    // this runner's own: why its service is out of reach, or else its state.
    .help(action.isEnabled ? action.accessibilityLabel : (card.serviceNote ?? card.state))
    .accessibilityLabel(action.accessibilityLabel)
    .accessibilityIdentifier(identifier(for: action.kind, of: card))
  }

  private func destinationButton(
    _ action: RunnerCardAction, of card: RunnerCardPresentation
  ) -> some View {
    let qualifiedLabel = L10n.runnerInScope(action.accessibilityLabel, card.title)
    return Button {
      perform(action.kind, card.id)
    } label: {
      Label(action.label, systemImage: action.symbolName)
    }
    .disabled(!action.isEnabled)
    .help(action.isEnabled ? action.accessibilityLabel : card.state)
    .accessibilityLabel(qualifiedLabel)
    .accessibilityInputLabels([Text(action.label), Text(qualifiedLabel)])
    .accessibilityIdentifier(ControlCenterAccessibility.runner(card.id).github)
  }

  private func identifier(
    for kind: RunnerRow.Action.Kind, of card: RunnerCardPresentation
  ) -> String {
    let identifiers = ControlCenterAccessibility.runner(card.id)
    return switch kind {
    case .start: identifiers.start
    case .stop: identifiers.stop
    case .restart: identifiers.restart
    case .openOnGitHub: identifiers.github
    }
  }
}

/// The whole fleet, which the sidebar always lists first.
private struct OverviewSidebarRow: View {
  let header: ControlCenterHeaderPresentation
  /// What only the Overview shows. Zero draws no badge.
  let warningCount: Int
  /// The fleet and those warnings in words, which the badge is not.
  let accessibilityValue: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.controlCenterOverview)
        Text(header.shortSummary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    } icon: {
      Image(systemName: header.symbolName)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(header.tone.color)
    }
    .badge(warningCount)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(L10n.controlCenterOverview)
    .accessibilityValue(accessibilityValue)
    .accessibilityIdentifier(ControlCenterAccessibility.overview)
  }
}

/// One runner in the sidebar: its name, its state in a word or two, an order
/// still in flight or failed, and where it is registered.
private struct RunnerSidebarRow: View {
  let card: RunnerCardPresentation

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(card.title)
        // Two lines, not one: the Spanish state words run long.
        Text(card.compactState)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        if let receipt = card.sidebarReceipt {
          // Weight rather than colour marks the failure, as on the queue line.
          Text(receipt.title)
            .font(.subheadline)
            .fontWeight(receipt.isInFlight ? nil : .semibold)
            .foregroundStyle(
              receipt.isInFlight ? HierarchicalShapeStyle.secondary : .primary
            )
            .lineLimit(2)
        }
        Text(card.scope)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .help(L10n.scopeExplained(card.scope))
      }
    } icon: {
      Image(systemName: card.stateSymbolName)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(card.tone.color)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(card.title)
    .accessibilityValue(card.sidebarAccessibilityValue)
    .accessibilityIdentifier(ControlCenterAccessibility.runner(card.id).sidebar)
  }
}

/// The whole fleet on one page: who needs somebody first, what discovery could
/// not read, how hot the Mac is, and every runner with both of its layers.
struct ControlCenterOverview: View {
  let presentation: ControlCenterPresentation
  /// Empty unless the Mac is being throttled.
  let thermalLines: [String]
  /// Opens one runner's detail, as its sidebar row does.
  let select: (_ runnerID: String) -> Void

  var body: some View {
    let header = presentation.header
    // The runners the header counts, so its number and this list never
    // disagree: a healthy runner whose last order failed is in it, and one
    // somebody stopped on purpose is not.
    let attention = presentation.runnersNeedingAttention

    Form {
      Section {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: header.symbolName)
            .font(.largeTitle)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(header.tone.color)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            // The short form on screen, since UI-041. VoiceOver keeps the long
            // sentence: it has no layout to protect.
            Text(header.shortSummary)
              .font(.title2.weight(.semibold))
              .accessibilityLabel(header.summary)
            if let attention = header.attention {
              Label {
                Text(attention)
              } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                  .symbolRenderingMode(.multicolor)
              }
            }
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ControlCenterAccessibility.header)
      }

      if !attention.isEmpty {
        Section(L10n.controlCenterNeedsAttention) {
          ForEach(attention) { OverviewRunnerRow(card: $0, select: select) }
        }
      }

      if let notice = presentation.notice {
        Section(L10n.controlCenterDiscovery) {
          DiscoveryNoticeRow(notice: notice)
        }
      }

      if !thermalLines.isEmpty {
        Section(L10n.controlCenterThisMac) {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              ForEach(thermalLines, id: \.self) { Text($0) }
            }
          } icon: {
            Image(systemName: "thermometer.high")
              .foregroundStyle(.orange)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier(ControlCenterAccessibility.thermal)
        }
      }

      if !presentation.cards.isEmpty {
        Section(L10n.controlCenterAllRunners) {
          ForEach(presentation.runnersByAttention) {
            OverviewRunnerRow(card: $0, select: select)
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

/// One runner on the Overview: its name and where it is registered, then each
/// layer in a column of its own, so a whole fleet reads down the page.
private struct OverviewRunnerRow: View {
  let card: RunnerCardPresentation
  let select: (_ runnerID: String) -> Void

  /// Fixed, so each layer lines up from row to row. A grid cannot reach
  /// across rows that are buttons, so every row is its own stack. Readings
  /// longer than this wrap, as Spanish ones do.
  @ScaledMetric(relativeTo: .body) private var localColumnWidth: CGFloat = 110
  @ScaledMetric(relativeTo: .body) private var remoteColumnWidth: CGFloat = 170
  /// The least the name keeps beside the columns. The same for every row, so
  /// a section switches to stacking all at once rather than row by row.
  @ScaledMetric(relativeTo: .body) private var nameColumnWidth: CGFloat = 150

  var body: some View {
    Button {
      select(card.id)
    } label: {
      // A narrow detail, with the window at its minimum or the sidebar wide,
      // leaves the columns no room: they would squeeze the name to a few
      // letters a line or push the row out of its section. There the
      // readings go under the name instead.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Label {
            name
          } icon: {
            stateSymbol
          }
          .frame(idealWidth: nameColumnWidth, maxWidth: .infinity, alignment: .leading)
          localReading
            .frame(width: localColumnWidth, alignment: .leading)
          remoteReading
            .frame(width: remoteColumnWidth, alignment: .leading)
          chevron
        }
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Label {
            VStack(alignment: .leading, spacing: 4) {
              name
              localReading
              remoteReading
            }
          } icon: {
            stateSymbol
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          chevron
        }
      }
      // The whole row, not only its words, the way a sidebar row selects.
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // The scope as well as the name: one Mac can serve two repositories with
    // runners of the same name, and the sidebar row says it too.
    .accessibilityLabel(L10n.runnerInScope(card.title, card.scope))
    .accessibilityValue(card.layers.accessibilityValue)
  }

  private var name: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(card.title)
      Text(card.scope)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var stateSymbol: some View {
    Image(systemName: card.stateSymbolName)
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(card.tone.color)
  }

  private var localReading: some View {
    StatusLabel(reading: card.layers.local)
      .help(card.layers.localName)
  }

  private var remoteReading: some View {
    StatusLabel(reading: card.layers.remote)
      .help(card.layers.remoteName)
  }

  private var chevron: some View {
    Image(systemName: "chevron.right")
      .foregroundStyle(.tertiary)
  }
}

/// What discovery could not read, with the paths one click away rather than
/// stacked under it: one unreadable file is a line, and forty are the page.
private struct DiscoveryNoticeRow: View {
  let notice: ControlCenterNoticePresentation

  @State private var showsPaths = false
  /// Past this the paths scroll: discovery reports every file it could not
  /// read, and a popover taller than the screen leaves the last ones out of
  /// reach.
  @ScaledMetric(relativeTo: .body) private var popoverMaximumHeight: CGFloat = 300

  var body: some View {
    HStack {
      // The triangle carries the colour; the words stay primary.
      Label {
        Text(notice.title)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .symbolRenderingMode(.multicolor)
      }
      Spacer()
      Button(L10n.controlCenterDetails) { showsPaths = true }
        .popover(isPresented: $showsPaths) {
          ScrollView {
            PathList(paths: notice.detailLines)
              .padding()
          }
          .scrollBounceBehavior(.basedOnSize)
          // As tall as the paths, up to the cap: a scroll view alone takes all
          // the height it is offered.
          .frame(maxHeight: popoverMaximumHeight)
          .fixedSize(horizontal: false, vertical: true)
        }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(ControlCenterAccessibility.notice)
  }
}

/// Paths somebody is going to open in Finder or paste into a terminal: whole,
/// in monospace, and selectable.
private struct PathList: View {
  let paths: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(paths, id: \.self) { path in
        Text(path)
          .monospaced()
      }
    }
    .textSelection(.enabled)
  }
}

/// A Control Center with no runner to show: still checking, nothing installed,
/// or discovery that could not read where runners live.
struct ControlCenterEmptyView: View {
  let empty: ControlCenterEmptyPresentation
  let header: ControlCenterHeaderPresentation

  var body: some View {
    switch empty {
    case .checking:
      ProgressView {
        Text(L10n.checkingRunners)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .noRunnersInstalled, .launchAgentsUnavailable, .unreadableRunners:
      // Centred while it fits. Forty files that would not read do not, and
      // the system view does not shrink its description to the room left, so
      // then the whole of it scrolls and the last path stays reachable.
      ViewThatFits(in: .vertical) {
        unavailable
        ScrollView { unavailable }
      }
    }
  }

  private var unavailable: some View {
    ContentUnavailableView {
      // UI-031 leaves the title out where the header says the same sentence.
      // There is no header above this any more, so here the header's words
      // are the title.
      Label(empty.title ?? header.shortSummary, systemImage: empty.symbolName)
    } description: {
      if case .noRunnersInstalled = empty {
        Text(empty.detailLines.joined(separator: "\n"))
      } else {
        // A directory or files that would not read: paths to open, not prose.
        PathList(paths: empty.detailLines)
      }
    } actions: {
      // UI-039: the one screen where a new user has nothing else to go on.
      if let guide = empty.guide {
        Link(L10n.controlCenterInstallGuide, destination: guide)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier(ControlCenterAccessibility.installGuide)
        // Named for where it goes, as the line above it is. Settings opens on
        // General, and a button promising to add a folder would leave
        // somebody hunting for the tab that does.
        SettingsLink {
          Text(L10n.settings)
        }
      }
    }
  }
}
