import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// A job row that says what happened and not when.
///
/// Pedro, looking at his own app: "testflight — Correcto (2m 52s). ¿Hace
/// cuánto fue? ¿Hace 2 minutos? ¿Hace 3 días? ¿Hace 2 años?" The parenthesis
/// after an outcome reads as age and is a duration, so the line answers a
/// question nobody asked in the shape of the one they did.
private let ageNow = Date(timeIntervalSince1970: 1_785_962_174)

private func finished(
  _ name: String = "testflight", secondsAgo: TimeInterval, took: TimeInterval? = 172
) -> JobRecord {
  let finishedAt = ageNow.addingTimeInterval(-secondsAgo)
  return JobRecord(
    name: name, startedAt: finishedAt.addingTimeInterval(-(took ?? 0)),
    finishedAt: finishedAt, result: .succeeded)
}

// MARK: - How long ago

@Test func aJobSaysHowLongAgoItRan() {
  let row = JobRow.building([finished(secondsAgo: 3 * 3600)], now: ageNow)[0]

  #expect(row.age == L10n.durationHours(3))
}

@Test func ageIsMeasuredFromWhenTheJobEndedNotWhenItStarted() {
  // A job that started four hours ago and ran for three finished one hour
  // ago. "Hace 4 h" would describe the start of something already over.
  let startedAt = ageNow.addingTimeInterval(-4 * 3600)
  let record = JobRecord(
    name: "nightly", startedAt: startedAt,
    finishedAt: ageNow.addingTimeInterval(-3600), result: .succeeded)

  let row = JobRow.building([record], now: ageNow)[0]

  #expect(row.age == L10n.durationHours(1))
}

@Test func aJobFromTheDayBeforeYesterdayDoesNotSayFiftyThreeHours() {
  // `coarse` used to stop at hours, so anything older read as a pile of them.
  let row = JobRow.building([finished(secondsAgo: 53 * 3600)], now: ageNow)[0]

  #expect(row.age == L10n.durationDays(2))
  #expect(row.age?.contains("53") != true)
}

@Test func daysHaveNoCeilingBecauseASilentRunnerIsThePoint() {
  // "Hace 45 d" is not a formatting failure: it is the app saying this runner
  // has not been given work in a month and a half.
  let row = JobRow.building([finished(secondsAgo: 45 * 24 * 3600)], now: ageNow)[0]

  #expect(row.age == L10n.durationDays(45))
}

@Test func aJobStillRunningHasNoAgeToReport() {
  let record = JobRecord(
    name: "deploy", startedAt: ageNow.addingTimeInterval(-60), finishedAt: nil,
    result: nil)

  let row = JobRow.building([record], now: ageNow)[0]

  // Both halves come from `finishedAt`, so they are absent together.
  #expect(row.age == nil)
  #expect(row.duration == nil)
  #expect(row.circumstances == nil)
}

@Test func aClockThatWentBackwardsDoesNotPrintANegativeAge() {
  let row = JobRow.building([finished(secondsAgo: -30)], now: ageNow)[0]

  #expect(row.age == L10n.durationSeconds(0))
}

// MARK: - What the card actually shows

@Test func theFocusLineSeparatesWhatHappenedFromWhenAndHowLong() {
  let row = JobRow.building([finished(secondsAgo: 3 * 3600, took: 172)], now: ageNow)[0]

  // The answer stays on its own line; the circumstances move underneath it,
  // where they no longer compete for width with the job name.
  #expect(row.text == L10n.jobRowNoDuration("testflight", row.outcome.label))
  #expect(
    row.circumstances
      == L10n.jobAgeAndDuration(L10n.durationHours(3), DurationText.precise(172)))
}

@Test func theDurationIsNeverLeftAloneInAParenthesisAgain() {
  // The whole defect in one assertion: a bare `(2m 52s)` after an outcome is
  // read as "2m 52s ago" by anyone who did not write it.
  let row = JobRow.building([finished(secondsAgo: 3 * 3600, took: 172)], now: ageNow)[0]

  #expect(!row.text.contains("("))
  let circumstances = try? #require(row.circumstances)
  #expect(circumstances?.contains(L10n.durationHours(3)) == true)
}

// MARK: - Where the card puts it

@Test func theCardRendersTheCircumstancesUnderneathTheOutcome() {
  let source = standfastSource("RunnerCardView.swift")

  // `focusLine` already knew how to draw a title with a detail underneath —
  // it does it for service operations. The last job now uses the same shape
  // instead of cramming everything onto one line.
  #expect(source.contains("detail: job.circumstances"))
}

@Test func theHistoryRowNamesWhichNumberIsWhich() {
  let source = standfastSource("RunnerCardView.swift")

  // Five rows of "Correcto" with no dates do not say whether they are from
  // today or from last month, which is the same question the focus line was
  // failing to answer. Answering it with two bare numbers — `Correcto 48s 49s`
  // — asks a new one: which of them is the age? The rows say it in the same
  // words the focus line already uses.
  #expect(source.contains("if let circumstances = job.circumstances"))
  #expect(!source.contains("Text(age)"))
  #expect(!source.contains("Text(duration)"))
}
