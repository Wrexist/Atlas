import XCTest
@testable import Peptide

final class AdaptiveTDEEEngineTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Fixed "now": midday so today's start-of-day is unambiguous.
    private let now = Date(timeIntervalSince1970: 1_772_366_400) // 2026-03-01 12:00 UTC

    /// A morning timestamp `offset` days from today (negative = past).
    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .hour, value: offset * 24 + 8, to: today)!
    }

    private func weights(_ offsets: some Sequence<Int>, kg: (Int) -> Double) -> [WeightEntry] {
        offsets.map { WeightEntry(date: day($0), kg: kg($0)) }
    }

    private func intake(_ offsets: some Sequence<Int>, kcal: Int) -> [DailyConsumption] {
        offsets.map {
            DailyConsumption(
                date: calendar.startOfDay(for: day($0)),
                caloriesKcal: kcal, proteinG: 0, carbsG: 0, fatG: 0, waterOz: 0
            )
        }
    }

    /// Linear loss of `kgPerWeek` ending at 80 kg today.
    private func losing(_ kgPerWeek: Double) -> (Int) -> Double {
        { offset in 80 - kgPerWeek / 7 * Double(offset) }
    }

    private func estimate(
        weights: [WeightEntry],
        intake: [DailyConsumption],
        formula: Double? = 2_200
    ) -> AdaptiveTDEEEngine.Estimate? {
        AdaptiveTDEEEngine.estimate(
            weights: weights, intake: intake, formulaTDEE: formula, asOf: now, calendar: calendar
        )
    }

    private let fullWindowWeighIns = -28...0
    private let fullWindowIntake = -28 ... -1

    // MARK: - Insufficient data

    func test_noData_fallsBackToFormula() {
        let result = estimate(weights: [], intake: [])
        XCTAssertEqual(result?.source, .formula)
        XCTAssertEqual(result?.kcal, 2_200)
        XCTAssertEqual(result?.intakeDays, 0)
        XCTAssertNil(result?.weightChangeKgPerWeek)
    }

    func test_noDataAndNoFormula_returnsNil() {
        XCTAssertNil(estimate(weights: [], intake: [], formula: nil))
    }

    func test_nineIntakeDays_fallsBackToFormula() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { _ in 80 },
            intake: intake(-9 ... -1, kcal: 2_500),
            formula: 2_000
        )
        XCTAssertEqual(result?.source, .formula)
        XCTAssertEqual(result?.kcal, 2_000)
    }

    func test_weighInSpanUnderTwoWeeks_fallsBackToFormula() {
        let result = estimate(
            weights: weights(-13...0) { _ in 80 },
            intake: intake(fullWindowIntake, kcal: 2_500),
            formula: 2_000
        )
        XCTAssertEqual(result?.source, .formula)
    }

    func test_onlyTwoWeighIns_fallsBackToFormula() {
        let result = estimate(
            weights: weights([-20, 0]) { _ in 80 },
            intake: intake(fullWindowIntake, kcal: 2_500)
        )
        XCTAssertEqual(result?.source, .formula)
    }

    func test_dataOlderThanWindow_isIgnored() {
        let result = estimate(
            weights: weights(-60 ... -29) { _ in 80 },
            intake: intake(-60 ... -29, kcal: 2_500)
        )
        XCTAssertEqual(result?.source, .formula)
    }

    func test_partialLogDays_areNotCountedAsIntake() {
        let real = intake(-12 ... -1, kcal: 2_500)
        let partial = intake(-20 ... -16, kcal: 300)
        let result = estimate(weights: weights(fullWindowWeighIns) { _ in 80 }, intake: real + partial, formula: nil)
        XCTAssertEqual(result?.intakeDays, 12)
        XCTAssertEqual(result?.kcal, 2_500)
    }

    func test_todaysPartialIntake_isExcluded() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { _ in 80 },
            intake: intake(fullWindowIntake, kcal: 2_500) + intake([0], kcal: 900),
            formula: nil
        )
        XCTAssertEqual(result?.intakeDays, 28)
        XCTAssertEqual(result?.kcal, 2_500)
    }

    // MARK: - Energy balance

    func test_steadyWeight_expenditureEqualsIntake() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { _ in 80 },
            intake: intake(fullWindowIntake, kcal: 2_500)
        )
        XCTAssertEqual(result?.source, .adaptive)
        XCTAssertEqual(result?.kcal, 2_500)
        XCTAssertEqual(result?.intakeDays, 28)
        XCTAssertEqual(result?.weightChangeKgPerWeek ?? .nan, 0, accuracy: 0.001)
    }

    /// Eating 2 000 kcal while losing 0.5 kg/week → 0.5 × 7 700 / 7 = 550
    /// kcal/day deficit, so expenditure ≈ 2 550.
    func test_losingWeightWhileEating2000_expenditureIsIntakePlusDeficit() {
        let result = estimate(
            weights: weights(fullWindowWeighIns, kg: losing(0.5)),
            intake: intake(fullWindowIntake, kcal: 2_000)
        )
        XCTAssertEqual(result?.source, .adaptive)
        XCTAssertEqual(Double(result?.kcal ?? 0), 2_550, accuracy: 2)
        XCTAssertEqual(result?.weightChangeKgPerWeek ?? .nan, -0.5, accuracy: 0.001)
    }

    func test_gainingWeightWhileEating3000_expenditureIsIntakeMinusSurplus() {
        let result = estimate(
            weights: weights(fullWindowWeighIns, kg: losing(-0.25)),
            intake: intake(fullWindowIntake, kcal: 3_000)
        )
        XCTAssertEqual(Double(result?.kcal ?? 0), 2_725, accuracy: 2)
    }

    func test_noisyWeights_stillRecoverTrend() {
        let noise = [0.6, -0.4, 0.8, -0.7, 0.2, -0.5, 0.0]
        let trend = losing(0.5)
        let result = estimate(
            weights: weights(fullWindowWeighIns) { trend($0) + noise[($0 + 28) % 7] },
            intake: intake(fullWindowIntake, kcal: 2_000)
        )
        XCTAssertEqual(Double(result?.kcal ?? 0), 2_550, accuracy: 100)
    }

    func test_typoWeighIn_isClampedToTrend() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { $0 == -10 ? 8 : 80 },
            intake: intake(fullWindowIntake, kcal: 2_500)
        )
        XCTAssertEqual(Double(result?.kcal ?? 0), 2_500, accuracy: 100)
    }

    func test_typoFirstWeighIn_cannotAnchorTrend() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { $0 == -28 ? 180 : 80 },
            intake: intake(fullWindowIntake, kcal: 2_500)
        )
        XCTAssertEqual(Double(result?.kcal ?? 0), 2_500, accuracy: 150)
    }

    func test_multipleWeighInsSameDay_latestWins() {
        let flat = weights(fullWindowWeighIns) { _ in 80 }
        let earlierTypo = WeightEntry(date: day(0).addingTimeInterval(-3_600), kg: 90)
        let result = estimate(weights: flat + [earlierTypo], intake: intake(fullWindowIntake, kcal: 2_500))
        XCTAssertEqual(result?.kcal, 2_500)
    }

    // MARK: - Gaps

    func test_sparseWeighInsAndIntake_stillEstimate() {
        let result = estimate(
            weights: weights(stride(from: -28, through: 0, by: 3), kg: losing(0.5)),
            intake: intake((-28 ... -1).filter { $0 % 3 != 0 }, kcal: 2_000),
            formula: nil
        )
        XCTAssertEqual(result?.source, .adaptive)
        XCTAssertEqual(result?.intakeDays, 19)
        XCTAssertEqual(Double(result?.kcal ?? 0), 2_550, accuracy: 2)
    }

    // MARK: - Blending toward the formula

    /// 14 intake days → confidence 14/21; 2/3 × 2 500 + 1/3 × 2 000 = 2 333.
    func test_partialData_blendsTowardFormula() {
        let result = estimate(
            weights: weights(stride(from: -28, through: 0, by: 4)) { _ in 80 },
            intake: intake(stride(from: -28, through: -1, by: 2), kcal: 2_500),
            formula: 2_000
        )
        XCTAssertEqual(result?.source, .adaptive)
        XCTAssertEqual(result?.intakeDays, 14)
        XCTAssertEqual(result?.kcal, 2_333)
    }

    /// Bare minimum (10 days, 14-day span) → confidence 10/21.
    func test_minimumData_leansOnFormula() {
        let result = estimate(
            weights: weights(stride(from: -14, through: 0, by: 2)) { _ in 80 },
            intake: intake(-10 ... -1, kcal: 2_500),
            formula: 2_000
        )
        XCTAssertEqual(result?.source, .adaptive)
        XCTAssertEqual(result?.kcal, 2_238)
    }

    func test_fullData_ignoresFormula() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { _ in 80 },
            intake: intake(fullWindowIntake, kcal: 2_500),
            formula: 1_500
        )
        XCTAssertEqual(result?.kcal, 2_500)
    }

    // MARK: - Bounds

    /// 3 kg/week is clamped to 1.5 kg/week → at most 1 650 kcal/day deficit.
    func test_implausibleWeightLossRate_isClamped() {
        let result = estimate(
            weights: weights(fullWindowWeighIns, kg: losing(3)),
            intake: intake(fullWindowIntake, kcal: 2_000),
            formula: nil
        )
        XCTAssertEqual(result?.kcal, 3_650)
        XCTAssertEqual(result?.weightChangeKgPerWeek ?? .nan, -1.5, accuracy: 0.001)
    }

    func test_absurdIntake_isCappedToExpenditureBounds() {
        let result = estimate(
            weights: weights(fullWindowWeighIns) { _ in 80 },
            intake: intake(fullWindowIntake, kcal: 9_000),
            formula: nil
        )
        XCTAssertEqual(result?.kcal, 5_000)
    }

    // MARK: - Following the recommendation

    private func targets(_ kcal: Int) -> NutritionTargets {
        NutritionTargets(calories: kcal, proteinG: 150, carbsG: 200, fatG: 60, fiberG: 30)
    }

    func test_shouldFollow_acceptedRecommendationMovedEnough_isTrue() {
        XCTAssertTrue(AdaptiveTDEEEngine.shouldFollow(current: targets(2_000), followedCalories: 2_000, next: targets(2_100)))
    }

    func test_shouldFollow_customTargets_isFalse() {
        XCTAssertFalse(AdaptiveTDEEEngine.shouldFollow(current: targets(2_000), followedCalories: nil, next: targets(2_300)))
        XCTAssertFalse(AdaptiveTDEEEngine.shouldFollow(current: targets(2_000), followedCalories: 1_900, next: targets(2_300)))
    }

    func test_shouldFollow_smallMove_isFalse() {
        XCTAssertFalse(AdaptiveTDEEEngine.shouldFollow(current: targets(2_000), followedCalories: 2_000, next: targets(2_040)))
    }

    // MARK: - NutritionMath integration

    func test_recommendedTargets_withMaintenance_appliesGoalToMeasuredTDEE() {
        let metrics = BodyMetrics(
            weightKg: 80, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        )
        let cut = NutritionMath.recommendedTargets(for: metrics, goalRaw: "loseFat", maintenanceKcal: 3_000)
        XCTAssertEqual(Double(cut?.calories ?? 0), 2_400, accuracy: 10)
    }

    func test_recommendedTargets_withoutMaintenance_matchesFormula() {
        let metrics = BodyMetrics(
            weightKg: 80, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        )
        let formula = NutritionMath.formulaTDEE(for: metrics)!
        let viaFormula = NutritionMath.recommendedTargets(for: metrics, goalRaw: "maintain")
        let viaOverride = NutritionMath.recommendedTargets(for: metrics, goalRaw: "maintain", maintenanceKcal: formula)
        XCTAssertEqual(viaFormula, viaOverride)
    }
}
