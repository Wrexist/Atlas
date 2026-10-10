import Foundation

/// The recap's sole projection. No asset loading, clock ticks or view state.
enum WorkoutRecapEngine {
    enum Duration: Equatable, Sendable {
        case tracked(TimeInterval), notTracked, unavailable
        var label: String {
            switch self {
            case .notTracked: return String(localized: "Not tracked")
            case .unavailable: return "—"
            case .tracked(let seconds):
                if seconds < 60 { return String(localized: "<1 min") }
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
                formatter.unitsStyle = .abbreviated
                return formatter.string(from: seconds) ?? "—"
            }
        }
    }
    enum Role: String, Sendable { case primary = "Primary", supporting = "Supporting" }
    struct Contribution: Identifiable, Sendable {
        var id: UUID { entryID }
        let entryID: UUID
        let name: String
        let role: Role
        let sets: [SetEntry]
    }
    struct Muscle: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let contributions: [Contribution]
        var role: Role { contributions.contains { $0.role == .primary } ? .primary : .supporting }
        var setCount: Int { Set(contributions.flatMap { $0.sets.map(\.id) }).count }
    }
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let exerciseID: String
        let name: String
        let sets: [SetEntry]
        let volumeKg: Double?
        let primary: [String]
        let supporting: [String]
    }
    struct Summary: Sendable {
        let session: WorkoutSession
        let duration: Duration
        let entries: [Entry]
        let muscles: [Muscle]
        let workingSetCount: Int
        let volumeKg: Double?
        let excludedVolumeSets: Int
        let missingMappings: Int
        let hasLegacyLoad: Bool
        var workingSetLabel: String {
            session.exercises.isEmpty ? String(localized: "Not logged") : workingSetCount.formatted()
        }
        /// Legacy manual logs have a durable finish but no structured sets.
        /// Keep counting those workouts without inventing their set totals.
        var qualifiesForWeek: Bool {
            session.finishedAt != nil && (workingSetCount > 0 || session.exercises.isEmpty)
        }
        var name: String {
            let name = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? String(localized: "Workout") : name
        }
    }

    static func derive(_ session: WorkoutSession, catalog: [String: Exercise]) -> Summary {
        var seenEntries = Set<UUID>()
        var seenSets = Set<UUID>()
        var entries: [Entry] = []
        var contributions: [String: [Contribution]] = [:]
        var excluded = 0
        var missing = 0
        var legacy = false
        for entry in session.exercises.sorted(by: { $0.index < $1.index }) {
            guard seenEntries.insert(entry.id).inserted else { continue }
            let sets = entry.sets.sorted { $0.index < $1.index }.filter {
                $0.completed && !$0.isWarmup && seenSets.insert($0.id).inserted
            }
            guard !sets.isEmpty else { continue }
            let exercise = catalog[entry.exerciseID]
            let primary = Array(Set(exercise?.primaryMuscles.map { $0.lowercased() } ?? [])).sorted()
            let supporting = Array(Set(exercise?.secondaryMuscles.map { $0.lowercased() } ?? [])
                .subtracting(primary)).sorted()
            let name = exercise?.name ?? entry.exerciseID.replacingOccurrences(of: "_", with: " ")
            let volumes = sets.compactMap { set -> Double? in
                // Older cardio/stretching records have no timed/distance schema;
                // retain the record but do not reinterpret reps as external work.
                if set.measurement == nil,
                   exercise?.category == .cardio || exercise?.category == .stretching { return nil }
                return set.externalVolumeKg
            }
            excluded += sets.count - volumes.count
            legacy = legacy || sets.contains { $0.weightKg > 0 && $0.measurement == nil }
            let volume = volumes.isEmpty ? nil : volumes.reduce(0, +)
            entries.append(Entry(id: entry.id, exerciseID: entry.exerciseID, name: name,
                                 sets: sets, volumeKg: volume, primary: primary, supporting: supporting))
            if primary.isEmpty && supporting.isEmpty { missing += 1 }
            for (names, role) in [(primary, Role.primary), (supporting, Role.supporting)] {
                for muscle in names {
                    contributions[muscle, default: []].append(
                        Contribution(entryID: entry.id, name: name, role: role, sets: sets))
                }
            }
        }
        let volumes = entries.compactMap(\.volumeKg)
        return Summary(session: session, duration: duration(of: session), entries: entries,
                       muscles: contributions.map { Muscle(name: $0.key, contributions: $0.value) }
                        .sorted { $0.name < $1.name },
                       workingSetCount: seenSets.count,
                       volumeKg: volumes.isEmpty ? nil : volumes.reduce(0, +),
                       excludedVolumeSets: excluded, missingMappings: missing, hasLegacyLoad: legacy)
    }

    static func duration(of session: WorkoutSession) -> Duration {
        if session.focus?.timing == .notTracked { return .notTracked }
        guard session.focus?.timing != .unavailable, let end = session.finishedAt else { return .unavailable }
        let paused = session.focus?.pausedSeconds ?? 0
        guard paused.isFinite, paused >= 0 else { return .unavailable }
        let seconds = end.timeIntervalSince(session.startedAt) - paused
        guard seconds.isFinite, seconds > 0 else { return .unavailable }
        return .tracked(seconds)
    }

    struct Day: Identifiable, Sendable {
        var id: Date { date }
        let date: Date
        let count: Int
    }
    struct Week: Sendable {
        let days: [Day]
        let count: Int
        let volumeKg: Double?
    }

    /// Current locale/calendar week. A qualifying workout is finished and has
    /// working sets or is a legacy manual log without structured exercise data.
    /// Start date matches Atlas history.
    static func week(sessions: [WorkoutSession], catalog: [String: Exercise],
                     now: Date = Date(), calendar: Calendar = .current) -> Week {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Week(days: [], count: 0, volumeKg: nil)
        }
        var seen = Set<UUID>()
        let included = sessions.filter {
            guard let end = $0.finishedAt else { return false }
            return end <= now && $0.startedAt >= interval.start && $0.startedAt < interval.end
                && seen.insert($0.id).inserted
        }.map { derive($0, catalog: catalog) }.filter(\.qualifiesForWeek)
        let days = (0..<7).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return Day(date: date, count: included.filter { calendar.isDate($0.session.startedAt, inSameDayAs: date) }.count)
        }
        let volumes = included.compactMap(\.volumeKg)
        return Week(days: days, count: included.count, volumeKg: volumes.isEmpty ? nil : volumes.reduce(0, +))
    }
}
