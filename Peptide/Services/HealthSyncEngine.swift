import Foundation

/// The "Sync workouts, weight and water" setting. Device-local, like the
/// daily reminders: Health permission is granted per device, so a
/// CloudKit-synced flag would switch sync on for an iPad that never
/// asked.
enum HealthSyncSettings {
    static let enabledKey = "atlas.healthSync.trainingAndBody.v1"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }
}

/// Decides which weigh-ins from Apple Health (smart scales, other apps)
/// Atlas takes in.
enum HealthSyncEngine {
    /// How far back each foreground pass looks for outside weigh-ins.
    static let importWindowDays = 30

    /// One entry per day Atlas has no weight for, using the latest
    /// reading of that day. Days the user already logged in Atlas are
    /// left alone, so their own number always wins and repeated passes
    /// add nothing new. Readings the user deleted (`dismissed`, by
    /// sample id) never come back.
    static func weightsToImport(
        _ external: [WeightEntry],
        existing: [WeightEntry],
        dismissed: Set<UUID> = [],
        calendar: Calendar = .current
    ) -> [WeightEntry] {
        let loggedDays = Set(existing.map { calendar.startOfDay(for: $0.date) })
        var latestByDay: [Date: WeightEntry] = [:]
        for entry in external where !dismissed.contains(entry.id) {
            let day = calendar.startOfDay(for: entry.date)
            guard !loggedDays.contains(day) else { continue }
            if let current = latestByDay[day], current.date >= entry.date { continue }
            latestByDay[day] = entry
        }
        return latestByDay.values.sorted { $0.date < $1.date }
    }
}
