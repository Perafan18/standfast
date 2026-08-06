import Foundation
import RunnerKit
import Testing

@testable import Standfast

private let now = Date(timeIntervalSince1970: 1_785_962_174)
private let gigabyte: Int64 = 4_331_016_192

private func section(
  _ snapshot: RunnerSnapshot = snapshot(), measurement: DiskMeasurement? = nil,
  latest: RunnerVersion? = nil, isWorking: Bool = false, notice: String? = nil,
  at readAt: Date = now
) -> MaintenanceSection {
  MaintenanceSection.building(
    snapshot, measurement: measurement, latest: latest, isWorking: isWorking,
    notice: notice, now: readAt)
}

// MARK: - What may be deleted at all

@Test func theOnlyThingsOfferedForDeletionAreCaches() {
  // The claim the whole unit rests on. Every button that deletes a directory
  // names a `CleanupTarget`, and a `CleanupTarget` is a cache the runner refills
  // on a miss — so there is no wiring by which the repository checkout, the
  // job scratch space or the runner's bookkeeping can be reached from this menu.
  let deletable = MaintenanceOffer.Kind.allCases.compactMap(\.target)
  #expect(Set(deletable) == Set(CleanupTarget.allCases))
  #expect(Set(CleanupTarget.allCases.map(\.folderName)) == ["_tool", "_actions"])
  #expect(!CleanupTarget.allCases.map(\.kind).contains(.checkout))
  #expect(!CleanupTarget.allCases.map(\.kind).contains(.temporary))
}

@Test func nothingIsOfferedForDeletionBeforeAnythingHasBeenMeasured() {
  // A button that cannot say what it frees is a button nobody can decide about,
  // and the confirmation it opened would have the same hole in it.
  let rows = section()
  #expect(rows.offers.map(\.kind) == [.measure])
  #expect(rows.usage.isEmpty)
  #expect(rows.measured == L10n.diskNotMeasured)
}

@Test func anIdleRunnerCanFreeItsToolCache() {
  let rows = section(
    snapshot(display: .resolved(.idle)),
    measurement: measured(toolCache: gigabyte, actionCache: 16_588_800))
  let offer = rows.offer(.cleanToolCache)
  #expect(offer?.isEnabled == true)
  // The size is in the label because it is the reason to press it.
  #expect(offer?.label.contains("GB") == true)
  #expect(rows.offer(.cleanActionCache)?.isEnabled == true)
  #expect(rows.notes.isEmpty)
}

@Test func aStoppedRunnerCanBeTidiedUpToo() {
  // The safest state there is, and the one a naive "must be running" rule would
  // have excluded.
  let rows = section(
    snapshot(display: .resolved(.stopped)), measurement: measured(toolCache: gigabyte))
  #expect(rows.offer(.cleanToolCache)?.isEnabled == true)
}

@Test func aRunnerThatIsBuildingIsOfferedNothingAndToldWhy() {
  let rows = section(
    snapshot(display: .resolved(.busy)), measurement: measured(toolCache: gigabyte))
  // Shown rather than hidden: a button that vanishes leaves the user hunting
  // for a feature they saw yesterday.
  #expect(rows.offer(.cleanToolCache)?.isEnabled == false)
  #expect(rows.notes.contains(L10n.deletingOnlyWhenIdle))
}

@Test func everyStateThatIsNotIdleOrStoppedGreysTheButtonsOut() {
  // Read off this runner and nothing else. `.disconnected` is the one that
  // reads like "not working" and is not — GitHub calls a Mac that dropped
  // mid-job offline with the job still assigned to it.
  let refused: [DisplayState] = [
    .resolved(.busy), .resolved(.disconnected), .resolved(.unknown(.noAnswer)),
    .resolved(.unknown(.serviceStateUnreadable)), .starting,
  ]
  for display in refused {
    let rows = section(snapshot(display: display), measurement: measured(toolCache: 1024))
    #expect(rows.offer(.cleanToolCache)?.isEnabled == false, "\(display)")
  }
}

