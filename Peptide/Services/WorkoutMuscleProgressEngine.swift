import Foundation

/// How far a live workout has come, per muscle: the working sets done
/// against the working sets planned, grouped the way the session builder
/// names muscles. Drives the muscle progress card on the workout screen.
enum WorkoutMuscleProgressEngine {

    struct Row: Identifiable, Equatable, Sendable {
        let target: SessionBuilderEngine.Target
        let done: Int
        let planned: Int
        var id: SessionBuilderEngine.Target { target }
        var isComplete: Bool { planned > 0 && done >= planned }
    }

    struct Progress: Equatable, Sendable {
        /// In the order the workout first reaches each muscle.
        let rows: [Row]
        let doneSets: Int
        let plannedSets: Int

        var fraction: Double {
            plannedSets > 0 ? min(Double(doneSets) / Double(plannedSets), 1) : 0
        }

        /// The most sets any one muscle has had so far; rows scale their
        /// colour against it, as the map scales against its brightest head.
        var maxDone: Int { rows.map(\.done).max() ?? 0 }
    }

    /// Every exercise counts its working sets toward each muscle it mainly
    /// trains (`SessionBuilderEngine.targets(of:)`). Warm-ups never count.
    /// Exercises the lookup can't resolve still count toward the totals.
    static func progress(
        of session: WorkoutSession,
        exercise lookup: (String) -> Exercise?
    ) -> Progress {
        var order: [SessionBuilderEngine.Target] = []
        var done: [SessionBuilderEngine.Target: Int] = [:]
        var planned: [SessionBuilderEngine.Target: Int] = [:]
        var doneSets = 0
        var plannedSets = 0

        for entry in session.exercises.sorted(by: { $0.index < $1.index }) {
            let working = entry.sets.filter { !$0.isWarmup }
            let completed = working.filter(\.completed).count
            doneSets += completed
            plannedSets += working.count
            guard let exercise = lookup(entry.exerciseID) else { continue }
            let targets = SessionBuilderEngine.targets(of: exercise)
            for target in SessionBuilderEngine.Target.allCases where targets.contains(target) {
                if planned[target] == nil { order.append(target) }
                planned[target, default: 0] += working.count
                done[target, default: 0] += completed
            }
        }

        let rows = order.compactMap { target -> Row? in
            let plannedCount = planned[target] ?? 0
            guard plannedCount > 0 else { return nil }
            return Row(target: target, done: done[target] ?? 0, planned: plannedCount)
        }
        return Progress(rows: rows, doneSets: doneSets, plannedSets: plannedSets)
    }

    /// The map's per-head load for this workout alone, on the same scale
    /// as the Train overview's heatmap.
    @MainActor
    static func frequencies(of session: WorkoutSession, library: ExerciseLibrary) -> [AnatomicalMuscle: Double] {
        WeeklyMuscleHeatmap.frequencies(from: [session], library: library, days: 1, now: session.startedAt)
    }
}
