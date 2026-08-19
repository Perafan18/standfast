import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let labels = ["self-hosted", "macOS"]

private func job(_ id: Int, labels: [String] = ["self-hosted"]) -> QueuedJob {
  QueuedJob(
    id: id, name: "build", workflowName: "CI", labels: labels, queuedAt: nil, url: nil)
}

private func line(
  _ knowledge: QueuedWorkKnowledge, display: DisplayState = .resolved(.idle)
) -> QueuedWorkPresentation? {
  QueuedWorkPresentation.building(knowledge, runnerLabelled: labels, display: display)
}

// MARK: - When there is work waiting

@Test func workWaitingForThisMachineIsNamedAndCounted() {
  let waiting = QueuedWork(jobs: [job(1), job(2)], isPartial: false)

  #expect(line(.work(waiting))?.line == L10n.queueWaiting(2))
}

@Test func oneWaitingJobUsesTheSingular() {
  #expect(
    line(.work(QueuedWork(jobs: [job(1)], isPartial: false)))?.line == L10n.queueWaitingOne)
}

@Test func workForOtherRunnersIsNotCountedAsThisRunners() {
  // The failure this whole feature has to avoid: two runners on one repository
  // both announcing the same queued job, when only one of them will ever be
  // sent it.
  let waiting = QueuedWork(
    jobs: [job(1, labels: ["self-hosted", "linux"])], isPartial: false)

  #expect(line(.work(waiting)) == nil)
}

@Test func aCappedReadingSaysTheCountIsAFloorAndNotATotal() {
  // "2 waiting" over a queue only partly looked at is a silent truncation
  // wearing the clothes of an answer.
  let waiting = QueuedWork(jobs: [job(1), job(2)], isPartial: true)

  #expect(line(.work(waiting))?.line == L10n.queueWaitingPartial(2))
}

// MARK: - Whose problem it is

@Test func workPilingUpBehindAStoppedRunnerIsAnAlarm() {
  // The sentence this feature exists to be able to say: not "your runner is
  // stopped", but "your runner is stopped and three jobs are waiting for it".
  let waiting = QueuedWork(jobs: [job(1), job(2), job(3)], isPartial: false)

  #expect(line(.work(waiting), display: .resolved(.stopped))?.tone == .attention)
}

@Test func workBehindAHealthyIdleRunnerIsJustInformation() {
  // GitHub dispatches to an idle matching runner within seconds. A red badge
  // on a machine that is about to start working would cry wolf every time.
  let waiting = QueuedWork(jobs: [job(1)], isPartial: false)

  #expect(line(.work(waiting), display: .resolved(.idle))?.tone == .neutral)
}

// MARK: - When there is nothing, and when nothing can be known

@Test func anIdleRunnerWithAnEmptyQueueSaysNothingAtAll() {
  // The ordinary state of a healthy machine. A permanent line reading "no work
  // queued" on every card is the noise this product decided not to be.
  #expect(line(.work(QueuedWork(jobs: [], isPartial: false))) == nil)
}

@Test func aStoppedRunnerWithAnEmptyQueueIsToldSoOnPurpose() {
  // Here the same fact is worth saying: whoever is looking at a stopped runner
  // is asking what it is costing them, and "nothing is piling up" is the
  // answer.
  let presentation = line(
    .work(QueuedWork(jobs: [], isPartial: false)), display: .resolved(.stopped))

  #expect(presentation?.line == L10n.queueEmpty)
  #expect(presentation?.tone == .neutral)
}

@Test func anOrganisationRunnerInTroubleSaysTheQuestionCannotBeAnswered() {
  // GitHub has no endpoint for it. Saying nothing would leave the operator to
  // conclude the queue is empty; saying it on every healthy card would be a
  // permanent apology.
  #expect(
    line(.notAvailableHere, display: .resolved(.stopped))?.line == L10n.queueUnknownScope)
  #expect(line(.notAvailableHere, display: .resolved(.idle)) == nil)
}

@Test func aRunnerNobodyAskedAboutClaimsNothingEitherWay() {
  // Busy, or on the `gh` path where labels never arrive. Absence of a question
  // is not evidence of an empty queue.
  #expect(line(.notAsked, display: .resolved(.stopped)) == nil)
  #expect(line(.notAsked, display: .resolved(.busy)) == nil)
}

@Test func aRunnerWhoseLabelsAreUnknownSaysNothingAboutTheQueue() {
  // A stopped runner never reaches GitHub — the local probe answers first — so
  // this app does not know what it is registered as. Reporting "no work is
  // waiting" there would be a claim built out of an absence of evidence, and it
  // is precisely the runner whose queue somebody wants to know about.
  let waiting = QueuedWork(jobs: [job(1)], isPartial: false)

  #expect(
    QueuedWorkPresentation.building(
      .work(waiting), runnerLabelled: [], display: .resolved(.stopped)) == nil)
}
