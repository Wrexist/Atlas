import XCTest
@testable import Peptide

final class CycleCardModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    func test_cycleDay_lateEveningStartNextMorning_isDayTwo() {
        let day = CycleCardModel.cycleDay(from: date(10, hour: 22), now: date(11, hour: 9), calendar: calendar)
        XCTAssertEqual(day, 2)
    }

    func test_cycleDay_startedToday_isDayOne() {
        let day = CycleCardModel.cycleDay(from: date(10, hour: 8), now: date(10, hour: 20), calendar: calendar)
        XCTAssertEqual(day, 1)
    }

    func test_cycleDay_futureStart_isZero() {
        let day = CycleCardModel.cycleDay(from: date(12, hour: 8), now: date(10, hour: 20), calendar: calendar)
        XCTAssertEqual(day, 0)
    }

    // MARK: - Health section (C249)

    func test_healthSummary_noFields_isEmpty() {
        XCTAssertTrue(CycleCardModel.HealthSummary(weightDeltaKg: nil, avgSleepHours: nil, hrvTrendDescription: nil).isEmpty)
        XCTAssertFalse(CycleCardModel.HealthSummary(weightDeltaKg: -1, avgSleepHours: nil, hrvTrendDescription: nil).isEmpty)
    }

    // MARK: - Masked names and spoken summary (C260, C261)

    private func model(streakIsOverall: Bool = false) -> CycleCardModel {
        CycleCardModel(
            subjectTitle: "BPC-157 + TB-500",
            peptides: [MockPeptides.bpc157],
            activeSinceDate: date(1, hour: 8),
            cycleDay: 3,
            cycleTotalDays: 56,
            dosesLogged: 12,
            adherencePercent: 90,
            currentStreakDays: 4,
            healthSummary: nil,
            streakIsOverall: streakIsOverall
        )
    }

    func test_maskedCompoundName_usesTheLocalizedVialName() {
        XCTAssertEqual(CycleCardModel.maskedCompoundName(1), String(localized: "Compound \("B")"))
    }

    func test_spokenSummary_masked_hidesTitleAndAbbreviations() {
        let summary = model().spokenSummary(maskCompoundNames: true)
        XCTAssertFalse(summary.contains("BPC-157"))
        XCTAssertTrue(summary.contains(CycleCardModel.maskedCompoundName(0)))
    }

    func test_streakTitle_perProtocolCard_saysOverall() {
        XCTAssertEqual(model(streakIsOverall: true).streakTitle, String(localized: "Overall streak"))
        XCTAssertEqual(model().streakTitle, String(localized: "Streak"))
    }
}
