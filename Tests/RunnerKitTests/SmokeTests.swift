import Testing

@testable import RunnerKit

/// Scaffolding, not coverage. The load-bearing line is the `@testable import`
/// above: it proves the test target links against RunnerKit. Delete this once
/// real tests exist.
@Test func packageBuildsAndTestsRun() {
  #expect(Bool(true))
}
