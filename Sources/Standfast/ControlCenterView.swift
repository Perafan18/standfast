import SwiftUI

/// The operational authority: the fleet status stays visible while runner
/// detail, honest empty states, and recovery notices scroll independently.
struct ControlCenterView: View {
  @ObservedObject private var fleet: RunnerFleetModel
  /// Invalidation-only: the body still derives exclusively from the fleet's
  /// complete presentation, which reads this model's published memory.
  @ObservedObject private var housekeeping: HousekeepingModel
  /// Invalidation-only, for the same reason: a fold has to redraw the card it
  /// was performed on, and the fold itself is remembered by the fleet.
  @ObservedObject private var folding: RunnerCardFolding

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  init(fleet: RunnerFleetModel) {
    self.fleet = fleet
    housekeeping = fleet.housekeeping
    folding = fleet.folding
  }

  private var palette: StandfastPalette {
    StandfastTheme.palette(
      for: colorScheme == .dark ? .dark : .light,
      increasedContrast: colorSchemeContrast == .increased,
      reduceTransparency: reduceTransparency)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 2)) { timeline in
      let presentation = fleet.controlCenterPresentation(now: timeline.date)
      VStack(spacing: 0) {
        header(presentation.header)

        ScrollView {
          LazyVStack(alignment: .leading, spacing: StandfastTheme.Spacing.large) {
            if let notice = presentation.notice {
              noticeView(notice)
            }

            if let empty = presentation.empty {
              emptyView(empty)
            } else {
              ForEach(presentation.cards) { card in
                RunnerCardView(
                  card: card,
                  isCollapsed: fleet.folding.isCollapsed(card),
                  toggleCollapsed: { fleet.folding.toggle(card) },
                  performAction: { action in
                    fleet.perform(action, onRunnerID: card.id)
                  },
                  performMaintenance: { offer in
                    fleet.performMaintenance(offer, onRunnerID: card.id)
                  })
              }
            }
          }
          .padding(.horizontal, StandfastTheme.Spacing.large)
          .padding(.vertical, StandfastTheme.Spacing.roomy)
        }
      }
      .frame(minWidth: StandfastTheme.controlCenterMinimumWidth)
      .frame(maxHeight: .infinity)
      .background(Color(nsColor: .windowBackgroundColor))
    }
  }

  private func header(_ presentation: ControlCenterHeaderPresentation) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: StandfastTheme.Spacing.standard) {
        headerStatus(presentation)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: StandfastTheme.Spacing.standard)
        refreshButton
      }
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
        headerStatus(presentation)
        refreshButton
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, StandfastTheme.Spacing.large)
    .padding(.vertical, StandfastTheme.Spacing.standard)
    .background(palette.surface.color)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(palette.structuralBorder.color)
        .frame(height: StandfastTheme.Stroke.structural)
    }
    .accessibilityIdentifier(ControlCenterAccessibility.header)
  }

  private func headerStatus(
    _ presentation: ControlCenterHeaderPresentation
  ) -> some View {
    HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
      Image(systemName: presentation.symbolName)
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        // The short form, since UI-041. The long sentence carries diagnosis,
        // remedy and the name of a button, wraps to two lines the moment any
        // of them grows, pushes Refresh onto a row of its own — and then says
        // itself again, word for word, in the card below. The remedy belongs
        // there, beside the runner it is about.
        //
        // This is only worth doing because the short form now says something:
        // until UI-034 it read `Unknown` for four different problems.
        //
        // The long sentence stays for VoiceOver, which has no card to read
        // next and no layout to protect.
        Text(presentation.shortSummary)
          .font(.title2.weight(.semibold))
          .foregroundStyle(palette.textPrimary.color)
          .accessibilityLabel(presentation.summary)
        if let attention = presentation.attention {
          Text(attention)
            .font(.subheadline)
            .foregroundStyle(palette.attentionForeground.color)
        }
        Text(presentation.freshness)
          .font(.caption)
          .foregroundStyle(palette.textSecondary.color)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var refreshButton: some View {
    Button {
      fleet.refresh()
    } label: {
      Label(L10n.refreshNow, systemImage: "arrow.clockwise")
        .frame(minHeight: StandfastTheme.controlMinimumHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .keyboardShortcut("r", modifiers: .command)
    .accessibilityIdentifier(ControlCenterAccessibility.refresh)
  }

  private func noticeView(
    _ presentation: ControlCenterNoticePresentation
  ) -> some View {
    let content: (title: String, lines: [String]) =
      switch presentation {
      case .launchAgentsUnavailable(let directory):
        (L10n.launchAgentsUnreadable, [directory])
      case .unreadableRunners(let paths):
        (L10n.someRunnersUnreadable, paths)
      }

    return HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        Text(content.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.textPrimary.color)
        ForEach(content.lines, id: \.self) { line in
          Text(line)
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary.color)
        }
      }
    }
    .padding(.horizontal, StandfastTheme.Spacing.compact)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(ControlCenterAccessibility.notice)
  }

  private func emptyView(
    _ presentation: ControlCenterEmptyPresentation
  ) -> some View {
    VStack(spacing: StandfastTheme.Spacing.compact) {
      Image(systemName: presentation.symbolName)
        .font(.system(size: 32, weight: .medium))
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)
      Text(presentation.title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(palette.textPrimary.color)
      ForEach(presentation.detailLines, id: \.self) { detail in
        Text(detail)
          .font(.body)
          .foregroundStyle(palette.textSecondary.color)
          .multilineTextAlignment(.center)
      }
      // UI-039. This is the one screen where the user has nothing else to go
      // on, and it used to tell them to install a runner and leave them to
      // find out how.
      if let guide = presentation.guide {
        Link(L10n.controlCenterInstallGuide, destination: guide)
          .font(.body)
          .padding(.top, StandfastTheme.Spacing.xSmall)
          .accessibilityIdentifier(ControlCenterAccessibility.installGuide)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
    .padding(StandfastTheme.Spacing.large)
    .accessibilityElement(children: .combine)
  }
}
