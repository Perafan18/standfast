import SwiftUI

/// One runner as a grouped form: who it is, what its two layers say, what it
/// runs and ran, and its disk. The service verbs are the window's toolbar,
/// which acts on whichever runner the sidebar has selected.
struct RunnerCardView: View {
  let card: RunnerCardPresentation
  /// The heat lines, when this runner's own job has overrun on a Mac that is
  /// being throttled, and nil otherwise.
  let thermalLine: String?
  let performMaintenance: (MaintenanceOffer.Kind) -> Void
  let showLogs: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Open, because the jobs are what most people come to a runner for. The
  /// caller resets both per runner with `.id`.
  @State private var jobsExpanded = true
  @State private var maintenanceExpanded = false

  private var identifiers: ControlCenterAccessibility.RunnerIdentifiers {
    ControlCenterAccessibility.runner(card.id)
  }

  var body: some View {
    Form {
      identity
      // A failed order heads the form while it is the news. Any other receipt
      // is a row of Status.
      if let failed = card.failedReceipt {
        Section(L10n.controlCenterLastAction) {
          receipt(failed, failed: true)
        }
      }
      status
      currentJob
      recentJobs
      maintenance
    }
    .formStyle(.grouped)
    .standfastBar(.top, showing: thermalLine) { line in
      Label {
        Text(line)
      } icon: {
        Image(systemName: "thermometer.high")
          .foregroundStyle(.orange)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(ControlCenterAccessibility.thermal)
    }
    // Presence only: a receipt arriving or leaving. State and elapsed times
    // redraw every two seconds, and interpolating them would tween the age of
    // the data on screen.
    .animation(
      StandfastTheme.Motion.honouring(
        StandfastTheme.Motion.receipt, reduceMotion: reduceMotion),
      value: card.operationFeedback
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifiers.card)
  }

  private var identity: some View {
    Section {
      HStack(spacing: 12) {
        Image(systemName: card.stateSymbolName)
          .font(.largeTitle)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(card.tone.color)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(card.title)
            .font(.title2.weight(.semibold))
          Text(card.scope)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // UI-026. A scope under a runner name reads as an assignment, a
            // filter or the job in flight. It is where the runner is
            // registered, and nothing else said so.
            .help(L10n.scopeExplained(card.scope))
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(card.title)
      .accessibilityValue(card.identityAccessibilityValue)
      .accessibilityIdentifier(identifiers.status)
    }
  }

  private var status: some View {
    Section {
      LabeledContent(card.layers.localName) {
        StatusLabel(reading: card.layers.local)
      }
      LabeledContent(card.layers.remoteName) {
        StatusLabel(reading: card.layers.remote)
      }
      // Beside the state it explains: "Disconnected" says what broke, and this
      // says what that is costing.
      if let queued = card.queued {
        queue(queued)
      }
      if let operation = card.operation, operation.isInFlight {
        inFlight(operation)
      }
      if let feedback = card.operationFeedback, card.failedReceipt == nil {
        receipt(feedback, failed: false)
      }
    } header: {
      Text(L10n.controlCenterStatus)
    } footer: {
      // The whole sentence, remedy included, under the readings it explains.
      // Then why the toolbar's service controls do nothing, when they do not.
      VStack(alignment: .leading, spacing: 4) {
        if let sentence = card.statusSentence {
          Text(sentence)
        }
        if let note = card.serviceNote {
          Text(note)
        }
      }
    }
  }

  private func queue(_ queued: QueuedWorkPresentation) -> some View {
    // Weight rather than colour carries "and nothing here will take it": it
    // survives a colour-blind reader and a monochrome screenshot.
    let unclaimed = queued.tone == .attention
    return LabeledContent(L10n.controlCenterWaiting) {
      Label(queued.line, systemImage: unclaimed ? "tray.full.fill" : "tray.full")
        .fontWeight(unclaimed ? .semibold : nil)
        .foregroundStyle(unclaimed ? HierarchicalShapeStyle.primary : .secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifiers.queue)
  }

  private func inFlight(_ operation: ServiceOperationPresentation) -> some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(operation.title)
        Text(operation.detail)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// What became of the last order. A failure is filled and red until the
  /// next order; anything else wears its own tone, so an uncertain result is
  /// never drawn as a failure.
  private func receipt(
    _ feedback: ServiceOperationPresentation, failed: Bool
  ) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(feedback.title)
          .fontWeight(failed ? .semibold : nil)
        Text(feedback.detail)
          .foregroundStyle(.secondary)
      }
    } icon: {
      if failed {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      } else {
        Image(systemName: feedback.symbolName)
          .foregroundStyle(feedback.tone.color)
      }
    }
    .accessibilityElement(children: .combine)
    .transition(.opacity)
  }

