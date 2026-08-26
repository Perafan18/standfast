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
  /// Whether this runner's card is folded right now.
  ///
  /// Told, never decided here. `@State` takes its initial value once and the
  /// enclosing `LazyVStack` recycles card views as they scroll, so a fold
  /// seeded inside this type would follow a view slot instead of a runner.
  let isCollapsed: Bool
  let toggleCollapsed: () -> Void
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
    // Folded is status, unfolded is actions. A column of complete cards is the
    // right shape for the two or three runners one Mac usually hosts and the
    // wrong shape for ten, where the operator scrolls past nine healthy
    // runners to reach the one that broke — so a folded card keeps answering
    // "what is this runner doing" and drops everything you would open it for.
    VStack(alignment: .leading, spacing: 0) {
      situation
      if !isCollapsed {
        detail
      }
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

  /// What the card answers whether or not it is folded: which runner this is,
  /// what state it is in, and what it is doing about it.
  private var situation: some View {
    VStack(alignment: .leading, spacing: StandfastTheme.Spacing.standard) {
      identity
      focus
      // What is waiting for this runner, above the fold and beside the state
      // it explains. "Disconnected" says what broke; the line under it says
      // what that is costing, and that is the half somebody came for.
      if let queued = card.queued {
        queueLine(queued)
      }
      // Why the controls below do nothing, above the fold with the controls
      // themselves. Greyed-out buttons and no explanation is the app knowing
      // something and not saying it.
      if let note = card.serviceNote {
        HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
          Image(systemName: "hand.raised")
            .frame(width: 20)
            .foregroundStyle(palette.textSecondary.color)
            .accessibilityHidden(true)
          Text(note)
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
      }
      // The receipt for the last Start or Stop stays with the situation on
      // purpose: hiding the outcome of an action the operator just took would
      // make folding feel like the app forgot.
      if let feedback = card.operationFeedback {
        operationFeedback(feedback)
      }
    }
  }

  /// Everything a person opens a card in order to do.
  ///
  /// One spacing value between every section says every section is equally
  /// related to the one above it, which is the same as saying nothing about
  /// structure at all. The gaps carry the grouping instead: controls read as
  /// one block and the two things you open on purpose as a quieter second.
  private var detail: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(spacing: StandfastTheme.Spacing.small) {
        serviceActions
        navigation
      }
      .padding(.top, StandfastTheme.Spacing.large)

      Rectangle()
        .fill(palette.structuralBorder.color)
        .frame(height: StandfastTheme.Stroke.structural)
        .padding(.top, StandfastTheme.Spacing.xLarge)

      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        history
        maintenance
      }
      .padding(.top, StandfastTheme.Spacing.compact)
    }
  }

  private var identity: some View {
    HStack(alignment: .firstTextBaseline, spacing: StandfastTheme.Spacing.compact) {
      identitySummary
      foldControl
    }
    // The lesson the disclosure rows already learned: a chevron on its own is
    // a few points of target beside a whole row that reads interactive and
    // ignores the click. The row is the target; the chevron says which way.
    .contentShape(Rectangle())
    .onTapGesture(perform: toggleCollapsed)
  }

  private var identitySummary: some View {
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
          // UI-026. `acme/acme-widget` under a runner name reads as a fixed
          // assignment, a filter, the last repository used, or the job in
          // flight. It is where the runner is registered, and that was the one
          // reading the card never stated.
          .help(L10n.scopeExplained(card.scope))
      }

      Spacer(minLength: StandfastTheme.Spacing.small)

      StateBadge(label: card.compactState, tone: card.tone, palette: palette)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(card.title)
    .accessibilityValue("\(card.compactState), \(card.scope). \(card.state)")
    .accessibilityIdentifier(identifiers.status)
    // Without this the combined status element is a dead end for VoiceOver:
    // it reads the runner's state and offers no way to open the card it is
    // describing without navigating back out to the chevron.
    .accessibilityAction(named: Text(foldLabel), toggleCollapsed)
  }

  /// What pressing the control would do next, not what it did last.
  private var foldLabel: String {
    isCollapsed ? L10n.unfoldCard : L10n.foldCard
  }

  private var foldControl: some View {
    Button(action: toggleCollapsed) {
      Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
        .font(.body.weight(.semibold))
        .foregroundStyle(palette.textSecondary.color)
        .frame(
          minWidth: StandfastTheme.controlMinimumHeight,
          minHeight: StandfastTheme.controlMinimumHeight
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(L10n.runnerInScope(foldLabel, card.title))
    .accessibilityIdentifier(identifiers.fold)
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
      focusLine(
        symbol: job.outcome.symbolName, title: job.text,
        detail: job.circumstances)
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

  private func queueLine(_ queued: QueuedWorkPresentation) -> some View {
    HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
      // The same two tokens the Settings notices use, and for the same reason:
      // they are the pair already measured against this surface. Reaching for
      // a badge's foreground here would borrow a colour chosen against a badge
      // background that is not behind this text.
      let colour =
        queued.tone == .attention
        ? palette.attentionForeground.color : palette.textSecondary.color
      // Weight rather than colour carries the difference between "work is
      // waiting" and "work is waiting and nothing here is going to take it".
      // The attention token is nearly white in dark mode, so on this surface
      // the two tones were all but identical — and weight survives a
      // colour-blind reader and a monochrome screenshot, which colour does not.
      Image(systemName: queued.tone == .attention ? "tray.full.fill" : "tray.full")
        .frame(width: 20)
        .foregroundStyle(colour)
        .accessibilityHidden(true)
      Text(queued.line)
        .font(queued.tone == .attention ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(colour)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifiers.queue)
  }

  private func operationFeedback(
    _ feedback: ServiceOperationPresentation
  ) -> some View {
    // A failure used to arrive in the same ink as everything else, under a
    // green `Listo` badge that outweighed it. The rule and the colour are what
    // make it the loudest thing on the card while it is there; both are
    // decoration, so the element the reader hears is unchanged.
    let failed = feedback.tone == .attention
    let ink = failed ? palette.attentionOnSurface : palette.textPrimary

    return HStack(alignment: .top, spacing: StandfastTheme.Spacing.compact) {
      if failed {
        RoundedRectangle(cornerRadius: StandfastTheme.Stroke.structural)
          .fill(palette.attentionOnSurface.color)
          .frame(width: 3)
          .accessibilityHidden(true)
      }
      Image(systemName: feedback.symbolName)
        .foregroundStyle(ink.color)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: StandfastTheme.Spacing.xSmall) {
        Text(feedback.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(ink.color)
        Text(feedback.detail)
          .font(.subheadline)
          .foregroundStyle(palette.textSecondary.color)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
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
          // Tint, and only tint. `Arrancar` disabled and `Parar` enabled used
          // to weigh almost the same, so a card at rest read as a panel of
          // controls rather than as a machine with nothing to do. The button
          // keeps its place in the layout and its identifier either way.
          Label(action.label, systemImage: action.symbolName)
            .foregroundStyle(
              action.isEnabled
                ? palette.textPrimary.color : palette.controlTextDisabled.color)
        }
      }
      .frame(maxWidth: .infinity, minHeight: StandfastTheme.controlMinimumHeight)
      .contentShape(Rectangle())
    }
    .disabled(!action.isEnabled)
    // A greyed control that will not say why is a dead end. The runner state is
    // the reason, already localised, so the tooltip reuses it rather than
    // inventing a second vocabulary for the same fact.
    .help(action.isEnabled ? "" : card.state)
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
          // Tint, and only tint. `Arrancar` disabled and `Parar` enabled used
          // to weigh almost the same, so a card at rest read as a panel of
          // controls rather than as a machine with nothing to do. The button
          // keeps its place in the layout and its identifier either way.
          Label(action.label, systemImage: action.symbolName)
            .foregroundStyle(
              action.isEnabled
                ? palette.textPrimary.color : palette.controlTextDisabled.color)
        }
      }
      .frame(maxWidth: .infinity, minHeight: StandfastTheme.controlMinimumHeight)
      .contentShape(Rectangle())
    }
    .disabled(!action.isEnabled)
    .help(action.isEnabled ? "" : card.state)
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
      disclosureLabel(isExpanded: $jobsExpanded) {
        HStack {
          Text(L10n.recentJobs)
            .font(.subheadline.weight(.semibold))
          Spacer()
          if case .available(let rows, true) = card.history {
            Text(L10n.historyLatest(rows.count))
              .font(.caption.weight(.semibold))
              .foregroundStyle(palette.textSecondary.color)
          }
        }
      }
    }
    .accessibilityIdentifier(identifiers.jobs)
  }

  /// On macOS a `DisclosureGroup` toggles from its triangle and nothing else,
  /// so the label beside it looks interactive and is not: the target is a few
  /// points of chevron next to a whole row of text that ignores the click.
  /// Every native disclosure — the Finder inspector, System Settings — opens
  /// from the entire row, which is also the thing a pointer aims at.
  private func disclosureLabel<Content: View>(
    isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .padding(.leading, StandfastTheme.Spacing.xSmall)
      .frame(maxWidth: .infinity, minHeight: StandfastTheme.controlMinimumHeight)
      .contentShape(Rectangle())
      .onTapGesture { isExpanded.wrappedValue.toggle() }
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
      // When first, then how long — and both named, in the sentence the focus
      // line above already uses. Five rows of "Correcto" with no dates do not
      // say whether they are from today or from last month; two bare numbers
      // answering that ("Correcto 48s 49s") only move the guesswork onto which
      // of them is the age.
      if let circumstances = job.circumstances {
        Text(circumstances)
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
        // `measured` stays on the collapsed row, where it says what is inside
        // without opening it. Repeating it here told the reader something they
        // had already read on the line they clicked to get here.
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
      disclosureLabel(isExpanded: $maintenanceExpanded) {
        HStack {
          Text(L10n.maintenance)
            .font(.subheadline.weight(.semibold))
          Spacer()
          Text(card.maintenance.measured)
            .font(.caption)
            .foregroundStyle(palette.textSecondary.color)
        }
      }
    }
    .accessibilityIdentifier(identifiers.maintenance)
  }

  private func maintenanceButton(_ offer: MaintenanceOffer) -> some View {
    Button(role: offer.kind == .measure ? nil : .destructive) {
      performMaintenance(offer.kind)
    } label: {
      Text(offer.label)
        .frame(
          maxWidth: .infinity, minHeight: StandfastTheme.controlMinimumHeight,
          alignment: .leading
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .disabled(!offer.isEnabled)
    .help(offer.isEnabled ? "" : card.state)
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
