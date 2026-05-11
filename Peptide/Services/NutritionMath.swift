import Foundation

/// Pure functions that translate body metrics into a daily calorie/macro
/// reference using Mifflin-St Jeor for BMR, a fixed moderate-activity
/// multiplier (1.55) for TDEE, and a balanced 1.8 g/kg-protein /
/// 25%-fat / fill-with-carbs split. These numbers are reference
/// targets — not medical advice — and are surfaced behind a disclaimer.
enum NutritionMath {

    /// Activity multiplier used for the onboarding TDEE estimate. The
    /// product spec hard-codes "moderate" so the screen renders a single
    /// number without asking the user to pick an activity bucket.
    static let activityMultiplier: Double = 1.55

    /// Protein recommendation in grams per kilogram of bodyweight.
    static let proteinPerKg: Double = 1.8

    /// Fraction of TDEE allocated to fat before splitting the remainder
    /// into protein and carbohydrate calories.
    static let fatCalorieFraction: Double = 0.25

    /// Average fiber target (the spec's 25–38 g/day band, midpoint).
    static let fiberDefaultG: Int = 30

    /// Calories per gram of each macronutrient.
    private static let kcalPerGramProtein: Double = 4
    private static let kcalPerGramCarbs: Double = 4
    private static let kcalPerGramFat: Double = 9

    /// Returns nil when any input the formula needs is missing or the values
    /// are out of a sane range. Callers should treat nil as "show
    /// placeholder, don't compute".
    static func dailyTargets(for metrics: BodyMetrics) -> NutritionTargets? {
        guard
            let weightKg = metrics.weightKg, weightKg > 0,
            let heightCm = metrics.heightCm, heightCm > 0,
            let age = metrics.age, age > 0
        else {
            return nil
        }

        let bmr = mifflinStJeor(weightKg: weightKg, heightCm: heightCm, age: age, sex: metrics.sex)
        let tdee = bmr * activityMultiplier

        let proteinG = weightKg * proteinPerKg
        let fatCalories = tdee * fatCalorieFraction
        let fatG = fatCalories / kcalPerGramFat
        let proteinCalories = proteinG * kcalPerGramProtein
        let carbCalories = max(0, tdee - proteinCalories - fatCalories)
        let carbsG = carbCalories / kcalPerGramCarbs

        return NutritionTargets(
            calories: Int(tdee.rounded()),
            proteinG: Int(proteinG.rounded()),
            carbsG: Int(carbsG.rounded()),
            fatG: Int(fatG.rounded()),
            fiberG: fiberDefaultG
        )
    }

    /// Mifflin-St Jeor BMR in kilocalories. The `.other` and `.unspecified`
    /// cases use the average of the male/female constants (-78) so a
    /// non-binary user still gets a reasonable estimate without forcing
    /// them into a sex they don't identify with.
    static func mifflinStJeor(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: BiologicalSex
    ) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male:        return base + 5
        case .female:      return base - 161
        case .other,
             .unspecified: return base - 78
        }
    }
}
