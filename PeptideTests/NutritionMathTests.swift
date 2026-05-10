import XCTest
@testable import Peptide

final class NutritionMathTests: XCTestCase {

    // MARK: - Mifflin-St Jeor BMR

    /// Worked example from the spec: 75 kg, 180 cm, 30-year-old male.
    /// BMR = 10·75 + 6.25·180 - 5·30 + 5 = 750 + 1125 - 150 + 5 = 1730
    func test_mifflinStJeor_male_matchesSpec() {
        let bmr = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .male)
        XCTAssertEqual(bmr, 1730, accuracy: 0.001)
    }

    /// Female constant is -161 instead of +5 → 1730 - 5 - 161 = 1564.
    func test_mifflinStJeor_female_matchesSpec() {
        let bmr = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .female)
        XCTAssertEqual(bmr, 1564, accuracy: 0.001)
    }

    /// `.other` and `.unspecified` should sit halfway between the two
    /// spec constants — average of +5 and -161 is -78.
    func test_mifflinStJeor_other_isAverageOfMaleAndFemale() {
        let male = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .male)
        let female = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .female)
        let other = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .other)
        XCTAssertEqual(other, (male + female) / 2, accuracy: 0.001)
    }

    func test_mifflinStJeor_unspecified_matchesOther() {
        let other = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .other)
        let unspec = NutritionMath.mifflinStJeor(weightKg: 75, heightCm: 180, age: 30, sex: .unspecified)
        XCTAssertEqual(other, unspec, accuracy: 0.001)
    }

    // MARK: - Daily targets pipeline

    /// 75 kg male → BMR 1730 → TDEE 1730·1.55 = 2681.5 → 2682 kcal/day.
    /// Protein = 75·1.8 = 135 g. Fat calories = 2681.5·0.25 = 670.375 → 74.486 g.
    /// Carbs = (2681.5 - 540 - 670.375) / 4 = 367.781 g.
    func test_dailyTargets_male75kg_matchesSpec() {
        let metrics = BodyMetrics(
            weightKg: 75, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        )
        let targets = NutritionMath.dailyTargets(for: metrics)
        XCTAssertNotNil(targets)
        XCTAssertEqual(targets?.calories, 2682)
        XCTAssertEqual(targets?.proteinG, 135)
        XCTAssertEqual(targets?.fatG, 74)
        XCTAssertEqual(targets?.carbsG, 368)
        XCTAssertEqual(targets?.fiberG, 30)
    }

    /// Returns nil when any input the formula needs is missing — callers
    /// rely on this to render a placeholder rather than zeros.
    func test_dailyTargets_missingHeight_returnsNil() {
        let metrics = BodyMetrics(
            weightKg: 75, heightCm: nil, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        )
        XCTAssertNil(NutritionMath.dailyTargets(for: metrics))
    }

    func test_dailyTargets_missingAge_returnsNil() {
        let metrics = BodyMetrics(
            weightKg: 75, heightCm: 180, age: nil,
            sex: .male, activityLevel: .moderate, unit: .metric
        )
        XCTAssertNil(NutritionMath.dailyTargets(for: metrics))
    }

    /// Reducing weight by 10 kg should reduce both calories and protein —
    /// quick sanity check that the inputs flow through the pipeline.
    func test_dailyTargets_lowerWeight_reducesCaloriesAndProtein() {
        let heavier = NutritionMath.dailyTargets(for: BodyMetrics(
            weightKg: 80, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        ))
        let lighter = NutritionMath.dailyTargets(for: BodyMetrics(
            weightKg: 70, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        ))

        XCTAssertNotNil(heavier)
        XCTAssertNotNil(lighter)
        XCTAssertGreaterThan(heavier!.calories, lighter!.calories)
        XCTAssertGreaterThan(heavier!.proteinG, lighter!.proteinG)
    }
}
