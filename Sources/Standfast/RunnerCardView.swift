import SwiftUI

struct StateBadge: View {
  let label: String
  let tone: StateTone
  let palette: StandfastPalette

  var body: some View {
    let colors = palette.badge(for: tone)
    Text(label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(colors.foreground.color)
      .padding(.horizontal, StandfastTheme.Spacing.small)
      .padding(.vertical, StandfastTheme.Spacing.xSmall)
      .background(colors.background.color, in: Capsule())
      .overlay {
        Capsule()
          .stroke(colors.border.color, lineWidth: StandfastTheme.Stroke.structural)
      }
  }
}

struct RunnerCardView: View {
  let card: RunnerCardPresentation
  let performAction: (RunnerRow.Action.Kind) -> Void
  let performMaintenance: (MaintenanceOffer.Kind) -> Void

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @State private var jobsExpanded = false
  @State private var maintenanceExpanded = false

  private var palette: StandfastPalette {
    StandfastTheme.palette(
      for: colorScheme == .dark ? .dark : .light,
      increasedContrast: colorSchemeContrast == .increased,
      reduceTransparency: reduceTransparency)
  }

  private var identifiers: ControlCenterAccessibility.RunnerIdentifiers {
    ControlCenterAccessibility.runner(card.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.roomy) {
      identity
      focus
      if let feedback = card.operationFeedback {
        operationFeedback(feedback)
      }
      serviceActions
      navigation
      Rectangle()
        .fill(palette.structuralBorder.color)
        .frame(height: StandfastTheme.Stroke.structural)
      history
      maintenance
    }
    .padding(StandfastTheme.Spacing.large)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      palette.surface.color,
      in: RoundedRectangle(
        cornerRadius: StandfastTheme.Radius.surface, style: .continuous)
    )
    .overlay {
      RoundedRectangle(
        cornerRadius: StandfastTheme.Radius.surface, style: .continuous
      )
      .stroke(
        palette.structuralBorder.color,
        lineWidth: StandfastTheme.Stroke.structural)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifiers.card)
  }

  private var identity: some View {
    HStack(alignment: .firstTextBaseline, spacing: StandfastTheme.Spacing.compact) {
      Image(systemName: card.stateSymbolName)
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        Text(card.title)
          .font(.title3.weight(.semibold))
          .foregroundStyle(palette.textPrimary.color)
        Text(card.scope)
          .font(.subheadline)
          .foregroundStyle(palette.textSecondary.color)
      }

      Spacer(minLength: StandfastTheme.Spacing.small)

      StateBadge(label: card.compactState, tone: card.tone, palette: palette)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(card.title)
    .accessibilityValue("\(card.compactState), \(card.scope). \(card.state)")
    .accessibilityIdentifier(identifiers.status)
  }

  @ViewBuilder
  private var focus: some View {
    switch card.focus {
    case .operation(let operation):
      focusLine(
        symbol: operation.symbolName, title: operation.title,
        detail: operation.detail)
    case .currentJob(let progress):
      focusLine(symbol: "bolt.fill", title: progress)
    case .lastJob(let job):
      focusLine(symbol: job.outcome.symbolName, title: job.text)
    case .state(let state):
      focusLine(symbol: card.stateSymbolName, title: state)
    }
  }

