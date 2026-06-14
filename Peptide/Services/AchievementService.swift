import Foundation

struct Achievement: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let icon: String
    var unlockedDate: Date?

    var isUnlocked: Bool { unlockedDate != nil }
}

@MainActor @Observable
final class AchievementService {
    static let shared = AchievementService()

    private(set) var achievements: [Achievement] = []
    /// FIFO queue of freshly-unlocked achievements awaiting a toast.
    /// A single save can cross multiple milestones (e.g. a dose count
    /// and a meal count) — a single slot would drop all but the last,
    /// so unlocks queue and the consumer drains them one at a time.
    private(set) var pendingUnlocks: [Achievement] = []

    /// The achievement the celebration toast should currently show —
    /// the head of `pendingUnlocks`. Consumers observe this, present
    /// the toast, then call `acknowledgeLatestUnlock()` to advance.
    var latestUnlock: Achievement? { pendingUnlocks.first }

    private let persistenceKey = "achievements"
    private let defaults = UserDefaults.standard

    private init() {
        loadAchievements()
    }

    func checkAchievements(totalDoses: Int, currentStreak: Int, bestStreak: Int, protocolCount: Int, daysLogged: Int) {
        // Don't reset latestUnlock here — see `acknowledgeLatestUnlock`.
        // Resetting clobbers any unlock another check method just wrote
        // when the two methods run back-to-back on the same save.
        let unlocksBefore = pendingUnlocks.count
        unlock("first_dose", if: totalDoses >= 1)
        unlock("ten_doses", if: totalDoses >= 10)
        unlock("fifty_doses", if: totalDoses >= 50)
        unlock("hundred_doses", if: totalDoses >= 100)
        unlock("five_hundred_doses", if: totalDoses >= 500)

        unlock("streak_3", if: currentStreak >= 3)
        unlock("streak_7", if: currentStreak >= 7)
        unlock("streak_14", if: currentStreak >= 14)
        unlock("streak_30", if: currentStreak >= 30)
        unlock("streak_90", if: currentStreak >= 90)

        unlock("first_protocol", if: protocolCount >= 1)
        unlock("three_protocols", if: protocolCount >= 3)

        unlock("week_logged", if: daysLogged >= 7)
        unlock("month_logged", if: daysLogged >= 30)

        // Only persist when something actually unlocked — this runs on
        // every DataStore.save, and re-encoding the whole array each time
        // was wasted work on the hot path.
        if pendingUnlocks.count != unlocksBefore { saveAchievements() }
    }

    /// Lifestyle-side milestones. Surfaced when the user crosses
    /// thresholds in meal logging, lab tracking, recipe building,
    /// or daily check-ins. Kept as a separate entry point from
    /// `checkAchievements` so the call site (`DataStore.save`)
    /// doesn't have to plumb every count through one omnibus
    /// signature — each domain runs its own loop.
    func checkLifestyleAchievements(
        mealsLogged: Int,
        mealStreak: Int,
        labsLogged: Int,
        labPanelCount: Int,
        recipesCount: Int,
        checkInsLogged: Int
    ) {
        // No reset — the consumer drains via `acknowledgeLatestUnlock`.
        let unlocksBefore = pendingUnlocks.count
        unlock("first_meal", if: mealsLogged >= 1)
        unlock("fifty_meals", if: mealsLogged >= 50)
        unlock("five_hundred_meals", if: mealsLogged >= 500)

        unlock("meal_streak_7", if: mealStreak >= 7)
        unlock("meal_streak_30", if: mealStreak >= 30)
        unlock("meal_streak_90", if: mealStreak >= 90)

        unlock("first_lab", if: labsLogged >= 1)
        unlock("lab_panels_5", if: labPanelCount >= 5)
        unlock("lab_panels_10", if: labPanelCount >= 10)

        unlock("first_recipe", if: recipesCount >= 1)
        unlock("five_recipes", if: recipesCount >= 5)

        unlock("first_checkin", if: checkInsLogged >= 1)
        unlock("checkin_streak_14", if: checkInsLogged >= 14)
        unlock("checkin_streak_60", if: checkInsLogged >= 60)

        if pendingUnlocks.count != unlocksBefore { saveAchievements() }
    }