@Test func aRunnerWithNothingToDeleteIsNotToldWhenDeletingWouldBeOffered() {
  // The note explains a greyed-out button. With no button there is nothing to
  // explain, and a line that is true every day is a line nobody reads.
  let rows = section(snapshot(display: .resolved(.busy)), measurement: measured())
  #expect(rows.offers.map(\.kind) == [.measure])
  #expect(rows.notes.isEmpty)
}

@Test func anEmptyCacheIsNotOfferedForDeletion() {
  let rows = section(measurement: measured(toolCache: 0, actionCache: 4096))
  #expect(rows.offer(.cleanToolCache) == nil)
  #expect(rows.offer(.cleanActionCache) != nil)
}

@Test func logsAreOnlyOfferedWhenASweepWouldFreeSomething() {
  // A `_diag` of nothing but this week's logs is a `_diag` a sweep would leave
  // exactly as it found it.
  #expect(section(measurement: measured(logs: 9_000_000)).offer(.trimLogs) == nil)
  #expect(
    section(
      measurement: measured(logs: 9_000_000, rotatable: 8_000_000, rotatableCount: 19)
    )
    .offer(.trimLogs) != nil)
}

@Test func whatTheLastActionDidIsSaidUnderTheButtons() {
  // The one outcome the user has to be told about is a refusal: they asked for
  // something, agreed to it, and did not get it. Without this line the deletion
  // that did not happen looks exactly like the deletion that did.
  let rows = section(
    snapshot(display: .resolved(.idle)), measurement: measured(toolCache: gigabyte),
    notice: L10n.cleanupRefused("build-mac"))
  #expect(rows.notes == [L10n.cleanupRefused("build-mac")])
  // And under the greyed-out buttons it joins the reason rather than replacing
  // it: why they are dead and what the last press did are different questions.
  let busy = section(
    snapshot(display: .resolved(.busy)), measurement: measured(toolCache: gigabyte),
    notice: L10n.cleanupRefused("build-mac"))
  #expect(busy.notes == [L10n.deletingOnlyWhenIdle, L10n.cleanupRefused("build-mac")])
}

@Test func everythingGoesDeadWhileSomethingIsAlreadyRunning() {
  // Measuring and deleting both rewrite the numbers the other is showing, and
  // `du` on four gigabytes is not instant.
  let rows = section(measurement: measured(toolCache: gigabyte), isWorking: true)
  #expect(rows.offers.allSatisfy { !$0.isEnabled })
  #expect(rows.measured == L10n.diskWorking)
}

// MARK: - The rows

@Test func theBiggestThingIsAtTheTop() {
  let rows = section(
    measurement: measured(
      toolCache: gigabyte, actionCache: 16_588_800, checkout: 430_821_376,
      logs: 9_383_936))
  #expect(rows.usage.first == L10n.diskToolCache(ByteText.short(gigabyte)))
  #expect(rows.usage.contains(L10n.diskCheckouts(ByteText.short(430_821_376))))
  // Logs last, whatever their size: they are not in `_work` and they are the
  // one line with a different button under it.
  #expect(rows.usage.last == L10n.diskLogs(ByteText.short(9_383_936)))
  #expect(rows.usage.count == 4)
}

@Test func anEmptyDirectoryGetsNoRowOfItsOwn() {
  // `_work` on a runner that builds one repository has three of them, and a
  // submenu of zeroes buries the one number worth reading.
  let rows = section(measurement: measured(toolCache: gigabyte))
  #expect(rows.usage == [L10n.diskToolCache(ByteText.short(gigabyte))])
}

@Test func sizesAreWrittenInUnitsSomebodyCanRead() {
  // Not raw bytes: "Tool cache — 4331016192" is a number nobody can compare
  // against the window they have open beside it.
  #expect(ByteText.short(gigabyte).contains("GB"))
  #expect(ByteText.short(16_588_800).contains("MB"))
  #expect(ByteText.short(4096).contains("KB"))
}

