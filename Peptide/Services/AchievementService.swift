import Foundation

struct Achievement: Identifiable, Codable {
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
    private(set) var latestUnlock: Achievement?

    private let persistenceKey = "achievements"
    private let defaults = UserDefaults.standard

    private init() {
        loadAchievements()
    }

    func checkAchievements(totalDoses: Int, currentStreak: Int, bestStreak: Int, protocolCount: Int, daysLogged: Int) {
        latestUnlock = nil

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

        saveAchievements()
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
        latestUnlock = achievements[index]
    }

    private func loadAchievements() {
        if let data = defaults.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([Achievement].self, from: data) {
            achievements = mergeWithDefaults(saved)
        } else {
            achievements = Self.defaultAchievements
        }
    }

    private func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            defaults.set(data, forKey: persistenceKey)
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
    ]
}
