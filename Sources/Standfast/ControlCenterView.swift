import SwiftUI

/// The operational authority: the fleet status stays visible while runner
/// detail, honest empty states, and recovery notices scroll independently.
struct ControlCenterView: View {
  @ObservedObject private var fleet: RunnerFleetModel
  /// Invalidation-only: the body still derives exclusively from the fleet's
  /// complete presentation, which reads this model's published memory.
  @ObservedObject private var housekeeping: HousekeepingModel

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  init(fleet: RunnerFleetModel) {
    self.fleet = fleet
    housekeeping = fleet.housekeeping
  }

  private var palette: StandfastPalette {
    StandfastTheme.palette(
      for: colorScheme == .dark ? .dark : .light,
      increasedContrast: colorSchemeContrast == .increased,
      reduceTransparency: reduceTransparency)
  }

  var body: some View {
    let presentation = fleet.controlCenterPresentation(now: Date())
    VStack(spacing: 0) {
      header(presentation.header)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: StandfastTheme.Spacing.standard) {
          if let notice = presentation.notice {
            noticeView(notice)
          }

          if let empty = presentation.empty {
            emptyView(empty)
          } else {
            ForEach(presentation.cards) { card in
              RunnerCardView(
                card: card,
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
        Text(presentation.summary)
          .font(.headline)
          .foregroundStyle(palette.textPrimary.color)
        if let attention = presentation.attention {
          Text(attention)
            .font(.subheadline.weight(.medium))
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
        .frame(minHeight: 44)
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
        .font(.headline)
        .foregroundStyle(palette.textPrimary.color)
      ForEach(presentation.detailLines, id: \.self) { detail in
        Text(detail)
          .font(.body)
          .foregroundStyle(palette.textSecondary.color)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 320)
    .padding(StandfastTheme.Spacing.large)
    .accessibilityElement(children: .combine)
  }
}
