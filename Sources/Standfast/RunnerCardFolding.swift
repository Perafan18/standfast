import Foundation

/// Which runner cards are folded, and on whose authority.
///
/// This lives outside the card view on purpose. `@State` takes its initial
/// value once and `LazyVStack` recycles cards as they scroll, so a fold seeded
/// from the presentation would land on whichever runner happened to reuse that
/// view. Keyed by the runner's durable launchd label, the same identity the
/// Accessibility identifiers hash, a fold follows its runner instead.
@MainActor
final class RunnerCardFolding: ObservableObject {
  /// Where the folds are remembered.
  static let defaultsKey = "foldedRunnerCards"

  /// Runners the operator has folded or unfolded by hand.
  ///
  /// Absence is meaningful: a runner nobody has touched is not in here at all,
  /// which is what lets the product rule keep deciding for it. Entries are
  /// never pruned — a runner that stops being discovered for an afternoon
  /// should find its card the way it left it, not reset by a bad launchd read.
  @Published private var operatorChoices: [String: Bool]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    operatorChoices =
      (defaults.dictionary(forKey: Self.defaultsKey) ?? [:])
      .compactMapValues { $0 as? Bool }
  }

  func isCollapsed(_ card: RunnerCardPresentation) -> Bool {
    operatorChoices[card.id] ?? card.startsCollapsed
  }

  func toggle(_ card: RunnerCardPresentation) {
    let folded = !isCollapsed(card)
    operatorChoices[card.id] = folded
    defaults.set(operatorChoices, forKey: Self.defaultsKey)
  }
}
