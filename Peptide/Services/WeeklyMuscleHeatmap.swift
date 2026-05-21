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

                let primary = AnatomicalMuscle.regions(forRawMuscles: exercise.primaryMuscles)
                let secondary = AnatomicalMuscle.regions(forRawMuscles: exercise.secondaryMuscles)
                    .subtracting(primary)

                for muscle in primary {
                    counts[muscle, default: 0] += setCount
                }
                for muscle in secondary {
                    counts[muscle, default: 0] += setCount * 0.5
                }
            }
        }
        return counts
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
}
