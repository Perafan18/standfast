import Foundation
import Testing

@testable import Standfast

private func scratch() -> UserDefaults {
  let suite = UserDefaults(suiteName: "manual-runners-\(UUID().uuidString)")!
  return suite
}

@MainActor
@Test func aMacWithNothingAddedListsNothing() {
  #expect(ManualRunnerDirectories(defaults: scratch()).directories.isEmpty)
}

@MainActor
@Test func anAddedDirectorySurvivesARelaunch() {
  // The whole point of storing them: a runner started by hand is invisible to
  // discovery, so if this list did not persist the operator would be pointing
  // the app at it again every morning.
  let defaults = scratch()
  ManualRunnerDirectories(defaults: defaults).add(URL(fileURLWithPath: "/Users/ci/one"))

  #expect(
    ManualRunnerDirectories(defaults: defaults).directories.map(\.path)
      == ["/Users/ci/one"])
}

@MainActor
@Test func theSameDirectoryTwiceIsStillOneRunner() {
  // Adding it again is what somebody does when they are not sure it took.
  // Discovery deduplicates by label, so a repeat would be silently dropped
  // there — but the list itself would grow, and Settings would show it twice.
  let subject = ManualRunnerDirectories(defaults: scratch())
  subject.add(URL(fileURLWithPath: "/Users/ci/one"))
  subject.add(URL(fileURLWithPath: "/Users/ci/one/"))

  #expect(subject.directories.count == 1)
}

@MainActor
@Test func removingADirectoryStopsItBeingLookedFor() {
  let defaults = scratch()
  let subject = ManualRunnerDirectories(defaults: defaults)
  subject.add(URL(fileURLWithPath: "/Users/ci/one"))
  subject.add(URL(fileURLWithPath: "/Users/ci/two"))

  subject.remove(URL(fileURLWithPath: "/Users/ci/one"))

  #expect(subject.directories.map(\.path) == ["/Users/ci/two"])
  #expect(
    ManualRunnerDirectories(defaults: defaults).directories.map(\.path)
      == ["/Users/ci/two"])
}

@MainActor
@Test func theyComeBackInTheOrderTheyWereAdded() {
  // Not sorted: the operator added them in an order that meant something to
  // them, and reordering a list somebody typed is a small theft.
  let subject = ManualRunnerDirectories(defaults: scratch())
  for name in ["zulu", "alpha", "mike"] {
    subject.add(URL(fileURLWithPath: "/Users/ci/\(name)"))
  }

  #expect(subject.directories.map(\.lastPathComponent) == ["zulu", "alpha", "mike"])
}

@MainActor
@Test func rubbishInTheDefaultsIsIgnoredRatherThanCrashing() {
  // `defaults write` is a thing people do, and a wrong type there must not
  // take the fleet down with it.
  let defaults = scratch()
  defaults.set(
    ["/Users/ci/one", 42, ["nested"]], forKey: ManualRunnerDirectories.defaultsKey)

  #expect(
    ManualRunnerDirectories(defaults: defaults).directories.map(\.path) == ["/Users/ci/one"]
  )
}
