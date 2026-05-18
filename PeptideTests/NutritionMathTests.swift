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

    /// 75 kg male → BMR 1730 → TDEE 1730·1.55 = 2681.5. After audit L11,
    /// macros round first and calories derive from `4·P + 4·C + 9·F` so
    /// the displayed total always equals the macro sum:
    ///   protein 135g · carbs 368g · fat 74g → 540 + 1472 + 666 = 2678 kcal.
    func test_dailyTargets_male75kg_matchesSpec() {
        let metrics = BodyMetrics(
            weightKg: 75, heightCm: 180, age: 30,
            sex: .male, activityLevel: .moderate, unit: .metric
        )
        let targets = NutritionMath.dailyTargets(for: metrics)
        XCTAssertNotNil(targets)
        XCTAssertEqual(targets?.calories, 2678)
        XCTAssertEqual(targets?.proteinG, 135)
        XCTAssertEqual(targets?.fatG, 74)
        XCTAssertEqual(targets?.carbsG, 368)
        XCTAssertEqual(targets?.fiberG, 30)
    }

    /// Audit Meals L11 — the displayed calorie target must equal
    /// `4·proteinG + 4·carbsG + 9·fatG` so the user never sees the
    /// number disagree with the macro breakdown.
    func test_dailyTargets_caloriesEqualMacroSum() {
        let cases: [BodyMetrics] = [
            BodyMetrics(weightKg: 60, heightCm: 165, age: 25, sex: .female, activityLevel: .light, unit: .metric),
            BodyMetrics(weightKg: 75, heightCm: 180, age: 30, sex: .male,   activityLevel: .moderate, unit: .metric),
            BodyMetrics(weightKg: 95, heightCm: 188, age: 40, sex: .male,   activityLevel: .active,   unit: .metric),
            BodyMetrics(weightKg: 55, heightCm: 160, age: 22, sex: .other,  activityLevel: .athlete,  unit: .metric),
        ]
        for metrics in cases {
            guard let t = NutritionMath.dailyTargets(for: metrics) else {
                XCTFail("Targets nil for \(metrics)"); continue
            }
            let sum = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9
            XCTAssertEqual(
                t.calories, sum,
                "calories \(t.calories) ≠ macro sum \(sum) for \(metrics)"
            )
        }
    }

    /// Audit Meals L12 — activity level now drives TDEE. Bumping a
    /// sedentary user to active must raise the calorie target.
    func test_dailyTargets_activityLevel_movesCalories() {
        func target(_ level: ActivityLevel) -> Int {
            NutritionMath.dailyTargets(for: BodyMetrics(
                weightKg: 75, heightCm: 180, age: 30,
                sex: .male, activityLevel: level, unit: .metric
            ))?.calories ?? 0
        }
        XCTAssertLessThan(target(.sedentary), target(.light))
        XCTAssertLessThan(target(.light),     target(.moderate))
        XCTAssertLessThan(target(.moderate),  target(.active))
        XCTAssertLessThan(target(.active),    target(.athlete))
    }

    /// Multipliers match the published Mifflin-St Jeor PAL bands so a
    /// user comparing across apps sees the same TDEE numbers.
    func test_activityLevel_multipliers_matchPublishedBands() {
        XCTAssertEqual(ActivityLevel.sedentary.tdeeMultiplier, 1.2,   accuracy: 0.001)
        XCTAssertEqual(ActivityLevel.light.tdeeMultiplier,     1.375, accuracy: 0.001)
        XCTAssertEqual(ActivityLevel.moderate.tdeeMultiplier,  1.55,  accuracy: 0.001)
        XCTAssertEqual(ActivityLevel.active.tdeeMultiplier,    1.725, accuracy: 0.001)
        XCTAssertEqual(ActivityLevel.athlete.tdeeMultiplier,   1.9,   accuracy: 0.001)
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
