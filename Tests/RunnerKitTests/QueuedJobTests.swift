import Foundation
import Testing

@testable import RunnerKit

private func job(_ labels: [String]) -> QueuedJob {
  QueuedJob(
    id: 1, name: "build", workflowName: "CI", labels: labels, queuedAt: nil, url: nil)
}

private let thisRunner = ["self-hosted", "macOS", "ARM64", "standfast"]

// MARK: - Which queued work is waiting for this machine

@Test func aJobAskingForNothingThisRunnerLacksIsWaitingForIt() {
  // GitHub's own rule: a job goes to a runner that carries *every* label the
  // job asked for. The runner may carry more.
  #expect(job(["self-hosted", "macOS"]).waits(forRunnerLabelled: thisRunner))
}

@Test func aJobAskingForOneLabelThisRunnerLacksIsNotWaitingForIt() {
  // The whole point of the feature. Two runners on the same repository, one
  // labelled `standfast` and one not, must not both claim the same queued job
  // — a menu that says "1 waiting" over the wrong machine is worse than
  // saying nothing.
  #expect(!job(["self-hosted", "linux"]).waits(forRunnerLabelled: thisRunner))
}

@Test func labelsMatchWhateverCaseEitherSideSpelledThem() {
  // GitHub matches labels case-insensitively, and both sides are typed by
  // hand: the label on the runner at registration, and the `runs-on` in a
  // workflow file. `macos` and `macOS` are the same runner to GitHub, and a
  // case-sensitive comparison here would silently report an idle machine as
  // having nothing to do while a job waited for it.
  #expect(job(["Self-Hosted", "MACOS"]).waits(forRunnerLabelled: thisRunner))
}

@Test func aJobBoundForGitHubsOwnRunnersIsNotWaitingForThisOne() {
  // `runs-on: ubuntu-latest` arrives here as a label no self-hosted runner
  // carries, so the same subset rule excludes it without a special case.
  #expect(!job(["ubuntu-latest"]).waits(forRunnerLabelled: thisRunner))
}

@Test func aJobAskingForNoLabelsAtAllIsNotClaimed() {
  // GitHub does not produce this, and if it ever did, "asked for nothing" is
  // not a reason for this runner to announce the job as its own.
  #expect(!job([]).waits(forRunnerLabelled: thisRunner))
}

@Test func aRunnerWithNoLabelsClaimsNothing() {
  // A runner whose labels could not be read is not a runner that matches
  // everything. It is one this app knows nothing about.
  #expect(!job(["self-hosted"]).waits(forRunnerLabelled: []))
}

@Test func duplicateLabelsChangeNothing() {
  #expect(job(["self-hosted", "self-hosted"]).waits(forRunnerLabelled: thisRunner))
}
