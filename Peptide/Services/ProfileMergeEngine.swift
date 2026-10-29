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
        merged.outcomeHistory = mergeOutcomes(primary.outcomeHistory, other.outcomeHistory)
        merged.habits = union(primary.habits, other.habits)
        merged.habitEntries = mergeHabitEntries(primary.habitEntries, other.habitEntries)
        merged.workoutHistory = union(primary.workoutHistory, other.workoutHistory)
        merged.customFoods = union(primary.customFoods, other.customFoods)
        merged.recipes = union(primary.recipes, other.recipes)
        merged.protocolNotes = union(primary.protocolNotes, other.protocolNotes)
        merged.supplements = mergeSupplements(primary.supplements, other.supplements)
        merged.favoriteFoodIDs.formUnion(other.favoriteFoodIDs)
        merged.favoriteRecipeIDs.formUnion(other.favoriteRecipeIDs)
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
        merged.emailSubscription = merged.emailSubscription ?? other.emailSubscription
        merged.lastKnownTimezoneIdentifier = merged.lastKnownTimezoneIdentifier ?? other.lastKnownTimezoneIdentifier
    }

    /// Meals the other row alone holds join the diary. A day only the
    /// other row has keeps its whole bucket; a day both rows have gains
    /// just those meals' macros, so nothing is counted twice, plus the
    /// other row's water, which has no per-glass record to match on
    /// (an identical bucket is the same day twice and adds nothing).
    private static func mergeMeals(from other: UserProfile, into merged: inout UserProfile, primary: UserProfile) {
        let known = Set(primary.mealHistory.map(\.id))
        let otherOnly = other.mealHistory.filter { !known.contains($0.id) }
        merged.mealHistory = (primary.mealHistory + otherOnly).sorted { $0.date < $1.date }
        // Rows sharing a meal are copies of one history (a backup restored
        // on two devices), so their water is the same water: the larger
        // total stays rather than the sum.
        let copies = otherOnly.count < other.mealHistory.count
        for (key, bucket) in other.dailyConsumption {
            guard let own = primary.dailyConsumption[key] else {
                merged.dailyConsumption[key] = bucket
                continue
            }
            guard own != bucket else { continue }
            let water = copies ? max(0, bucket.waterFluidOunces - own.waterFluidOunces) : bucket.waterFluidOunces
            merged.dailyConsumption[key]?.addWater(fluidOunces: water)
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

    /// True when this device changed, since `baseline`, anything a save
    /// writes as a whole column holding more than one fact: the meal
    /// diary, a record list, or a field in the shared residual blob.
    static func needsRebase(from baseline: UserProfile, to local: UserProfile) -> Bool {
        mealsChanged(from: baseline, to: local)
            || recordLists.contains { $0.changed(baseline, local) }
            || blobFields.contains { $0.changed(baseline, local) }
    }

    /// Replays this device's edits since `baseline` onto `remote`, the
    /// row as the store holds it now: meals as `rebasingMeals` does,
    /// record lists by id (adds, edits and deletes), and each residual
    /// blob field this device left alone taken from `remote`. Otherwise
    /// a column written here would replace whatever another device
    /// changed in it since this device last read the row.
    static func rebasing(local: UserProfile, baseline: UserProfile, remote: UserProfile) -> UserProfile {
        var merged = rebasingMeals(local: local, baseline: baseline, remote: remote)
        for list in recordLists { list.rebase(&merged, baseline, remote) }
        for field in blobFields where !field.changed(baseline, local) { field.adopt(&merged, remote) }
        merged.weightHistory.sort { $0.date < $1.date }
        merged.outcomeHistory.sort { $0.date < $1.date }
        return merged
    }

    private struct RecordList {
        let changed: (UserProfile, UserProfile) -> Bool
        let rebase: (inout UserProfile, UserProfile, UserProfile) -> Void

        static func of<Record: Identifiable & Equatable>(_ keyPath: WritableKeyPath<UserProfile, [Record]>) -> RecordList {
            RecordList(
                changed: { $0[keyPath: keyPath] != $1[keyPath: keyPath] },
                rebase: { merged, baseline, remote in
                    merged[keyPath: keyPath] = ProfileMergeEngine.rebasingRecords(
                        local: merged[keyPath: keyPath],
                        baseline: baseline[keyPath: keyPath],
                        remote: remote[keyPath: keyPath]
                    )
                }
            )
        }

        /// Like `.of(\.supplements)`, but a supplement both devices
        /// touched keeps the days the other device checked or unchecked:
        /// this device's day changes are replayed onto `remote`'s days.
        static var supplements: RecordList {
            RecordList(
                changed: { $0.supplements != $1.supplements },
                rebase: { merged, baseline, remote in
                    let local = merged.supplements
                    let baseByID = Dictionary(baseline.supplements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    let remoteByID = Dictionary(remote.supplements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    let rebased = ProfileMergeEngine.rebasingRecords(local: local, baseline: baseline.supplements, remote: remote.supplements)
                    merged.supplements = rebased.map { (supplement: Supplement) -> Supplement in
                        guard let theirs = remoteByID[supplement.id], let base = baseByID[supplement.id],
                              let mine = local.first(where: { $0.id == supplement.id }) else { return supplement }
                        let added = Set(mine.takenDays).subtracting(base.takenDays)
                        let removed = Set(base.takenDays).subtracting(mine.takenDays)
                        var copy = supplement
                        copy.takenDays = Set(theirs.takenDays).union(added).subtracting(removed).sorted()
                        return copy
                    }
                }
            )
        }
    }

    private struct BlobField {
        let changed: (UserProfile, UserProfile) -> Bool
        let adopt: (inout UserProfile, UserProfile) -> Void

        static func of<Value: Equatable>(_ keyPath: WritableKeyPath<UserProfile, Value>) -> BlobField {
            BlobField(
                changed: { $0[keyPath: keyPath] != $1[keyPath: keyPath] },
                adopt: { merged, remote in merged[keyPath: keyPath] = remote[keyPath: keyPath] }
            )
        }
    }

    private static var recordLists: [RecordList] {
        [
            .of(\.habits), .of(\.habitEntries), .of(\.weightHistory), .of(\.labHistory),
            .of(\.outcomeHistory), .of(\.customFoods), .of(\.recipes), .of(\.protocolNotes),
            .supplements,
        ]
    }

    /// Fields written as part of a column shared with other facts: the
    /// food library's favourites and what `ProfileExtension.residual`
    /// packs into one blob.
    private static var blobFields: [BlobField] {
        [
            .of(\.favoriteFoodIDs), .of(\.favoriteRecipeIDs),
            .of(\.nutritionTargets),
            .of(\.emailSubscription), .of(\.progressPhotoFilenames), .of(\.workoutHistory),
            .of(\.healthKitNutritionEnabled), .of(\.workoutLegacyMigrationCompleted),
            .of(\.lastKnownTimezoneIdentifier), .of(\.streakFreezeDays), .of(\.biologyConfig),
            .of(\.todayLayout), .of(\.trainingPreferences), .of(\.weeklySummaryEnabled),
            .of(\.weeklySummaryOptInConfirmed), .of(\.goalDate),
        ]
    }

    /// `remote`'s records with this device's adds, edits and deletes
    /// since `baseline` applied, in `remote`'s order with new ones last.
    private static func rebasingRecords<Record: Identifiable & Equatable>(
        local: [Record], baseline: [Record], remote: [Record]
    ) -> [Record] {
        let baseByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localIDs = Set(local.map(\.id))
        var records = remote.filter { baseByID[$0.id] == nil || localIDs.contains($0.id) }
        var indexByID = Dictionary(records.indices.map { (records[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in local where baseByID[record.id] != record {
            if let index = indexByID[record.id] {
                records[index] = record
            } else {
                indexByID[record.id] = records.count
                records.append(record)
            }
        }
        return records
    }

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

    /// Check-ins carry random ids, so both rows checking one habit on one
    /// day would otherwise leave two entries; the larger count stays.
    private static func mergeHabitEntries(_ primary: [HabitEntry], _ other: [HabitEntry]) -> [HabitEntry] {
        struct HabitDay: Hashable { let habitId: UUID; let day: Date }
        let calendar = Calendar.current
        func key(_ entry: HabitEntry) -> HabitDay {
            HabitDay(habitId: entry.habitId, day: calendar.startOfDay(for: entry.date))
        }
        var merged = primary
        var indexByKey = Dictionary(primary.indices.map { (key(primary[$0]), $0) }, uniquingKeysWith: { first, _ in first })
        for entry in other {
            if let index = indexByKey[key(entry)] {
                merged[index].value = max(merged[index].value, entry.value)
            } else {
                indexByKey[key(entry)] = merged.count
                merged.append(entry)
            }
        }
        return merged
    }

    /// A supplement both rows hold keeps the primary's settings and the
    /// days either row checked it off.
    private static func mergeSupplements(_ primary: [Supplement], _ other: [Supplement]) -> [Supplement] {
        let otherByID = Dictionary(other.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = primary.map { (supplement: Supplement) -> Supplement in
            guard let theirs = otherByID[supplement.id] else { return supplement }
            var copy = supplement
            copy.takenDays = Set(supplement.takenDays).union(theirs.takenDays).sorted()
            return copy
        }
        return union(merged, other)
    }

    /// One outcome check-in per day; the more recently edited one stays.
    private static func mergeOutcomes(_ primary: [OutcomeEntry], _ other: [OutcomeEntry]) -> [OutcomeEntry] {
        let calendar = Calendar.current
        var merged = primary
        var indexByDay = Dictionary(primary.indices.map { (calendar.startOfDay(for: primary[$0].date), $0) },
                                    uniquingKeysWith: { first, _ in first })
        for entry in other {
            let day = calendar.startOfDay(for: entry.date)
            if let index = indexByDay[day] {
                if entry.id != merged[index].id, entry.updatedAt > merged[index].updatedAt { merged[index] = entry }
            } else {
                indexByDay[day] = merged.count
                merged.append(entry)
            }
        }
        return merged.sorted { $0.date < $1.date }
    }

    private static func union<T: Identifiable>(_ primary: [T], _ other: [T]) -> [T] {
        let known = Set(primary.map(\.id))
        return primary + other.filter { !known.contains($0.id) }
    }
}
