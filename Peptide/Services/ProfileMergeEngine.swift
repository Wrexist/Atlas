import Foundation

/// Merges divergent copies of the profile so multi-device sync never
/// drops a fact the user logged. Pure; `SwiftDataRepository` applies it.
enum ProfileMergeEngine {

    // MARK: - Duplicate rows

    /// Collapses two profile rows into one. `primary` is the newest row:
    /// its settings and its copy of any record both rows hold win, and it
    /// takes the other row's value only where it has none or still holds
    /// a fresh install's default. Every logged record (meals, weigh-ins,
    /// labs, check-ins, habits) is unioned by id, so a fresh row created
    /// by onboarding on a new device before CloudKit's first import can't
    /// erase the account's history or settings.
    static func reconcile(_ primary: UserProfile, with other: UserProfile) -> UserProfile {
        var merged = primary
        adoptSettings(from: other, into: &merged)
        merged.memberSince = min(primary.memberSince, other.memberSince)
        if merged.name.isEmpty { merged.name = other.name }
        if merged.goals.isEmpty { merged.goals = other.goals }
        if merged.bio.isEmpty { merged.bio = other.bio }
        merged.primaryGoal = merged.primaryGoal ?? other.primaryGoal
        merged.avatarImageData = merged.avatarImageData ?? other.avatarImageData
        merged.nutritionTargets = merged.nutritionTargets ?? other.nutritionTargets
        merged.trainingPreferences = merged.trainingPreferences ?? other.trainingPreferences
        merged.goalDate = merged.goalDate ?? other.goalDate

        merged.weightHistory = union(primary.weightHistory, other.weightHistory).sorted { $0.date < $1.date }
        merged.labHistory = union(primary.labHistory, other.labHistory)
        merged.outcomeHistory = union(primary.outcomeHistory, other.outcomeHistory).sorted { $0.date < $1.date }
        merged.habits = union(primary.habits, other.habits)
        merged.habitEntries = union(primary.habitEntries, other.habitEntries)
        merged.customFoods = union(primary.customFoods, other.customFoods)
        merged.recipes = union(primary.recipes, other.recipes)
        merged.protocolNotes = union(primary.protocolNotes, other.protocolNotes)
        merged.favoriteFoodIDs.formUnion(other.favoriteFoodIDs)
        merged.streakFreezeDays = StreakFreezeService.migratingLegacyKeys(
            primary.streakFreezeDays.union(other.streakFreezeDays)
        )
        merged.progressPhotoFilenames += other.progressPhotoFilenames.filter {
            !primary.progressPhotoFilenames.contains($0)
        }

        if other.atlasScore > primary.atlasScore {
            merged.atlasScore = other.atlasScore
            merged.atlasLevel = other.atlasLevel
            merged.momentumAwardedToday = other.momentumAwardedToday
            merged.lastMomentumAwardDay = other.lastMomentumAwardDay
        }
        merged.momentumHistory = union(primary.momentumHistory, other.momentumHistory).sorted { $0.date < $1.date }

        mergeMeals(from: other, into: &merged, primary: primary)
        return merged
    }

    /// The toggles are adopted together, and only while every one of them
    /// is still a fresh install's: "off" alone can't tell a default from
    /// a choice.
    private static func adoptSettings(from other: UserProfile, into merged: inout UserProfile) {
        let fresh = UserProfile.fresh
        if merged.bodyMetrics == fresh.bodyMetrics { merged.bodyMetrics = other.bodyMetrics }
        if merged.biologyConfig == fresh.biologyConfig { merged.biologyConfig = other.biologyConfig }
        if merged.todayLayout == fresh.todayLayout { merged.todayLayout = other.todayLayout }
        if merged.hapticFeedbackEnabled == fresh.hapticFeedbackEnabled,
           merged.doseRemindersEnabled == fresh.doseRemindersEnabled,
           merged.biometricLockEnabled == fresh.biometricLockEnabled,
           merged.weeklySummaryEnabled == fresh.weeklySummaryEnabled {
            merged.hapticFeedbackEnabled = other.hapticFeedbackEnabled
            merged.doseRemindersEnabled = other.doseRemindersEnabled
            merged.biometricLockEnabled = other.biometricLockEnabled
            merged.weeklySummaryEnabled = other.weeklySummaryEnabled
        }
        merged.creatorAttribution = merged.creatorAttribution ?? other.creatorAttribution
        merged.affiliateApplication = merged.affiliateApplication ?? other.affiliateApplication
        merged.emailSubscription = merged.emailSubscription ?? other.emailSubscription
        merged.lastKnownTimezoneIdentifier = merged.lastKnownTimezoneIdentifier ?? other.lastKnownTimezoneIdentifier
    }

