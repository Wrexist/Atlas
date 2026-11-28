import XCTest
@testable import Peptide

final class MinimumDayEngineTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Noon on a day in December 2026. The 2nd is a Wednesday.
    private func date(_ day: Int, month: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func keys(_ days: [Int], month: Int = 12) -> Set<String> {
        Set(days.map { DayKey.compact(date($0, month: month), calendar: calendar) })
    }

    private func input(
        meals: Int = 1, protein: Int = 150, target: Int? = 140, steps: Double? = nil, checkedIn: Bool = false
    ) -> MinimumDayEngine.DayInput {
        .init(mealsLogged: meals, proteinG: protein, proteinTargetG: target, steps: steps, checkedIn: checkedIn)
    }

    // MARK: - Met

    func test_isMet_everyChosenPartDone_isMet() {
        XCTAssertTrue(MinimumDayEngine.isMet(input(), parts: [.logFood, .protein]))
    }

    func test_isMet_proteinShort_isNotMet() {
        XCTAssertFalse(MinimumDayEngine.isMet(input(protein: 100), parts: [.logFood, .protein]))
    }

    func test_isMet_noProteinTarget_proteinPartIsSkipped() {
        XCTAssertTrue(MinimumDayEngine.isMet(input(protein: 0, target: nil), parts: [.logFood, .protein]))
    }

    func test_isMet_walkWithoutHealth_isSkipped_withHealthNeedsSteps() {
        XCTAssertTrue(MinimumDayEngine.isMet(input(steps: nil), parts: [.logFood, .walk]))
        XCTAssertFalse(MinimumDayEngine.isMet(input(steps: 400), parts: [.logFood, .walk]))
        XCTAssertTrue(MinimumDayEngine.isMet(input(steps: 1_000), parts: [.logFood, .walk]))
    }

    func test_isMet_nothingMeasurableChosen_isNotMet() {
        XCTAssertFalse(MinimumDayEngine.isMet(input(target: nil), parts: [.protein]))
        XCTAssertFalse(MinimumDayEngine.isMet(input(), parts: []))
    }

    func test_isMet_checkIn_needsTheCheckIn() {
        XCTAssertFalse(MinimumDayEngine.isMet(input(checkedIn: false), parts: [.checkIn]))
        XCTAssertTrue(MinimumDayEngine.isMet(input(checkedIn: true), parts: [.checkIn]))
    }

    // MARK: - Week

    func test_metDays_countsMondayToToday_only() {
        // Mon 30 Nov is the week's first day; Thu 3 Dec is after "today".
        let met = keys([29], month: 11).union(keys([30], month: 11)).union(keys([1, 2, 3]))
        XCTAssertEqual(MinimumDayEngine.metDays(inWeekOf: date(2), metDayKeys: met, calendar: calendar), 3)
    }

    func test_summary_todayMetLive_countsBeforeItIsRecorded() {
        let summary = MinimumDayEngine.summary(metDayKeys: keys([1]), metToday: true, now: date(2), calendar: calendar)
        XCTAssertEqual(summary.metThisWeek, 2)
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.status, .doneToday)
    }

    func test_summary_totalKeepsEveryRecordedDay() {
        let met = keys([3, 4, 5], month: 11).union(keys([1]))
        let summary = MinimumDayEngine.summary(metDayKeys: met, metToday: false, now: date(2), calendar: calendar)
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.weekProgress, 0.2, accuracy: 0.001)
    }

    // MARK: - Status

    func test_status_nothingEver_isStart() {
        let summary = MinimumDayEngine.summary(metDayKeys: [], metToday: false, now: date(2), calendar: calendar)
        XCTAssertEqual(summary.status, .start)
    }

    func test_status_missedYesterday_isNewDay() {
        let summary = MinimumDayEngine.summary(metDayKeys: keys([30], month: 11), metToday: false, now: date(2), calendar: calendar)
        XCTAssertEqual(summary.status, .newDay)
    }

    func test_status_metYesterday_isKeepGoing() {
        let summary = MinimumDayEngine.summary(metDayKeys: keys([1]), metToday: false, now: date(2), calendar: calendar)
        XCTAssertEqual(summary.status, .keepGoing)
    }

    func test_status_emptyWeekAfterShortWeek_isNewWeek() {
        // Last week (23–29 Nov) had two days; this week has none yet.
        let summary = MinimumDayEngine.summary(
            metDayKeys: keys([24, 25], month: 11), metToday: false, now: date(2), calendar: calendar
        )
        XCTAssertEqual(summary.status, .newWeek)
    }

    func test_status_mondayAfterKeptWeek_yesterdayMet_isKeepGoing() {
        // Monday 30 Nov; last week kept with Sunday 29 Nov met.
        let summary = MinimumDayEngine.summary(
            metDayKeys: keys([23, 24, 25, 26, 29], month: 11), metToday: false, now: date(30, month: 11), calendar: calendar
        )
        XCTAssertEqual(summary.status, .keepGoing)
    }

    func test_status_acrossMonthEnd_readsYesterdayInPreviousMonth() {
        // Tuesday 1 Dec, yesterday 30 Nov met.
        let summary = MinimumDayEngine.summary(metDayKeys: keys([30], month: 11), metToday: false, now: date(1), calendar: calendar)
        XCTAssertEqual(summary.status, .keepGoing)
        XCTAssertEqual(summary.metThisWeek, 1)
    }
}