  private func focusLine(
    symbol: String, title: String, detail: String? = nil
  ) -> some View {
    HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
      Image(systemName: symbol)
        .frame(width: 20)
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(palette.textPrimary.color)
        if let detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary.color)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifiers.focus)
  }

  private func operationFeedback(
    _ feedback: ServiceOperationPresentation
  ) -> some View {
    HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
      Image(systemName: feedback.symbolName)
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        Text(feedback.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.textPrimary.color)
        Text(feedback.detail)
          .font(.subheadline)
          .foregroundStyle(palette.textSecondary.color)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var serviceActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: StandfastTheme.Spacing.small) {
        ForEach(serviceActionPresentations) { action in
          serviceButton(action)
        }
      }
      VStack(spacing: StandfastTheme.Spacing.small) {
        ForEach(serviceActionPresentations) { action in
          serviceButton(action)
        }
      }
    }
  }

  private var serviceActionPresentations: [RunnerCardAction] {
    card.actions.filter { $0.kind != .openOnGitHub }
  }

  @ViewBuilder
  private func serviceButton(_ action: RunnerCardAction) -> some View {
    if action.isEnabled && action.emphasis == .prominent {
      serviceButtonLabel(action, foreground: palette.primaryButtonText)
        .buttonStyle(.borderedProminent)
        .tint(palette.primaryButton.color)
    } else {
      serviceButtonLabel(action, foreground: nil)
        .buttonStyle(.bordered)
    }
  }

  private func serviceButtonLabel(
    _ action: RunnerCardAction, foreground: StandfastSRGBColor?
  ) -> some View {
    Button {
      performAction(action.kind)
    } label: {
      Group {
        if let foreground {
          Label(action.label, systemImage: action.symbolName)
            .foregroundStyle(foreground.color)
        } else {
          Label(action.label, systemImage: action.symbolName)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .disabled(!action.isEnabled)
    .accessibilityLabel(action.accessibilityLabel)
    .accessibilityIdentifier(identifier(for: action.kind))
  }

  @ViewBuilder
  private var navigation: some View {
    if let action = card.action(.openOnGitHub) {
      if action.isEnabled && action.emphasis == .prominent {
        navigationButton(action, foreground: palette.primaryButtonText)
          .buttonStyle(.borderedProminent)
          .tint(palette.primaryButton.color)
      } else {
        navigationButton(action, foreground: nil)
          .buttonStyle(.bordered)
      }
    }
  }

  private func navigationButton(
    _ action: RunnerCardAction, foreground: StandfastSRGBColor?
  ) -> some View {
    let qualifiedLabel = L10n.runnerInScope(action.accessibilityLabel, card.title)
    return Button {
      performAction(action.kind)
    } label: {
      Group {
        if let foreground {
          Label(action.label, systemImage: action.symbolName)
            .foregroundStyle(foreground.color)
        } else {
          Label(action.label, systemImage: action.symbolName)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .disabled(!action.isEnabled)
    .accessibilityLabel(qualifiedLabel)
    .accessibilityInputLabels([
      Text(action.label), Text(qualifiedLabel),
    ])
    .accessibilityIdentifier(identifiers.github)
  }

  private var history: some View {
    DisclosureGroup(isExpanded: $jobsExpanded) {
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
        switch card.history {
        case .available(let rows, _):
          if rows.isEmpty {
            Text(L10n.historyEmpty())
              .foregroundStyle(palette.textSecondary.color)
          } else {
            ForEach(rows) { historyRow($0) }
          }
        case .unavailable(let lastKnownRows):
          Label(L10n.historyUnavailable(), systemImage: "exclamationmark.triangle")
            .foregroundStyle(palette.textSecondary.color)
          ForEach(lastKnownRows) { historyRow($0) }
        }
      }
      .padding(.top, StandfastTheme.Spacing.compact)
    } label: {
      HStack {
        Text(L10n.recentJobs)
          .font(.headline)
        Spacer()
        if case .available(let rows, true) = card.history {
          Text("\(rows.count)+")
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textSecondary.color)
        }
      }
      .frame(minHeight: 44)
    }
    .accessibilityIdentifier(identifiers.jobs)
  }

  private func historyRow(_ job: JobRow) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: StandfastTheme.Spacing.small) {
      Image(systemName: job.outcome.symbolName)
        .foregroundStyle(palette.textPrimary.color)
        .accessibilityHidden(true)
      Text(job.name)
        .foregroundStyle(palette.textPrimary.color)
      Spacer(minLength: StandfastTheme.Spacing.small)
      Text(job.outcome.label)
        .foregroundStyle(palette.textSecondary.color)
      if let duration = job.duration {
        Text(duration)
          .monospacedDigit()
          .foregroundStyle(palette.textSecondary.color)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifiers.job(job.id))
  }

  private var maintenance: some View {
    DisclosureGroup(isExpanded: $maintenanceExpanded) {
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.compact) {
        if let version = card.maintenance.version {
          Text(version)
        }
        ForEach(card.maintenance.usage, id: \.self) { usage in
          Text(usage)
        }
        Text(card.maintenance.measured)
          .foregroundStyle(palette.textSecondary.color)
        ForEach(card.maintenance.offers) { offer in
          maintenanceButton(offer)
        }
        ForEach(card.maintenance.notes, id: \.self) { note in
          Text(note)
            .foregroundStyle(palette.textSecondary.color)
        }
      }
      .padding(.top, StandfastTheme.Spacing.compact)
    } label: {
      HStack {
        Text(L10n.maintenance)
          .font(.headline)
        Spacer()
        Text(card.maintenance.measured)
          .font(.caption)
          .foregroundStyle(palette.textSecondary.color)
      }
      .frame(minHeight: 44)
    }
    .accessibilityIdentifier(identifiers.maintenance)
  }

  private func maintenanceButton(_ offer: MaintenanceOffer) -> some View {
    Button(role: offer.kind == .measure ? nil : .destructive) {
      performMaintenance(offer.kind)
    } label: {
      Text(offer.label)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .disabled(!offer.isEnabled)
    .accessibilityLabel(L10n.runnerInScope(offer.label, card.title))
    .accessibilityIdentifier(identifiers.maintenanceAction(offer.kind))
  }

  private func identifier(for kind: RunnerRow.Action.Kind) -> String {
    switch kind {
    case .start: identifiers.start
    case .stop: identifiers.stop
    case .restart: identifiers.restart
    case .openOnGitHub: identifiers.github
    }
  }
}
