import SwiftUI

/// The operational authority: one native scrolling column, with one card for
/// every runner the latest conclusive scan still says is installed.
struct ControlCenterView: View {
  @ObservedObject private var fleet: RunnerFleetModel
  @ObservedObject private var housekeeping: HousekeepingModel

  init(fleet: RunnerFleetModel) {
    self.fleet = fleet
    housekeeping = fleet.housekeeping
  }

  var body: some View {
    let cards = fleet.controlCenterCards()
    if cards.isEmpty {
      let empty = ControlCenterEmptyPresentation.building(notice: fleet.notice)
      ContentUnavailableView {
        Label(empty.title, systemImage: empty.symbolName)
      } description: {
        VStack {
          ForEach(empty.detailLines.indices, id: \.self) { index in
            Text(empty.detailLines[index])
          }
        }
      } actions: {
        Button(L10n.refreshNow) { fleet.refresh() }
      }
    } else {
      ScrollView {
        LazyVStack(alignment: .leading) {
          if let notice = fleet.notice {
            GroupBox {
              VStack(alignment: .leading) {
                ForEach(notice.lines, id: \.self) { Text($0) }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          ForEach(cards) { card in
            runnerCard(card)
          }
        }
        .padding()
      }
    }
  }

  @ViewBuilder
  private func runnerCard(_ card: RunnerCardPresentation) -> some View {
    GroupBox {
      VStack(alignment: .leading) {
        LabeledContent(L10n.controlCenterStatus, value: card.state)
        LabeledContent(L10n.controlCenterScope, value: card.scope)

        if let progress = card.progress { Text(progress) }

        if let operation = card.operation {
          GroupBox {
            VStack(alignment: .leading) {
              Label(operation.title, systemImage: operation.symbolName)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(operation.title)
                .accessibilityValue(operation.detail)
              Text(operation.detail)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        GroupBox(L10n.controlCenterService) {
          ControlGroup {
            ForEach(
              card.actions.filter { $0.kind != .openOnGitHub }, id: \.kind
            ) { action in
              Button(action.label) {
                fleet.perform(action.kind, onRunnerID: card.id)
              }
              .disabled(!action.isEnabled)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let action = card.actions.first(where: { $0.kind == .openOnGitHub }) {
          Button(action.label) {
            fleet.perform(action.kind, onRunnerID: card.id)
          }
          .disabled(!action.isEnabled)
        }

        if !card.recentJobs.isEmpty {
          GroupBox(L10n.recentJobs) {
            VStack(alignment: .leading) {
              ForEach(card.recentJobs) { job in
                Text(job.text)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }

        maintenance(card.maintenance, runnerID: card.id)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label(card.title, systemImage: card.stateSymbolName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.title)
        .accessibilityValue(card.state)
    }
  }

  @ViewBuilder
  private func maintenance(_ section: MaintenanceSection, runnerID: String) -> some View {
    GroupBox(L10n.maintenance) {
      VStack(alignment: .leading) {
        if let version = section.version { Text(version) }
        ForEach(section.usage, id: \.self) { Text($0) }
        Text(section.measured)
        ControlGroup {
          ForEach(section.offers) { offer in
            Button(role: offer.kind == .measure ? nil : .destructive) {
              fleet.performMaintenance(offer.kind, onRunnerID: runnerID)
            } label: {
              Text(offer.label)
            }
            .disabled(!offer.isEnabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        ForEach(section.notes, id: \.self) { Text($0) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
