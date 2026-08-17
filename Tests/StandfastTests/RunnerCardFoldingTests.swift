import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let foldingNow = Date(timeIntervalSince1970: 1_785_962_174)

private func foldableCard(
  _ name: String = "build-mac", display: DisplayState = .resolved(.idle),
  fleetSize: Int = 1
) -> RunnerCardPresentation {
  RunnerCardPresentation.building(
    snapshot(name, display: display), measurement: nil, latestRelease: nil,
    isMaintenanceWorking: false, maintenanceNotice: nil, now: foldingNow,
    fleetSize: fleetSize)
}

private let crowdedFleet = RunnerCardPresentation.compactFleetThreshold + 1

// MARK: - Before anybody touches anything

@Test @MainActor func aCardNobodyFoldedOpensTheWayTheProductDecided() {
  let folding = RunnerCardFolding(defaults: scratchDefaults())

  // Two runners: the shape the window was designed around, where every card
  // stays whole because there is nothing to scroll past.
  #expect(!folding.isCollapsed(foldableCard(fleetSize: 2)))
  // Ten: the same healthy runner now costs the operator a screen of scrolling
  // to reach the one that broke, so the product folds it.
  #expect(folding.isCollapsed(foldableCard(fleetSize: crowdedFleet)))
}

@Test @MainActor func openingTheWindowRemembersNothingOnItsOwn() {
  // A card that arrives folded because the fleet is large is not a decision the
  // operator made, and writing it down would freeze today's fleet size into a
  // preference nobody set. Only a real fold or unfold is remembered.
  let defaults = scratchDefaults()
  let folding = RunnerCardFolding(defaults: defaults)

  _ = folding.isCollapsed(foldableCard(fleetSize: crowdedFleet))

  #expect(defaults.dictionary(forKey: RunnerCardFolding.defaultsKey) == nil)
}

// MARK: - What the operator asked for

@Test @MainActor func foldingACardLeavesEveryOtherRunnerAlone() {
  let folding = RunnerCardFolding(defaults: scratchDefaults())
  let folded = foldableCard("build-mac")
  let untouched = foldableCard("release-mac")

  folding.toggle(folded)

  #expect(folding.isCollapsed(folded))
  #expect(!folding.isCollapsed(untouched))
}

@Test @MainActor func theOperatorsChoiceSurvivesARelaunch() {
  let defaults = scratchDefaults()
  let card = foldableCard()
  RunnerCardFolding(defaults: defaults).toggle(card)

  let afterRelaunch = RunnerCardFolding(defaults: defaults)

  // Folding eight runners and finding them open again the next morning is
  // worse than never having been able to fold them.
  #expect(afterRelaunch.isCollapsed(card))
}

@Test @MainActor func theOperatorOutranksTheProductRule() {
  let defaults = scratchDefaults()
  // A card the rule folds on sight, opened by hand.
  let card = foldableCard(fleetSize: crowdedFleet)
  let folding = RunnerCardFolding(defaults: defaults)
  folding.toggle(card)

  #expect(!folding.isCollapsed(card))
  #expect(!RunnerCardFolding(defaults: defaults).isCollapsed(card))
}

@Test @MainActor func aCardTheOperatorReopensStopsBeingFolded() {
  let folding = RunnerCardFolding(defaults: scratchDefaults())
  let card = foldableCard()

  folding.toggle(card)
  folding.toggle(card)

  #expect(!folding.isCollapsed(card))
}

// MARK: - What a folded card still answers

@Test @MainActor func aRunnerThatNeedsSomebodyIsNeverFoldedByTheRule() {
  let folding = RunnerCardFolding(defaults: scratchDefaults())

  // The disconnected runner on a ten-runner Mac is the entire reason the
  // window was opened. It stays whole even where healthy runners fold.
  #expect(
    !folding.isCollapsed(
      foldableCard(display: .resolved(.disconnected), fleetSize: crowdedFleet)))
}

// MARK: - Rendering the fold

@Test func aFoldedCardKeepsTheAnswerAndHidesTheControls() {
  let source = standfastSource("RunnerCardView.swift")

  // Folded is status, unfolded is actions. The two halves are named in the
  // view so the contract is legible where it is rendered rather than inferred
  // from which modifiers happen to sit inside the condition.
  #expect(source.contains("if !isCollapsed {"))
  #expect(source.contains("private var situation: some View"))
  #expect(source.contains("private var detail: some View"))
}

@Test func foldingIsNeverKeptInsideARecycledCard() {
  let source = standfastSource("RunnerCardView.swift")

  // `@State` takes its initial value once and `LazyVStack` reuses card views
  // as they scroll, so seeding a fold from the presentation would attach it to
  // a view slot rather than to a runner. The card is told, it does not decide.
  #expect(source.contains("let isCollapsed: Bool"))
  #expect(source.contains("let toggleCollapsed: () -> Void"))
  #expect(!source.contains("@State private var isCollapsed"))
  #expect(!source.contains("card.startsCollapsed"))
}

@Test func theWholeIdentityRowFoldsTheCardAndSaysSoToAssistiveTech() {
  let source = standfastSource("RunnerCardView.swift")

  // The same lesson the disclosure rows already learned: a chevron alone is a
  // few points of target beside a whole row that reads interactive and ignores
  // the click. The row folds, and the chevron is what keyboard focus and the
  // Accessibility tree can reach by name.
  #expect(source.contains(".onTapGesture(perform: toggleCollapsed)"))
  #expect(source.contains(".accessibilityIdentifier(identifiers.fold)"))
  #expect(source.contains("accessibilityAction(named:"))
}

@Test func theControlCenterOwnsTheFoldingItPassesToEachCard() {
  let controlCenter = standfastSource("ControlCenterView.swift")

  #expect(controlCenter.contains("isCollapsed: fleet.folding.isCollapsed(card)"))
  #expect(controlCenter.contains("fleet.folding.toggle(card)"))
}

@Test func theFoldControlHasItsOwnDeterministicIdentifier() {
  let runner = ControlCenterAccessibility.runner("/tmp/actions-runner")
  let other = ControlCenterAccessibility.runner("/tmp/other-runner")

  #expect(runner.fold == "\(runner.card).fold")
  #expect(runner.fold != other.fold)
  #expect(runner.fold == ControlCenterAccessibility.runner("/tmp/actions-runner").fold)
}

@Test func theFoldControlSaysWhichWayItWouldGo() {
  // A control that reads "Fold" whether it folds or unfolds tells the operator
  // — and VoiceOver — nothing about what pressing it does next.
  #expect(!L10n.foldCard.isEmpty)
  #expect(!L10n.unfoldCard.isEmpty)
  #expect(L10n.foldCard != L10n.unfoldCard)
  #expect(L10n.foldCard != "controlCenter.fold")
  #expect(L10n.unfoldCard != "controlCenter.unfold")
}
