import Foundation

/// How recovered each muscle head is, from the working sets the user
/// actually logged. Feeds the session builder's body map and its
/// "what should rest" calls.
///
/// Every working set adds fatigue to the heads it trains (primary at
/// its head weight, secondary at half, hard sets ×1.2). Each set's
/// fatigue fades linearly to zero over the head's recovery window, so
/// a big muscle hit hard on Tuesday is still flagged on Thursday while
/// biceps are ready again.
enum MuscleRecoveryEngine {

    enum Status: Equatable, Sendable {
        case ready, recovering, rest
    }

    struct Recovery: Equatable, Sendable {
        /// 0 = fully fatigued, 1 = fully recovered.
        let fraction: Double
        let lastTrained: Date?

        var status: Status {
            if fraction >= 0.9 { return .ready }
            if fraction >= 0.7 { return .recovering }
            return .rest
        }
    }

    /// Hard sets on one head that count as fully fatigued — roughly one
    /// complete session's worth for that muscle.
    static let fullFatigueSets = 8.0

    /// Recovery for every head; heads without recent work are 100 %.
    @MainActor
    static func recovery(
        from sessions: [WorkoutSession],
        library: ExerciseLibrary,
        readiness: ReadinessEngine.Level? = nil,
        now: Date = Date()
    ) -> [AnatomicalMuscle: Recovery] {
        var fatigue: [AnatomicalMuscle: Double] = [:]
        var lastTrained: [AnatomicalMuscle: Date] = [:]
        let scale = windowScale(for: readiness)

        for session in sessions {
            let trainedAt = session.finishedAt ?? session.startedAt
            let hoursAgo = now.timeIntervalSince(trainedAt) / 3600
            guard hoursAgo >= 0 else { continue }

            for entry in session.exercises {
                guard let exercise = library.lookup(id: entry.exerciseID) else { continue }
                let load = entry.completedWorkingSets.reduce(0) { $0 + effort(of: $1) }
                guard load > 0 else { continue }

                for (muscle, weight) in stimulus(for: exercise) {
                    if trainedAt > (lastTrained[muscle] ?? .distantPast) { lastTrained[muscle] = trainedAt }
                    let remaining = 1 - hoursAgo / (recoveryHours(for: muscle) * scale)
                    guard remaining > 0 else { continue }
                    fatigue[muscle, default: 0] += load * weight * remaining
                }
            }
        }

        return Dictionary(uniqueKeysWithValues: AnatomicalMuscle.allCases.map { muscle in
            let fraction = 1 - min(1, (fatigue[muscle] ?? 0) / fullFatigueSets)
            return (muscle, Recovery(fraction: fraction, lastTrained: lastTrained[muscle]))
        })
    }

    /// Hours until a head has fully recovered from a hard session.
    static func recoveryHours(for muscle: AnatomicalMuscle) -> Double {
        switch muscle {
        case .pecSternal, .pecClavicular, .lats, .lowerBack, .glutes, .adductors,
             .quadRectus, .quadLateralis, .quadMedialis, .hamstringLateral, .hamstringMedial:
            return 72
        case .deltAnterior, .trapsUpper, .trapsLower, .rhomboids, .tricepsLong,
             .tricepsLateral, .gluteMedius:
            return 54
        case .biceps, .deltLateralFront, .deltLateralBack, .deltPosterior, .forearmFront,
             .forearmBack, .abdominals, .obliques, .gastrocnemius, .soleus, .tibialis, .neck:
            return 42
        }
    }

    /// A poor HRV / sleep day stretches recovery; a strong one shortens it.
    static func windowScale(for readiness: ReadinessEngine.Level?) -> Double {
        switch readiness {
        case .low: return 1.25
        case .ready: return 0.9
        case .normal, nil: return 1
        }
    }

    private static func effort(of set: SetEntry) -> Double {
        (set.rpe ?? 0) >= 9 ? 1.2 : 1
    }

    private static func stimulus(for exercise: Exercise) -> [AnatomicalMuscle: Double] {
        let heads = WeeklyMuscleHeatmap.stimulusHeads(for: exercise)
        return heads.primary.merging(heads.secondary.mapValues { $0 * 0.5 }) { primary, _ in primary }
    }
}

/// Weekly hard-set targets per muscle head for hypertrophy, scaled by
/// training experience. Done volume comes from `WeeklyMuscleHeatmap`
/// (secondary sets already count half there).
enum MuscleVolumeTargets {

    static func weeklySets(for experience: Exercise.Level) -> ClosedRange<Double> {
        switch experience {
        case .beginner: return 10...12
        case .intermediate: return 12...16
        case .expert: return 16...20
        }
    }

    /// Sets past this in one session add little growth, only fatigue.
    static func sessionCap(for experience: Exercise.Level) -> Int {
        switch experience {
        case .beginner: return 6
        case .intermediate: return 8
        case .expert: return 10
        }
    }

    /// Sets still needed this week to reach the low end of the target.
    static func remainingSets(done: Double, experience: Exercise.Level) -> Double {
        max(0, weeklySets(for: experience).lowerBound - done)
    }
}
