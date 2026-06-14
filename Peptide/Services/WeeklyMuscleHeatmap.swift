import Foundation

/// Aggregates a window of recent `WorkoutSession`s into a per-muscle
/// frequency map that drives the Train tab's "Denna vecka" heatmap.
///
/// Every working set in the window contributes one frequency point to
/// each anatomical region the exercise targets. Primary muscles count
/// for one full point; secondary muscles count for half (matching the
/// "primary lights up bright, secondary tints softly" mental model on
/// the muscle map).
///
/// Pure computation — no I/O, no Date.now in the hot path beyond what
/// the caller passes in. Pulled out of the view so the same aggregation
/// can drive Insights charts, weekly summary copy, and the watch
/// complication without re-implementing the math.
enum WeeklyMuscleHeatmap {

    /// Frequency map per anatomical region for sessions whose
    /// `startedAt` falls within the past `days` days from `now`.
    /// Returns an empty dictionary when no sessions qualify.
    ///
    /// - Parameters:
    ///   - sessions: Source workout history. Order doesn't matter.
    ///   - library: Resolves `exerciseID` strings to `Exercise`
    ///     records so the muscle list can be looked up.
    ///   - days: Window size; defaults to 7 (the visible week).
    ///   - now: Reference clock; defaults to `Date()`.
    @MainActor
    static func frequencies(
        from sessions: [WorkoutSession],
        library: ExerciseLibrary,
        days: Int = 7,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AnatomicalMuscle: Double] {
        // Calendar-day window so DST flips don't push the boundary an
        // hour off, and so a workout at 23:50 doesn't fall out of the
        // window when re-rendered 10 minutes later (audit Train M6).
        // Anchored at startOfDay so the window is a clean N calendar
        // days ending today, not a rolling time-of-day cut.
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        var counts: [AnatomicalMuscle: Double] = [:]

        for session in sessions where session.startedAt >= cutoff {
            for entry in session.exercises {
                guard let exercise = library.lookup(id: entry.exerciseID) else {
                    // Silent skip used to hide deleted-custom-exercise
                    // referrals from the heatmap entirely — a user
                    // training on a since-deleted lift saw an empty
                    // map. Log so debug builds catch the data drift
                    // (audit Train T3).
                    AppLog.training.warning(
                        "Heatmap: exercise lookup miss for id \(entry.exerciseID, privacy: .public)"
                    )
                    continue
                }
                let workingSets = entry.sets.filter { $0.completed && !$0.isWarmup }
                guard !workingSets.isEmpty else { continue }
                let setCount = Double(workingSets.count)

                // Primary heads count full × their weight; secondary heads
                // count half, and primary wins when a head appears in both
                // lists.
                let heads = stimulusHeads(for: exercise)
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

    /// Resolves an exercise's raw muscle strings to weighted anatomical
    /// heads, biased by the exercise name (an incline press favours the
    /// clavicular pec, a pushdown the lateral triceps, a seated calf
    /// raise the soleus…). Shared by the weekly heatmap and the
    /// long-term gains aggregation so both light the same heads.
    static func stimulusHeads(
        for exercise: Exercise
    ) -> (primary: [AnatomicalMuscle: Double], secondary: [AnatomicalMuscle: Double]) {
        var primary: [AnatomicalMuscle: Double] = [:]
        for raw in exercise.primaryMuscles {
            for (muscle, weight) in AnatomicalMuscle.headWeights(
                forRawMuscle: raw, exerciseName: exercise.name
            ) {
                primary[muscle] = max(primary[muscle] ?? 0, weight)
            }
        }
        var secondary: [AnatomicalMuscle: Double] = [:]
        for raw in exercise.secondaryMuscles {
            for (muscle, weight) in AnatomicalMuscle.headWeights(
                forRawMuscle: raw, exerciseName: exercise.name
            ) {
                secondary[muscle] = max(secondary[muscle] ?? 0, weight)
            }
        }
        return (primary, secondary)
    }

    /// Convenience: list the top N muscles by frequency for the
    /// "most trained" callout under the heatmap. Returns muscles
    /// in descending order. Stable tie-break by the muscle's raw
    /// value so the order doesn't jitter between renders.
    static func topMuscles(
        from frequencies: [AnatomicalMuscle: Double],
        limit: Int = 3
    ) -> [(muscle: AnatomicalMuscle, count: Double)] {
        frequencies
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.rawValue < rhs.key.rawValue
            }
            .prefix(limit)
            .map { (muscle: $0.key, count: $0.value) }
    }

    /// The exercises the user actually logged that worked a given muscle
    /// head over the past `days`, newest first — drives the tap-to-inspect
    /// sheet on the muscle map. A movement counts when its name-weighted
    /// heads put any real stimulus on the tapped head, so tapping the side
    /// delt surfaces lateral raises rather than every shoulder press.
    @MainActor
    static func history(
        for muscle: AnatomicalMuscle,
        from sessions: [WorkoutSession],
        library: ExerciseLibrary,
        days: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MuscleExerciseHistory] {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        var byExercise: [String: MuscleExerciseHistory] = [:]

        for session in sessions where session.startedAt >= cutoff {
            for entry in session.exercises {
                guard let exercise = library.lookup(id: entry.exerciseID) else { continue }
                let touchesMuscle = (exercise.primaryMuscles + exercise.secondaryMuscles).contains { raw in
                    (AnatomicalMuscle.headWeights(forRawMuscle: raw, exerciseName: exercise.name)[muscle] ?? 0) > 0.15
                }
                guard touchesMuscle else { continue }
                let workingSets = entry.sets.filter { $0.completed && !$0.isWarmup }.count
                guard workingSets > 0 else { continue }

                if let existing = byExercise[entry.exerciseID] {
                    byExercise[entry.exerciseID] = MuscleExerciseHistory(
                        id: entry.exerciseID,
                        name: exercise.name,
                        sets: existing.sets + workingSets,
                        lastPerformed: max(existing.lastPerformed, session.startedAt)
                    )
                } else {
                    byExercise[entry.exerciseID] = MuscleExerciseHistory(
                        id: entry.exerciseID,
                        name: exercise.name,
                        sets: workingSets,
                        lastPerformed: session.startedAt
                    )
                }
            }
        }
        return byExercise.values.sorted { $0.lastPerformed > $1.lastPerformed }
    }
}

/// One exercise the user has logged for a muscle, aggregated for the
/// tap-to-inspect sheet on the muscle map.
struct MuscleExerciseHistory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sets: Int
    let lastPerformed: Date
}