  /// What is running now. A finished job and a quiet runner get no section:
  /// Recent jobs and the Status footer already say them.
  @ViewBuilder
  private var currentJob: some View {
    if let job = card.managedJob {
      Section(L10n.controlCenterCurrentJob) {
        VStack(alignment: .leading, spacing: 2) {
          Text(job.context)
          Text(job.detail)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifiers.focus)
        Text(job.association)
        ForEach(job.links) { link in
          Link(link.title, destination: link.url)
        }
      }
    } else if let progress = card.progress {
      Section(L10n.controlCenterCurrentJob) {
        VStack(alignment: .leading, spacing: 6) {
          Text(progress)
            .monospacedDigit()
          // No bar past the usual time: a full one would read as done while
          // the job runs on. The line above still says both numbers.
          if let job = card.jobProgress, job.showsBar, let typical = job.typical {
            ProgressView(value: job.elapsed, total: typical)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifiers.focus)
      }
    }
  }

  private var recentJobs: some View {
    Section {
      DisclosureGroup(isExpanded: $jobsExpanded) {
        switch card.history {
        case .available(let rows, _):
          if rows.isEmpty {
            Text(L10n.historyEmpty())
              .foregroundStyle(.secondary)
          } else {
            ForEach(rows) { historyRow($0) }
          }
        case .unavailable(let lastKnownRows):
          ForEach(lastKnownRows) { historyRow($0) }
        }
      } label: {
        disclosureLabel(isExpanded: $jobsExpanded) {
          HStack {
            Text(L10n.recentJobs)
            Spacer()
            // How many are listed, and only when that is not all of them.
            if case .available(let rows, true) = card.history {
              Text(L10n.historyLatest(rows.count))
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .accessibilityIdentifier(identifiers.jobs)
    } footer: {
      if case .unavailable = card.history {
        Label(L10n.historyUnavailable(), systemImage: "exclamationmark.triangle")
      }
    }
  }

  /// On macOS a `DisclosureGroup` toggles from its triangle alone, so the label
  /// beside it reads as the control and ignores the click. Native disclosures,
  /// System Settings' among them, open from the whole row.
  private func disclosureLabel<Content: View>(
    isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture { isExpanded.wrappedValue.toggle() }
  }

  /// One finished job: which, how it ended, and when and for how long, named.
  /// Rows of "Succeeded" with no dates hide whether they are from today, and
  /// two bare numbers hide which one is the age.
  private func historyRow(_ job: JobRow) -> some View {
    // One line where the form is wide enough, and the circumstances under the
    // name where it is not: Spanish runs about a third longer.
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        jobLabel(job, detail: nil)
        Spacer(minLength: 8)
        Text(job.outcome.label)
          .foregroundStyle(.secondary)
        if let circumstances = job.circumstances {
          Text(circumstances)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        jobLabel(job, detail: job.circumstances)
        Spacer(minLength: 8)
        Text(job.outcome.label)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifiers.job(job.id))
  }

  private func jobLabel(_ job: JobRow, detail: String?) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(job.name)
        if let detail {
          Text(detail)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
    } icon: {
      Image(systemName: job.outcome.symbolName)
        .foregroundStyle(job.outcome.color)
        .accessibilityHidden(true)
    }
  }

  private var maintenance: some View {
    Section {
      DisclosureGroup(isExpanded: $maintenanceExpanded) {
        if let version = card.maintenance.version {
          Text(version)
        }
        ForEach(card.maintenance.usage, id: \.self) { usage in
          Text(usage)
        }
        ForEach(card.maintenance.offers) { offer in
          maintenanceButton(offer)
        }
        // Left out, not greyed, where there is no folder: a GitLab runner or a
        // fleet slot never has one of its own, and others have none until
        // they first run.
        if card.diagnosticsDirectory != nil {
          Button(L10n.showLogsInFinder, action: showLogs)
            .controlSize(.small)
            .accessibilityLabel(L10n.runnerInScope(L10n.showLogsInFinder, card.title))
            .accessibilityIdentifier(identifiers.logs)
        }
      } label: {
        disclosureLabel(isExpanded: $maintenanceExpanded) {
          HStack {
            Text(L10n.maintenance)
            Spacer()
            // On the collapsed row, where it says what is inside without
            // opening it.
            Text(card.maintenance.measured)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
      }
      .accessibilityIdentifier(identifiers.maintenance)
    } footer: {
      // Why the buttons are greyed out, and what the last one did.
      if !card.maintenance.notes.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(card.maintenance.notes, id: \.self) { note in
            Text(note)
          }
        }
      }
    }
  }

  private func maintenanceButton(_ offer: MaintenanceOffer) -> some View {
    Button(offer.label, role: offer.kind == .measure ? nil : .destructive) {
      performMaintenance(offer.kind)
    }
    .controlSize(.small)
    .disabled(!offer.isEnabled)
    .help(offer.isEnabled ? "" : card.state)
    .accessibilityLabel(L10n.runnerInScope(offer.label, card.title))
    .accessibilityIdentifier(identifiers.maintenanceAction(offer.kind))
  }
}

/// One layer's answer: a dot and its words. The words say it on their own, so
/// the dot is decoration and VoiceOver skips it.
struct StatusLabel: View {
  let reading: LayerReading

  var body: some View {
    Label {
      Text(reading.text)
    } icon: {
      Image(systemName: "circle.fill")
        .imageScale(.small)
        .foregroundStyle(reading.tone.color)
        .accessibilityHidden(true)
    }
  }
}
