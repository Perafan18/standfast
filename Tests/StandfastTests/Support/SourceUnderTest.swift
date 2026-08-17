import Foundation

/// A view's own source, read back as text.
///
/// SwiftUI hands out no inspectable tree, so the contracts that live in view
/// composition — what a fold hides, which surface a card draws on — are fixed
/// here rather than left to a screenshot somebody remembers to compare.
func standfastSource(_ name: String) -> String {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = repository.appendingPathComponent("Sources/Standfast/\(name)")
  return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
}
