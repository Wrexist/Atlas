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

    func test_fetchDays_oldestBrowsableDay_readsItsBucket() {
        // Buckets as the full fetch returns them: one per day, the oldest
        // `fetchDays - 1` days before today.
        let today = october(19)
        let buckets: [(date: Date, value: Double)] = (0..<StepGoalEngine.fetchDays).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { (date: $0, value: Double(1_000 + back)) }
        }
        let oldest = calendar.date(byAdding: .day, value: -LifestyleDataLogic.maxMealDayLookback, to: today) ?? today
        XCTAssertEqual(
            StepGoalEngine.steps(on: oldest, from: buckets, calendar: calendar),
            Double(1_000 + LifestyleDataLogic.maxMealDayLookback)
        )
    }

    func test_merging_recentRead_replacesOnlyTheRecentDays() {
        let full = [
            (date: october(16), value: 5_000.0),
            (date: october(18), value: 3_000.0),
            (date: october(19), value: 1_200.0)
        ]
        let recent = [(date: october(19), value: 4_800.0)]
        let merged = StepGoalEngine.merging(recent: recent, into: full, now: october(19, 14), calendar: calendar)
        XCTAssertEqual(StepGoalEngine.steps(on: october(16, 9), from: merged, calendar: calendar), 5_000)
        // Yesterday is inside the recent window and the fresh read has no
        // bucket for it, so its stale count drops out.
        XCTAssertEqual(StepGoalEngine.steps(on: october(18, 9), from: merged, calendar: calendar), 0)
        XCTAssertEqual(StepGoalEngine.steps(on: october(19, 9), from: merged, calendar: calendar), 4_800)
    }

    func test_merging_emptyFullWindow_keepsTheRecentRead() {
        let recent = [(date: october(19), value: 2_500.0)]
        let merged = StepGoalEngine.merging(recent: recent, into: [], now: october(19, 8), calendar: calendar)
        XCTAssertEqual(StepGoalEngine.steps(on: october(19, 20), from: merged, calendar: calendar), 2_500)
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
