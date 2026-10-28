import XCTest
@testable import Peptide

final class WeeklyCheckInEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Sunday Jan 11 2026, noon UTC. Week 0 is Mon Jan 5 – Sun Jan 11.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 11, hour: 12))!
    }

    private func day(_ offset: Int, hour: Int = 8) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .hour, value: offset * 24 + hour, to: start)!
    }

    private func weigh(_ offset: Int, _ kg: Double) -> WeightEntry {
        WeightEntry(date: day(offset), kg: kg)
    }

    private func eat(_ offset: Int, kcal: Int, protein: Int) -> DailyConsumption {
        DailyConsumption(
            date: calendar.startOfDay(for: day(offset)),
            caloriesKcal: kcal,
            proteinG: protein,
            carbsG: 0,
            fatG: 0,
            waterOz: 0
        )
    }

    private let targets = NutritionTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 70, fiberG: 30)

    private func build(
        weights: [WeightEntry] = [],
        consumption: [DailyConsumption] = [],
        targets: NutritionTargets? = nil,
        goalRaw: String? = nil,
        workoutDates: [Date] = [],
        planned: Int? = nil,
        sleep: [(date: Date, value: Double)] = []
    ) -> WeeklyCheckIn? {
        WeeklyCheckInEngine.build(
            weights: weights,
            consumption: consumption,
            targets: targets,
            goalRaw: goalRaw,
            workoutDates: workoutDates,
            plannedWorkoutsPerWeek: planned,
            sleepHours: sleep,
            now: now,
            calendar: calendar
        )
    }

    /// Three weeks of flat weigh-ins, three per week.
    private var flatThreeWeeks: [WeightEntry] {
        [-20, -18, -16, -13, -11, -9, -6, -4, -2].map { weigh($0, 80.0) }
    }

    /// A week of logging that sits on the calorie and protein targets.
    private var onTargetWeek: [DailyConsumption] {
        (-6...0).map { eat($0, kcal: 2000, protein: 160) }
    }

    // MARK: - Gate

    func test_build_nothingLogged_returnsNil() {
        XCTAssertNil(build())
    }

    func test_build_onlyOldData_returnsNil() {
        XCTAssertNil(build(weights: [weigh(-40, 80)], consumption: [eat(-40, kcal: 2000, protein: 100)]))
    }

    // MARK: - Weight

    func test_weight_bothWeeks_changeIsDifferenceOfWeeklyAverages() throws {
        let weight = try XCTUnwrap(build(weights: [
            weigh(-13, 80.0), weigh(-10, 80.2), weigh(-8, 80.4),
            weigh(-5, 79.6), weigh(-1, 79.8),
        ])?.weight)
        XCTAssertEqual(weight.currentKg, 79.7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(weight.changeKgPerWeek), -0.5, accuracy: 0.001)
        XCTAssertEqual(weight.weighInsThisWeek, 2)
        XCTAssertEqual(weight.trend.count, 5)
    }

    func test_weight_onlyThisWeek_hasNoChange() throws {
        let weight = try XCTUnwrap(build(weights: [weigh(-3, 81), weigh(-1, 80)])?.weight)
        XCTAssertNil(weight.changeKgPerWeek)
        XCTAssertEqual(weight.currentKg, 80.5, accuracy: 0.001)
    }

    func test_weight_noWeighInThisWeek_showsLatestReading() throws {
        let weight = try XCTUnwrap(build(weights: [weigh(-12, 82), weigh(-9, 81)])?.weight)
        XCTAssertEqual(weight.currentKg, 81)
        XCTAssertEqual(weight.weighInsThisWeek, 0)
        XCTAssertNil(weight.changeKgPerWeek)
    }

    func test_weight_onlyOlderThanTwoWeeks_isNil() throws {
        let checkIn = try XCTUnwrap(build(weights: [weigh(-20, 80)], workoutDates: [day(-1)]))
        XCTAssertNil(checkIn.weight)
    }

    func test_trend_consecutiveDays_movesQuarterOfTheGap() {
        let points = WeeklyCheckInEngine.trend([weigh(-2, 80), weigh(-1, 82)], since: day(-10), calendar: calendar)
        XCTAssertEqual(points.map(\.kg).last ?? 0, 80.5, accuracy: 0.001)
    }

    func test_trend_twoDayGap_smoothsAsTwoDays() {
        let points = WeeklyCheckInEngine.trend([weigh(-3, 80), weigh(-1, 82)], since: day(-10), calendar: calendar)
        // 1 - 0.75² = 0.4375 of the 2 kg gap.
        XCTAssertEqual(points.map(\.kg).last ?? 0, 80.875, accuracy: 0.001)
    }

    func test_trend_seedsFromEarlierWeeksButPlotsOnlyTheFortnight() throws {
        let weight = try XCTUnwrap(build(weights: [weigh(-25, 90), weigh(-5, 80)])?.weight)
        XCTAssertEqual(weight.trend.count, 1)
        XCTAssertGreaterThan(weight.trend[0].kg, 80)
    }

    // MARK: - Nutrition

    func test_nutrition_adherence_countsDaysWithinTenPercent() throws {
        let nutrition = try XCTUnwrap(build(
            consumption: [
                eat(-3, kcal: 2000, protein: 150),
                eat(-2, kcal: 2150, protein: 140),
                eat(-1, kcal: 2300, protein: 100),
                eat(0, kcal: 1700, protein: 160),
            ],
            targets: targets
        )?.nutrition)
        XCTAssertEqual(nutrition.loggedDays, 4)
        XCTAssertEqual(nutrition.averageKcal, 2038)
        XCTAssertEqual(try XCTUnwrap(nutrition.kcalAdherence), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(nutrition.proteinAdherence), 0.75, accuracy: 0.001)
    }

    func test_nutrition_unloggedDays_areLeftOut() throws {
        let nutrition = try XCTUnwrap(build(
            consumption: [eat(-2, kcal: 0, protein: 0), eat(-1, kcal: 1800, protein: 120)],
            targets: targets
        )?.nutrition)
        XCTAssertEqual(nutrition.loggedDays, 1)
        XCTAssertEqual(nutrition.averageKcal, 1800)
    }

    func test_nutrition_noTargets_hasNoAdherence() throws {
        let nutrition = try XCTUnwrap(build(consumption: [eat(-1, kcal: 1800, protein: 120)])?.nutrition)
        XCTAssertNil(nutrition.kcalAdherence)
        XCTAssertNil(nutrition.proteinAdherence)
    }

    func test_nutrition_previousWeekAverage_isReported() throws {
        let nutrition = try XCTUnwrap(build(
            consumption: [eat(-9, kcal: 2400, protein: 100), eat(-8, kcal: 2200, protein: 100), eat(-1, kcal: 2000, protein: 100)]
        )?.nutrition)
        XCTAssertEqual(nutrition.previousAverageKcal, 2300)
    }

    // MARK: - Training

    func test_training_twoSessionsOneDay_countOnce() throws {
        let training = try XCTUnwrap(build(workoutDates: [day(-1, hour: 7), day(-1, hour: 18), day(-3)])?.training)
        XCTAssertEqual(training.days, 2)
    }

    func test_training_plannedDays_isTheGoal() throws {
        let training = try XCTUnwrap(build(workoutDates: [day(-1)], planned: 4)?.training)
        XCTAssertEqual(training.goal, 4)
        XCTAssertEqual(training.goalSource, .planned)
    }

    func test_training_noPlan_goalIsThreeWeekAverage() throws {
        let previous = [-8, -10, -12, -15, -17, -22, -24, -26, -27].map { day($0) }
        let training = try XCTUnwrap(build(workoutDates: previous + [day(-1)])?.training)
        XCTAssertEqual(training.previousDays, 3)
        XCTAssertEqual(training.goal, 3)
        XCTAssertEqual(training.goalSource, .usual)
    }

    // MARK: - Sleep

    func test_sleep_averagesEachWeek() throws {
        let sleep = try XCTUnwrap(build(sleep: [
            (day(-9), 8.0), (day(-8), 7.0), (day(-2), 6.0), (day(-1), 7.0), (day(0), 0),
        ])?.sleep)
        XCTAssertEqual(sleep.averageHours, 6.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(sleep.previousAverageHours), 7.5, accuracy: 0.001)
    }

    // MARK: - Suggestion

    func test_suggestion_cutStalledTwoWeeks_eatsLess() {
        let checkIn = build(weights: flatThreeWeeks, consumption: onTargetWeek, targets: targets, goalRaw: "loseFat")
        XCTAssertEqual(checkIn?.suggestion, .weightStalledEatLess(kcal: 150))
    }

    func test_suggestion_stalledButOffTarget_hitsTargetFirst() {
        let checkIn = build(
            weights: flatThreeWeeks,
            consumption: (-6...0).map { eat($0, kcal: 2600, protein: 160) },
            targets: targets,
            goalRaw: "loseFat"
        )
        XCTAssertEqual(checkIn?.suggestion, .hitCalorieTarget)
    }

    func test_suggestion_bulkStalled_eatsMore() {
        let checkIn = build(weights: flatThreeWeeks, consumption: onTargetWeek, targets: targets, goalRaw: "buildMuscle")
        XCTAssertEqual(checkIn?.suggestion, .weightStalledEatMore(kcal: 150))
    }

    func test_suggestion_oneFlatWeek_isNotAStall() {
        let weights = [weigh(-20, 82), weigh(-18, 82)] + flatThreeWeeks.suffix(6)
        let checkIn = build(weights: weights, consumption: onTargetWeek, targets: targets, goalRaw: "loseFat")
        XCTAssertNotEqual(checkIn?.suggestion, .weightStalledEatLess(kcal: 150))
    }

    func test_suggestion_cutLosingOverOnePercent_eatsMore() {
        let weights = [weigh(-12, 81), weigh(-10, 81), weigh(-8, 81), weigh(-5, 80), weigh(-3, 80), weigh(-1, 80)]
        let checkIn = build(weights: weights, consumption: onTargetWeek, targets: targets, goalRaw: "loseFat")
        XCTAssertEqual(checkIn?.suggestion, .losingFast(kcal: 150))
    }

    func test_suggestion_lowProtein_prioritizesProtein() {
        let checkIn = build(consumption: (-6...0).map { eat($0, kcal: 2000, protein: 90) }, targets: targets)
        XCTAssertEqual(checkIn?.suggestion, .prioritizeProtein)
    }

    func test_suggestion_belowPlannedWorkouts_plansWorkouts() {
        let checkIn = build(consumption: onTargetWeek, targets: targets, workoutDates: [day(-2)], planned: 4)
        XCTAssertEqual(checkIn?.suggestion, .planWorkouts(goal: 4))
    }

    func test_suggestion_shortSleep_prioritizesSleep() {
        let checkIn = build(sleep: [(day(-2), 6.0), (day(-1), 6.5)])
        XCTAssertEqual(checkIn?.suggestion, .prioritizeSleep)
    }

    func test_suggestion_cutWithFewWeighIns_asksForMore() {
        let checkIn = build(weights: [weigh(-1, 80)], consumption: onTargetWeek, targets: targets, goalRaw: "loseFat")
        XCTAssertEqual(checkIn?.suggestion, .weighInMore)
    }

    func test_suggestion_everythingOnTrack_keepsGoing() {
        let weights = [weigh(-12, 80.3), weigh(-10, 80.2), weigh(-8, 80.1), weigh(-5, 79.9), weigh(-3, 79.8), weigh(-1, 79.7)]
        let checkIn = build(
            weights: weights,
            consumption: onTargetWeek,
            targets: targets,
            goalRaw: "loseFat",
            workoutDates: [day(-5), day(-3), day(-1)],
            planned: 3,
            sleep: [(day(-2), 7.5)]
        )
        XCTAssertEqual(checkIn?.suggestion, .keepGoing)
    }

    // MARK: - Schedule

    func test_isCheckInDay_sundayAndMonday_only() {
        XCTAssertTrue(WeeklyCheckInEngine.isCheckInDay(now, calendar: calendar))
        XCTAssertTrue(WeeklyCheckInEngine.isCheckInDay(day(1), calendar: calendar))
        XCTAssertFalse(WeeklyCheckInEngine.isCheckInDay(day(3), calendar: calendar))
    }
}
