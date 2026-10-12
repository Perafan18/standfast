import Foundation

/// A view's own source, read back as text.
///
/// SwiftUI hands out no inspectable tree, so the contracts that live in view
/// composition — which row carries an identifier, which control is disabled
/// rather than removed — are fixed here rather than left to a screenshot
/// somebody remembers to compare.
func standfastSource(_ name: String) -> String {
  let source = standfastSourceDirectory.appendingPathComponent(name)
  return (try? String(contentsOf: source, encoding: .utf8)) ?? ""
}

/// Every Swift file in the app target, as names `standfastSource` reads, for
/// the rules that hold in all of them rather than in one view.
func standfastSourceNames() -> [String] {
  let files = FileManager.default.enumerator(atPath: standfastSourceDirectory.path)
  return (files?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".swift") }.sorted()
}

private var standfastSourceDirectory: URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/Standfast")
}
