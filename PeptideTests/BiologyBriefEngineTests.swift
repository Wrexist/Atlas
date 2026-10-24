import XCTest
@testable import Peptide

@MainActor
final class BiologyBriefEngineTests: XCTestCase {

    private let inputs = PerformanceAgeEngine.Inputs(
        chronologicalAge: 40, hrvMedian30d: 60, rhrMedian30d: 52,
        sleepHoursMedian30d: 7.8, healthDataDays: 30
    )

    func test_brief_unlocked_carriesEstimateDriversAndMissing() throws {
        let estimate = try XCTUnwrap(PerformanceAgeEngine.estimate(inputs: inputs))
        let resolved = BioAgeStateResolver.Resolved(
            state: .unlocked(estimate: estimate), chronologicalAge: 40, inputs: inputs
        )

        let brief = BiologyBriefEngine.brief(resolved, unit: .metric)

        XCTAssertTrue(brief.contains("Biological Age: \(BioAgeFormat.age(estimate.biologicalAge))"))
        XCTAssertTrue(brief.contains("chronological age 40"))
        XCTAssertTrue(brief.contains("- HRV: 60 ms"))
        XCTAssertTrue(brief.contains("Not available:"))
        XCTAssertTrue(brief.contains("Cardio fitness"), "VO2 max had no reading, so it is listed as missing")
    }

    func test_brief_building_stillListsSignalsFromInputs() {
        let resolved = BioAgeStateResolver.Resolved(
            state: .building(days: 9, requiredDays: 15), chronologicalAge: 40, inputs: inputs
        )

        let brief = BiologyBriefEngine.brief(resolved, unit: .metric)

        XCTAssertTrue(brief.hasPrefix("No Biological Age yet: 9 of 30 days"))
        XCTAssertTrue(brief.contains("- Resting heart rate: 52 bpm"))
    }

    func test_brief_trend_namesFirstAndLastPoints() throws {
        let estimate = try XCTUnwrap(PerformanceAgeEngine.estimate(inputs: inputs))
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let resolved = BioAgeStateResolver.Resolved(
            state: .unlocked(estimate: estimate), chronologicalAge: 40, inputs: inputs,
            trend: [.init(date: start, biologicalAge: 39.0),
                    .init(date: start.addingTimeInterval(7 * 86_400), biologicalAge: 37.5)]
        )

        let brief = BiologyBriefEngine.brief(resolved, unit: .metric)

        XCTAssertTrue(brief.contains("Trend: \(BioAgeFormat.age(39.0)) on"))
        XCTAssertTrue(brief.contains("\(BioAgeFormat.age(37.5)) on"))
    }

    func test_brief_locked_saysNothingIsAvailable() {
        let brief = BiologyBriefEngine.brief(.init(state: .locked, chronologicalAge: 35), unit: .metric)
        XCTAssertTrue(brief.hasPrefix("No Biological Age available."))
    }

    // MARK: - Journal

    /// 2025-10-09 00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_759_968_000)

    /// Noon UTC on the offset day, so the printed date is the same in
    /// every time zone the tests run in.
    private func day(_ offset: Int) -> Date {
        now.addingTimeInterval(Double(offset) * 86_400 + 12 * 3600)
    }

    func test_brief_journal_listsRecentDaysOldestFirst() {
        let journal = [
            HealthJournalEntry(day: day(-1), mood: .good, note: "Slept well"),
            HealthJournalEntry(day: day(-3), mood: .low),
            HealthJournalEntry(day: day(-20), mood: .awful, note: "Too old"),
        ]

        let brief = BiologyBriefEngine.brief(
            .init(state: .locked, chronologicalAge: 35), unit: .metric, journal: journal, now: now
        )

        XCTAssertTrue(brief.contains("Health journal"))
        XCTAssertTrue(brief.contains("- 2025-10-06: mood 2/5\n- 2025-10-08: mood 4/5 — \"Slept well\""))
        XCTAssertFalse(brief.contains("Too old"))
    }

    func test_brief_journal_cutsLongNotes() {
        let note = String(repeating: "a", count: 1_000)
        let brief = BiologyBriefEngine.brief(
            .init(state: .locked, chronologicalAge: 35), unit: .metric,
            journal: [HealthJournalEntry(day: day(0), mood: .okay, note: note)], now: now
        )
        XCTAssertTrue(brief.contains(String(repeating: "a", count: BiologyBriefEngine.journalNoteLimit) + "\""))
        XCTAssertFalse(brief.contains(String(repeating: "a", count: BiologyBriefEngine.journalNoteLimit + 1)))
    }

    func test_brief_noJournal_hasNoJournalSection() {
        let brief = BiologyBriefEngine.brief(.init(state: .locked, chronologicalAge: 35), unit: .metric, now: now)
        XCTAssertFalse(brief.contains("Health journal"))
    }
}
