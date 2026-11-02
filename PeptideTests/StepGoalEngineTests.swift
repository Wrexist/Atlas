import XCTest
@testable import Peptide

final class StepGoalEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// 2026-10-<day> at the given hour.
    private func october(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date()
    }

    // MARK: - Goal

    func test_goal_unsaved_readsDefault() {
        XCTAssertEqual(StepGoalEngine.goal(stored: nil), 8_000)
        XCTAssertEqual(TrainingPreferences().stepGoal, 8_000)
    }

    func test_goal_outOfRange_clampsToBounds() {
        XCTAssertEqual(StepGoalEngine.goal(stored: 0), StepGoalEngine.goalRange.lowerBound)
        XCTAssertEqual(StepGoalEngine.goal(stored: -500), StepGoalEngine.goalRange.lowerBound)
        XCTAssertEqual(StepGoalEngine.goal(stored: 1_000_000), StepGoalEngine.goalRange.upperBound)
        XCTAssertEqual(StepGoalEngine.goal(stored: 12_500), 12_500)
    }

    func test_preferences_savedGoal_isClampedOnRead() {
        var prefs = TrainingPreferences()
        prefs.dailyStepGoal = 90_000
        XCTAssertEqual(prefs.stepGoal, StepGoalEngine.goalRange.upperBound)
    }

    // MARK: - Progress

    func test_progress_partWay_isFraction() {
        XCTAssertEqual(StepGoalEngine.progress(steps: 6_000, goal: 8_000), 0.75, accuracy: 0.0001)
    }

    func test_progress_overGoal_capsAtOne() {
        XCTAssertEqual(StepGoalEngine.progress(steps: 20_000, goal: 8_000), 1)
    }

    func test_progress_zeroOrNegativeInputs_isZero() {
        XCTAssertEqual(StepGoalEngine.progress(steps: 0, goal: 8_000), 0)
        XCTAssertEqual(StepGoalEngine.progress(steps: 5_000, goal: 0), 0)
        XCTAssertEqual(StepGoalEngine.progress(steps: -10, goal: 8_000), 0)
    }

    func test_isMet_exactlyAtGoal_true() {
        XCTAssertFalse(StepGoalEngine.isMet(steps: 7_999, goal: 8_000))
        XCTAssertTrue(StepGoalEngine.isMet(steps: 8_000, goal: 8_000))
        XCTAssertFalse(StepGoalEngine.isMet(steps: 100, goal: 0))
    }

    // MARK: - Fetch window

    func test_fetchDays_today_usesLookback() {
        XCTAssertEqual(StepGoalEngine.fetchDays(forDayOffset: 0), StepGoalEngine.lookbackDays)
    }

    func test_fetchDays_farPastDay_coversThatDay() {
        XCTAssertEqual(StepGoalEngine.fetchDays(forDayOffset: -30), 31)
    }

    // MARK: - Day lookup

    func test_steps_noBuckets_isNil() {
        XCTAssertNil(StepGoalEngine.steps(on: october(19, 12), from: [], calendar: calendar))
    }

    func test_steps_dayWithBucket_returnsItsCount() {
        let buckets = [(date: october(18), value: 4_000.0), (date: october(19), value: 6_240.0)]
        XCTAssertEqual(StepGoalEngine.steps(on: october(19, 15), from: buckets, calendar: calendar), 6_240)
    }

    func test_steps_dayInsideWindowWithoutBucket_isZero() {
        let buckets = [(date: october(17), value: 4_000.0)]
        XCTAssertEqual(StepGoalEngine.steps(on: october(19, 9), from: buckets, calendar: calendar), 0)
    }

    func test_steps_dayBeforeWindow_isNil() {
        let buckets = [(date: october(17), value: 4_000.0)]
        XCTAssertNil(StepGoalEngine.steps(on: october(10, 9), from: buckets, calendar: calendar))
    }
}