    /// Meals the other row alone holds join the diary. A day only the
    /// other row has keeps its whole bucket (water included); a day both
    /// rows have gains just those meals' macros, so nothing is counted
    /// twice.
    private static func mergeMeals(from other: UserProfile, into merged: inout UserProfile, primary: UserProfile) {
        let known = Set(primary.mealHistory.map(\.id))
        let otherOnly = other.mealHistory.filter { !known.contains($0.id) }
        merged.mealHistory = (primary.mealHistory + otherOnly).sorted { $0.date < $1.date }
        for (key, bucket) in other.dailyConsumption where primary.dailyConsumption[key] == nil {
            merged.dailyConsumption[key] = bucket
        }
        for entry in otherOnly
        where primary.dailyConsumption[LifestyleDataLogic.consumptionKey(for: entry.date)] != nil {
            LifestyleDataLogic.logMeal(
                into: &merged,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                date: entry.date
            )
        }
    }

    // MARK: - Concurrent edits to one row

    /// True when this device changed the meal diary since `baseline`.
    static func mealsChanged(from baseline: UserProfile, to local: UserProfile) -> Bool {
        local.mealHistory != baseline.mealHistory || local.dailyConsumption != baseline.dailyConsumption
    }

    /// Replays this device's meal edits since `baseline` on top of the
    /// diary another device synced into the store meanwhile, instead of
    /// letting the whole meals column overwrite it. Meals added, edited
    /// or deleted here are applied to `remote`'s list; each day's totals
    /// move by exactly what changed here.
    static func rebasingMeals(local: UserProfile, baseline: UserProfile, remote: UserProfile) -> UserProfile {
        guard mealsChanged(from: baseline, to: remote) else { return local }
        let baseByID = Dictionary(baseline.mealHistory.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localIDs = Set(local.mealHistory.map(\.id))
        var meals = remote.mealHistory.filter { baseByID[$0.id] == nil || localIDs.contains($0.id) }
        for entry in local.mealHistory where baseByID[entry.id] != entry {
            if let index = meals.firstIndex(where: { $0.id == entry.id }) {
                meals[index] = entry
            } else {
                meals.append(entry)
            }
        }

        var merged = local
        merged.mealHistory = meals.sorted { $0.date < $1.date }
        merged.dailyConsumption = remote.dailyConsumption
        let days = Set(local.dailyConsumption.keys).union(baseline.dailyConsumption.keys)
        for key in days {
            let mine = local.dailyConsumption[key]
            let base = baseline.dailyConsumption[key]
            guard mine != base, let day = (mine ?? base)?.date else { continue }
            let zero = DailyConsumption.empty(on: day)
            let change = (mine: mine ?? zero, base: base ?? zero)
            var bucket = remote.dailyConsumption[key] ?? zero
            bucket.caloriesKcal = max(0, bucket.caloriesKcal + change.mine.caloriesKcal - change.base.caloriesKcal)
            bucket.proteinG = max(0, bucket.proteinG + change.mine.proteinG - change.base.proteinG)
            bucket.carbsG = max(0, bucket.carbsG + change.mine.carbsG - change.base.carbsG)
            bucket.fatG = max(0, bucket.fatG + change.mine.fatG - change.base.fatG)
            bucket.addWater(fluidOunces: change.mine.waterFluidOunces - change.base.waterFluidOunces)
            merged.dailyConsumption[key] = bucket
        }
        return merged
    }

    // MARK: - Helpers

    private static func union<T: Identifiable>(_ primary: [T], _ other: [T]) -> [T] {
        let known = Set(primary.map(\.id))
        return primary + other.filter { !known.contains($0.id) }
    }
}