    /// Habit-side milestones. Surfaced as the user builds the daily-habit
    /// streaks the app now leads with. Kept as its own entry point — like
    /// `checkLifestyleAchievements` — so `DataStore.scheduleAchievementCheck`
    /// can pass habit-specific counts without one omnibus signature.
    func checkHabitAchievements(
        habitCount: Int,
        bestHabitStreak: Int,
        totalCompletions: Int,
        perfectDayToday: Bool
    ) {
        let unlocksBefore = pendingUnlocks.count
        unlock("first_habit", if: habitCount >= 1)

        unlock("habit_streak_7", if: bestHabitStreak >= 7)
        unlock("habit_streak_30", if: bestHabitStreak >= 30)
        unlock("habit_streak_90", if: bestHabitStreak >= 90)

        unlock("habit_days_50", if: totalCompletions >= 50)
        unlock("habit_days_250", if: totalCompletions >= 250)

        unlock("perfect_day", if: perfectDayToday)

        if pendingUnlocks.count != unlocksBefore { saveAchievements() }
    }

    /// Clears the celebration slot. Call after the toast has been
    /// presented so the next check can write a fresh unlock without
    /// the observer seeing a redundant change.
    func acknowledgeLatestUnlock() {
        if !pendingUnlocks.isEmpty { pendingUnlocks.removeFirst() }
    }

    var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    var totalCount: Int {
        achievements.count
    }

    // MARK: - Private

    private func unlock(_ id: String, if condition: Bool) {
        guard condition, let index = achievements.firstIndex(where: { $0.id == id && !$0.isUnlocked }) else { return }
        achievements[index].unlockedDate = Date()
        pendingUnlocks.append(achievements[index])
    }

    func resetForTesting() {
        achievements = Self.defaultAchievements
        pendingUnlocks = []
    }

    private func loadAchievements() {
        guard let data = defaults.data(forKey: persistenceKey) else {
            achievements = Self.defaultAchievements
            return
        }
        do {
            let saved = try JSONDecoder().decode([Achievement].self, from: data)
            achievements = mergeWithDefaults(saved)
        } catch {
            AppLog.achievements.error("Failed to decode achievements; reverting to defaults: \(error.localizedDescription, privacy: .public)")
            achievements = Self.defaultAchievements
        }
    }

