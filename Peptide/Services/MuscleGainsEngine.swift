import Foundation

/// Long-horizon companion to `WeeklyMuscleHeatmap` — aggregates the
/// user's whole training history into the two per-muscle maps that
/// drive the Train tab's "Muscle gains" figure:
///
/// - **Totals** — accumulated working-set stimulus per anatomical head
///   over all logged sessions, so the figure shows where the user has
///   built the most volume overall.
/// - **Regularity** — the fraction of recent weeks each head received
///   any stimulus, so the figure shows what the user trains
///   consistently versus what they only hit now and then.
///
/// Pure computation — no I/O beyond what the caller provides, same as
/// the weekly aggregation. Both maps use the head weights from
/// `WeeklyMuscleHeatmap.stimulusHeads` so the gains figure lights the
/// exact heads the weekly heatmap does.
enum MuscleGainsEngine {

    /// Accumulated stimulus per anatomical head across *all* sessions.
    /// Primary heads count one point per working set × weight, secondary
    /// heads half — identical weighting to the weekly heatmap, just
    /// without a time window.
    @MainActor
    static func totalFrequencies(
        from sessions: [WorkoutSession],
        library: ExerciseLibrary
    ) -> [AnatomicalMuscle: Double] {
        var counts: [AnatomicalMuscle: Double] = [:]
        for session in sessions {
            for entry in session.exercises {
                guard let exercise = library.lookup(id: entry.exerciseID) else { continue }
                let workingSets = entry.sets.filter { $0.completed && !$0.isWarmup }
                guard !workingSets.isEmpty else { continue }
                let setCount = Double(workingSets.count)

                let heads = WeeklyMuscleHeatmap.stimulusHeads(for: exercise)
                for (muscle, weight) in heads.primary {
                    counts[muscle, default: 0] += setCount * weight
                }
                for (muscle, weight) in heads.secondary where heads.primary[muscle] == nil {
                    counts[muscle, default: 0] += setCount * 0.5 * weight
                }
            }
        }
        return counts
    }

    /// How regularly each head gets trained: the fraction of the past
    /// `weeks` calendar weeks in which the head received meaningful
    /// stimulus (any working set from an exercise whose head weight
    /// clears 0.25). `1.0` means trained every single week; values map
    /// directly onto the muscle map's load ramp without re-normalising,
    /// so an every-week muscle reads hot even on a fresh-ish account.
    @MainActor
    static func weeklyRegularity(
        from sessions: [WorkoutSession],
        library: ExerciseLibrary,
        weeks: Int = 12,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AnatomicalMuscle: Double] {
        guard weeks > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let windowStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [:] }

        var weeksHit: [AnatomicalMuscle: Set<Date>] = [:]
        for session in sessions where session.startedAt >= windowStart {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start
            else { continue }
            for entry in session.exercises {
                guard let exercise = library.lookup(id: entry.exerciseID) else { continue }
                guard entry.sets.contains(where: { $0.completed && !$0.isWarmup }) else { continue }

                let heads = WeeklyMuscleHeatmap.stimulusHeads(for: exercise)
                let stimulated = heads.primary.filter { $0.value > 0.25 }.keys
                let assisted = heads.secondary.filter { $0.value > 0.25 }.keys
                for muscle in Set(stimulated).union(assisted) {
                    weeksHit[muscle, default: []].insert(week)
                }
            }
        }
        return weeksHit.mapValues { Double($0.count) / Double(weeks) }
    }
}
