import XCTest
@testable import Peptide

/// Fixed UTC calendar + explicit y/m/d dates throughout — the block-window
/// math this engine does is exact-day arithmetic, and running it against
/// `.current`/the test machine's local time zone would make these tests
/// flaky across CI runners in different zones.
final class TrainingPatternEngineTests: XCTestCase {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: comps)!
    }

    /// "Today" for every test below: Monday, Jan 29 2024. The current
    /// rolling week is therefore Jan 23–29 inclusive.
    private var referenceDate: Date { date(2024, 1, 29) }

    // MARK: - weeklyFrequencyBaseline

    func test_weeklyFrequencyBaseline_excludesCurrentRollingWeek_andBinsPriorBlocksWithNoGapOrOverlap() {
        let sessions = [
            // Current rolling week (Jan 23–29) — must NOT land in the baseline.
            date(2024, 1, 24), date(2024, 1, 27), date(2024, 1, 29),
            // Block 0: Jan 16–22 (2 sessions).
            date(2024, 1, 16), date(2024, 1, 20),
            // Block 1: Jan 9–15 (4 sessions).
            date(2024, 1, 9), date(2024, 1, 10), date(2024, 1, 11), date(2024, 1, 14),
            // Block 2: Jan 2–8 (0 sessions) — left empty on purpose.
        ]
        let baseline = TrainingPatternEngine.weeklyFrequencyBaseline(
            sessionDates: sessions,
            asOf: referenceDate,
            calendar: utcCalendar,
            trailingWeeks: 3
        )
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.sampleCount, 3)
        XCTAssertEqual(baseline?.mean ?? -1, 2.0, accuracy: 0.0001)
        // Sorted block counts are [0, 2, 4] — nearest-rank p90 lands on 4.
        XCTAssertEqual(baseline?.p90, 4)
    }

    func test_weeklyFrequencyBaseline_confidenceReflectsTrailingWeeksRequested() {
        // 3 non-empty trailing-week blocks with emergingAtWeeks == 3 should
        // read as emerging, not established.
        let sessions = [date(2024, 1, 16), date(2024, 1, 9), date(2024, 1, 2)]
        let baseline = TrainingPatternEngine.weeklyFrequencyBaseline(
            sessionDates: sessions,
            asOf: referenceDate,
            calendar: utcCalendar,
            trailingWeeks: TrainingPatternEngine.emergingAtWeeks
        )
        XCTAssertEqual(baseline?.confidence, .emergingBaseline)
    }

    func test_weeklyFrequencyBaseline_noSessionsAtAll_stillReturnsInsufficientBaseline_notNil() {
        // Empty history still produces zero-count blocks, not a `nil`
        // baseline — `PersonalBaselineEngine.build` only returns `nil` for
        // a genuinely empty `values` array, and `trailingWeeks` blocks are
        // always non-empty even when every count in them is zero.
        // `trailingWeeks` below `emergingAtWeeks` (3) keeps this at
        // insufficient confidence regardless of the (all-zero) counts.
        let baseline = TrainingPatternEngine.weeklyFrequencyBaseline(
            sessionDates: [],
            asOf: referenceDate,
            calendar: utcCalendar,
            trailingWeeks: 2
        )
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.mean, 0)
        XCTAssertEqual(baseline?.confidence, .insufficientHistory)
    }

    // MARK: - currentRollingWeekCount

    func test_currentRollingWeekCount_countsOnlyTrailingSevenDaysInclusiveOfToday() {
        let sessions = [
            date(2024, 1, 22), // one day before the window starts — excluded
            date(2024, 1, 23), // window start — inclusive
            date(2024, 1, 26),
            date(2024, 1, 29), // today — inclusive
            date(2024, 1, 30), // tomorrow — excluded
        ]
        let count = TrainingPatternEngine.currentRollingWeekCount(
            sessionDates: sessions,
            asOf: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(count, 3)
    }

    func test_currentRollingWeekCount_noSessions_isZero() {
        XCTAssertEqual(
            TrainingPatternEngine.currentRollingWeekCount(sessionDates: [], asOf: referenceDate, calendar: utcCalendar),
            0
        )
    }

    // MARK: - preferredWeekdays

    func test_preferredWeekdays_singleMostTrainedDay() {
        // Jan 1, 8, 15 2024 are all Mondays — ISO weekday 1.
        let sessions = [date(2024, 1, 1), date(2024, 1, 8), date(2024, 1, 15)]
        XCTAssertEqual(
            TrainingPatternEngine.preferredWeekdays(sessionDates: sessions, calendar: utcCalendar),
            [1]
        )
    }

    func test_preferredWeekdays_tiesAreAllReturned_sortedAscending() {
        let sessions = [
            date(2024, 1, 1),                        // Monday (1) — 1 session
            date(2024, 1, 3), date(2024, 1, 10),      // Wednesday (3) — 2 sessions
            date(2024, 1, 7), date(2024, 1, 14),      // Sunday (7) — 2 sessions
        ]
        XCTAssertEqual(
            TrainingPatternEngine.preferredWeekdays(sessionDates: sessions, calendar: utcCalendar),
            [3, 7]
        )
    }

    func test_preferredWeekdays_emptyInput_returnsEmpty() {
        XCTAssertEqual(TrainingPatternEngine.preferredWeekdays(sessionDates: [], calendar: utcCalendar), [])
    }
}