    private func saveAchievements() {
        do {
            let data = try JSONEncoder().encode(achievements)
            defaults.set(data, forKey: persistenceKey)
        } catch {
            AppLog.achievements.error("Failed to encode achievements: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func mergeWithDefaults(_ saved: [Achievement]) -> [Achievement] {
        let savedMap = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        return Self.defaultAchievements.map { def in
            if let saved = savedMap[def.id] {
                return saved
            }
            return def
        }
    }

    static let defaultAchievements: [Achievement] = [
        Achievement(id: "first_dose", title: "First Step", description: "Log your first dose", icon: "1.circle.fill"),
        Achievement(id: "ten_doses", title: "Getting Started", description: "Log 10 doses", icon: "10.circle.fill"),
        Achievement(id: "fifty_doses", title: "Committed", description: "Log 50 doses", icon: "star.fill"),
        Achievement(id: "hundred_doses", title: "Centurion", description: "Log 100 doses", icon: "star.circle.fill"),
        Achievement(id: "five_hundred_doses", title: "Legendary", description: "Log 500 doses", icon: "crown.fill"),
        Achievement(id: "streak_3", title: "Warming Up", description: "3-day streak", icon: "flame"),
        Achievement(id: "streak_7", title: "On Fire", description: "7-day streak", icon: "flame.fill"),
        Achievement(id: "streak_14", title: "Unstoppable", description: "14-day streak", icon: "bolt.fill"),
        Achievement(id: "streak_30", title: "Iron Will", description: "30-day streak", icon: "shield.fill"),
        Achievement(id: "streak_90", title: "Master", description: "90-day streak", icon: "trophy.fill"),
        Achievement(id: "first_protocol", title: "Protocol Creator", description: "Create your first protocol", icon: "list.clipboard.fill"),
        Achievement(id: "three_protocols", title: "Multi-Tasker", description: "Run 3 protocols", icon: "square.stack.3d.up.fill"),
        Achievement(id: "week_logged", title: "Week Warrior", description: "Log doses for 7 days", icon: "calendar"),
        Achievement(id: "month_logged", title: "Monthly Master", description: "Log doses for 30 days", icon: "calendar.badge.checkmark"),

        // Lifestyle achievements — surface as users build the
        // companion-data side of their tracking habit.
        Achievement(id: "first_meal", title: "First Bite", description: "Log your first meal", icon: "fork.knife"),
        Achievement(id: "fifty_meals", title: "Fed", description: "Log 50 meals", icon: "fork.knife.circle"),
        Achievement(id: "five_hundred_meals", title: "Chef's Choice", description: "Log 500 meals", icon: "fork.knife.circle.fill"),

        Achievement(id: "meal_streak_7", title: "Mindful Eater", description: "7-day meal-logging streak", icon: "leaf.fill"),
        Achievement(id: "meal_streak_30", title: "Tracker", description: "30-day meal-logging streak", icon: "leaf.circle.fill"),
        Achievement(id: "meal_streak_90", title: "Habit Locked", description: "90-day meal-logging streak", icon: "checkmark.seal.fill"),

        Achievement(id: "first_lab", title: "Data Driven", description: "Log your first lab value", icon: "testtube.2"),
        Achievement(id: "lab_panels_5", title: "Biomarker Hunter", description: "Track 5 different lab panels", icon: "chart.line.uptrend.xyaxis"),
        Achievement(id: "lab_panels_10", title: "Optimizer", description: "Track 10 different lab panels", icon: "chart.bar.xaxis.ascending"),

        Achievement(id: "first_recipe", title: "Recipe Builder", description: "Save your first recipe", icon: "list.bullet.rectangle"),
        Achievement(id: "five_recipes", title: "Recipe Library", description: "Save 5 recipes", icon: "list.bullet.rectangle.fill"),

        Achievement(id: "first_checkin", title: "Tuning In", description: "Complete your first daily check-in", icon: "heart.text.square"),
        Achievement(id: "checkin_streak_14", title: "Self-Aware", description: "14 daily check-ins logged", icon: "heart.text.square.fill"),
        Achievement(id: "checkin_streak_60", title: "Insight Engine", description: "60 daily check-ins logged", icon: "sparkles"),

        // Habit achievements — the daily-consistency engine the app now
        // leads with. Streaks reward sticking with a habit; "days" reward
        // breadth of completion; Perfect Day rewards clearing everything
        // due in a single day.
        Achievement(id: "first_habit", title: "First Habit", description: "Create your first habit", icon: "checkmark.seal.fill"),
        Achievement(id: "habit_streak_7", title: "Habit Spark", description: "7-day habit streak", icon: "flame.fill"),
        Achievement(id: "habit_streak_30", title: "Habit Forged", description: "30-day habit streak", icon: "bolt.fill"),
        Achievement(id: "habit_streak_90", title: "Habit Mastery", description: "90-day habit streak", icon: "trophy.fill"),
        Achievement(id: "habit_days_50", title: "Fifty Strong", description: "Complete 50 habits", icon: "checkmark.circle.fill"),
        Achievement(id: "habit_days_250", title: "Relentless", description: "Complete 250 habits", icon: "star.circle.fill"),
        Achievement(id: "perfect_day", title: "Perfect Day", description: "Complete every habit due in a day", icon: "sparkles"),
    ]
}