@Test func theMeasurementSaysHowOldItIs() {
  // The one number in this menu nothing refreshes on a timer, so it has to say
  // so out loud rather than look as current as the row above it.
  let taken = now.addingTimeInterval(-600)
  let rows = section(measurement: measured(toolCache: 1024, at: taken))
  #expect(rows.measured == L10n.diskMeasuredAgo(DurationText.coarse(600)))
  #expect(
    section(measurement: measured(toolCache: 1024)).measured == L10n.diskMeasuredJustNow)
}

@Test func aMeasurementThatFailedIsNotAMeasurement() {
  // "Measured just now" over no rows at all reads as a runner using no disk,
  // which is the opposite of what happened.
  let rows = section(measurement: DiskMeasurement(report: nil, readAt: now))
  #expect(rows.measured == L10n.diskUnavailable)
  #expect(rows.usage.isEmpty)
  #expect(rows.offers.map(\.kind) == [.measure])
}

// MARK: - The version line

@Test func theVersionLineOffersAnUpdateOnlyWhenThereIsANewerOne() {
  let current = section(
    snapshot(version: RunnerVersion(2, 336, 0)), latest: RunnerVersion(2, 336, 0))
  #expect(current.version == L10n.runnerVersion("2.336.0"))

  let behind = section(
    snapshot(version: RunnerVersion(2, 336, 0)), latest: RunnerVersion(2, 337, 0))
  #expect(behind.version == L10n.runnerVersionOutdated("2.336.0", "2.337.0"))
}

@Test func aRunnerAheadOfTheLatestReleaseIsNotToldToGoBackwards() {
  // What a pre-release build looks like from here.
  let rows = section(
    snapshot(version: RunnerVersion(2, 338, 0)), latest: RunnerVersion(2, 337, 0))
  #expect(rows.version == L10n.runnerVersion("2.338.0"))
}

@Test func aRunnerWhoseVersionIsUnknownGetsNoLineAtAll() {
  #expect(section(snapshot(version: nil), latest: RunnerVersion(2, 337, 0)).version == nil)
  // And one that has never been asked still shows what it is running.
  #expect(section(snapshot(version: RunnerVersion(2, 336, 0))).version != nil)
}

// MARK: - The confirmation

@Test func theConfirmationNamesTheDirectoryTheSizeAndTheRunner() {
  // The last thing between a click and four gigabytes going away. All three
  // facts have to be in it: a folder name alone does not say whose it is, and
  // this app is built for the Mac with two runners on it.
  let runner = snapshot("mac-mini-m4").runner
  let prompt = CleanupPrompt.cleaning(.toolCache, in: runner, bytes: gigabyte)
  #expect(prompt.title.contains("/tmp/mac-mini-m4/_work/_tool"))
  #expect(prompt.message.contains(ByteText.short(gigabyte)))
  #expect(prompt.message.contains("mac-mini-m4"))
  // And what it costs, which is one slower build.
  #expect(prompt.message.contains(L10n.cleanupToolCacheEffect))
  #expect(prompt.confirm == L10n.cleanupDelete)
  #expect(prompt.cancel == L10n.cleanupCancel)
}

@Test func theActionCacheConfirmationExplainsItsOwnCostAndNotTheToolCaches() {
  let runner = snapshot().runner
  let prompt = CleanupPrompt.cleaning(.actionCache, in: runner, bytes: 16_588_800)
  #expect(prompt.message.contains(L10n.cleanupActionCacheEffect))
  #expect(!prompt.message.contains(L10n.cleanupToolCacheEffect))
  #expect(prompt.title.contains("_actions"))
}

@Test func theLogConfirmationSaysHowManyFilesAndPromisesTheActiveOne() {
  let runner = snapshot().runner
  let plan = DiagnosticsRotationPlan(
    doomed: (0..<19).map { URL(fileURLWithPath: "/tmp/_diag/log\($0)") },
    bytes: 8_000_000)
  let prompt = CleanupPrompt.trimmingLogs(in: runner, plan: plan)
  #expect(prompt.title.contains("19"))
  #expect(prompt.title.contains("/tmp/build-mac/_diag"))
  #expect(prompt.message.contains(ByteText.short(8_000_000)))
  #expect(prompt.message.contains("19"))
}
