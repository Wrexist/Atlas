import Foundation

/// Read-only exercise history using the same inclusion rules as completion.
enum ExerciseHistoryEngine {
    struct Visit: Identifiable, Sendable {
        var id: UUID { session.id }
        let session: WorkoutSession
        let sets: [SetEntry]
        var date: Date { session.startedAt }
        var name: String {
            let value = session.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? String(localized: "Workout") : value
        }
    }

    static func visits(exerciseID: String, sessions: [WorkoutSession],
                       catalog: [String: Exercise]) -> [Visit] {
        var seen = Set<UUID>()
        return sessions.filter { !$0.isActive && seen.insert($0.id).inserted }
            .compactMap { session in
                let summary = WorkoutRecapEngine.derive(session, catalog: catalog)
                let sets = summary.entries.filter { $0.exerciseID == exerciseID }.flatMap(\.sets)
                return sets.isEmpty ? nil : Visit(session: session, sets: sets)
            }
            .sorted {
                $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
            }
    }
}
