import Foundation

/// Pure functions that translate body metrics into a daily calorie/macro
/// reference using Mifflin-St Jeor for BMR, a fixed moderate-activity
/// multiplier (1.55) for TDEE, and a balanced 1.8 g/kg-protein /
/// 25%-fat / fill-with-carbs split. These numbers are reference
/// targets — not medical advice — and are surfaced behind a disclaimer.
enum NutritionMath {

    /// Fallback activity multiplier when the user hasn't picked an
    /// `ActivityLevel`. Equivalent to `.moderate` — the value that
    /// used to be hard-coded for everyone (audit Meals L12).
    /// Live callers should read `BodyMetrics.activityLevel
    /// .tdeeMultiplier` to honor the user's pick.
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
        let tdee = bmr * metrics.activityLevel.tdeeMultiplier

        // Round the macros first, then derive calories from the
        // rounded values. Otherwise the displayed `calories` value
        // (Int(tdee.rounded())) wouldn't equal `proteinG*4 + carbsG*4
        // + fatG*9` once each macro got individually rounded — the
        // "your macros sum to 2,051 but your target is 2,054" mismatch
        // confuses users who notice the numbers don't add up
        // (audit Meals L11).
        let fatCalories = tdee * fatCalorieFraction
        let fatGRaw = fatCalories / kcalPerGramFat
        // Clamp protein so it can never exceed 40% of TDEE. For a
        // heavy, sedentary user `weightKg * proteinPerKg` could push
        // protein calories past `tdee - fatCalories`, flooring carbs
        // at 0 and leaving a protein-only target that badly undershoots
        // TDEE. The cap keeps the macro split realistic.
        let proteinCalorieCeiling = tdee * 0.40
        let proteinCalories = min(weightKg * proteinPerKg * kcalPerGramProtein, proteinCalorieCeiling)
        let proteinGRaw = proteinCalories / kcalPerGramProtein
        let carbCalories = max(0, tdee - proteinCalories - fatCalories)
        let carbsGRaw = carbCalories / kcalPerGramCarbs

        let proteinG = Int(proteinGRaw.rounded())
        let fatG = Int(fatGRaw.rounded())
        let carbsG = Int(carbsGRaw.rounded())
        let derivedCalories = proteinG * Int(kcalPerGramProtein)
            + carbsG * Int(kcalPerGramCarbs)
            + fatG * Int(kcalPerGramFat)

        return NutritionTargets(
            calories: derivedCalories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberDefaultG
        )
    }

    /// Calorie strategy implied by the user's primary goal. Build /
    /// strength goals lean into a lean surplus, fat loss into a moderate
    /// deficit, and everything else holds at maintenance. Recomp is a
    /// deliberate slight deficit — the body-recomposition sweet spot for
    /// trained lifters eating at-or-just-below maintenance with high
    /// protein.
    enum GoalIntent {
        case surplus
        case deficit
        case recomp
        case maintenance

        /// Maps a persisted `primaryGoal` raw value (the `PrimaryGoal`
        /// rawValues from onboarding) to a calorie strategy. Unknown or
        /// nil goals fall back to maintenance.
        init(goalRaw: String?) {
            switch goalRaw {
            case "buildMuscle", "getStronger", "athletic":
                self = .surplus
            case "loseFat":
                self = .deficit
            case "recomp":
                self = .recomp
            default:
                self = .maintenance
            }
        }

        /// Multiplier applied to maintenance TDEE.
        var calorieMultiplier: Double {
            switch self {
            case .surplus:     return 1.10   // ~+10% lean bulk
            case .deficit:     return 0.80   // ~-20% sustainable cut
            case .recomp:      return 0.95   // slight deficit, high protein
            case .maintenance: return 1.0
            }
        }

        /// Protein target in g/kg. Bumped above the maintenance default
        /// in a deficit (protein preserves lean mass when calories are
        /// low) and for muscle-building goals.
        var proteinPerKg: Double {
            switch self {
            case .surplus:     return 2.0
            case .deficit:     return 2.2
            case .recomp:      return 2.2
            case .maintenance: return 1.8
            }
        }

        var shortLabel: String {
            switch self {
            case .surplus:     return "lean gain"
            case .deficit:     return "fat loss"
            case .recomp:      return "recomposition"
            case .maintenance: return "maintenance"
            }
        }
    }

    /// Goal-aware daily targets. Computes maintenance TDEE, applies the
    /// goal's calorie strategy, then sets protein from bodyweight (goal-
    /// adjusted), fat at 25% of the adjusted calories, and fills the
    /// remainder with carbs. Returns nil when body metrics are
    /// incomplete — the caller should fall back to manual entry.
    ///
    /// This is the value behind the editor's "Recommended for you" card:
    /// it folds in everything the profile knows (weight, height, age,
    /// sex, activity level) plus the user's stated goal.
    static func recommendedTargets(
        for metrics: BodyMetrics,
        goalRaw: String?
    ) -> NutritionTargets? {
        guard
            let weightKg = metrics.weightKg, weightKg > 0,
            let heightCm = metrics.heightCm, heightCm > 0,
            let age = metrics.age, age > 0
        else {
            return nil
        }

        let intent = GoalIntent(goalRaw: goalRaw)
        let bmr = mifflinStJeor(weightKg: weightKg, heightCm: heightCm, age: age, sex: metrics.sex)
        let tdee = bmr * metrics.activityLevel.tdeeMultiplier
        let targetCalories = tdee * intent.calorieMultiplier

        let fatCalories = targetCalories * fatCalorieFraction
        let fatGRaw = fatCalories / kcalPerGramFat

        // Cap protein at 45% of target calories so an aggressive g/kg on
        // a heavy, low-calorie cut can't crowd out carbs entirely.
        let proteinCalorieCeiling = targetCalories * 0.45
        let proteinCalories = min(weightKg * intent.proteinPerKg * kcalPerGramProtein, proteinCalorieCeiling)
        let proteinGRaw = proteinCalories / kcalPerGramProtein
        let carbCalories = max(0, targetCalories - proteinCalories - fatCalories)
        let carbsGRaw = carbCalories / kcalPerGramCarbs

        let proteinG = Int(proteinGRaw.rounded())
        let fatG = Int(fatGRaw.rounded())
        let carbsG = Int(carbsGRaw.rounded())
        let derivedCalories = proteinG * Int(kcalPerGramProtein)
            + carbsG * Int(kcalPerGramCarbs)
            + fatG * Int(kcalPerGramFat)

        return NutritionTargets(
            calories: derivedCalories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
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
