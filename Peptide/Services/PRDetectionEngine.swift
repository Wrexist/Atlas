import Foundation
import OSLog

/// Maintains the per-exercise personal-record table. Ingests each
/// finished `WorkoutSession`, computes best estimated 1RM, best
/// absolute weight, and best session-volume per exercise touched in
/// the session, and upserts the result into the SwiftData store via
/// `SwiftDataRepository`.
///
/// Returns the list of *new* PRs detected so the finish screen can
/// celebrate them with confetti + haptic without scanning the full
/// history.
@MainActor @Observable
final class PRDetectionEngine {
    static let shared = PRDetectionEngine()
    private init() {}

    struct DetectedPR: Hashable, Sendable {
        let exerciseID: String
        let kind: Kind
        let value: Double
        enum Kind: String, Hashable, Sendable {
            case estimatedOneRepMax
            case absoluteWeight
            case sessionVolume
            /// Best rep count for bodyweight (weight-0) exercises.
            /// Push-ups / pull-ups / dips fall here so the user gets
            /// a celebration without needing to log a phantom weight
            /// (audit Train H3).
            case bodyweightReps
        }
    }

    /// Rebuilds the PR rows for the given exercises from the full stored
    /// history. Called after a session is deleted so a record set by the
    /// now-gone workout doesn't survive it as an unfalsifiable badge —
    /// the record either rolls back to the best remaining session or, if
    /// no other session touched the exercise, disappears entirely.
    func recompute(exerciseIDs: Set<String>) {
        guard !exerciseIDs.isEmpty else { return }
        let repo = SwiftDataRepository.shared
        // Bests are rebuilt in memory and each surviving record written
        // once at the end — upserting per session committed the store
        // once per exercise per workout across the whole history.
        var records: [String: PersonalRecord] = [:]
        // Full history, oldest first, so "achieved at" lands on the
        // earliest session that set each surviving best.
        for session in repo.loadAllWorkoutSessions() where session.finishedAt != nil {
            guard session.exercises.contains(where: { exerciseIDs.contains($0.exerciseID) })
            else { continue }
            apply(session: session, restrictTo: exerciseIDs, records: &records)
        }
        for exerciseID in exerciseIDs {
            if let record = records[exerciseID] {
                repo.upsertPersonalRecord(record)
            } else {
                repo.deletePersonalRecord(exerciseID: exerciseID)
            }
        }
    }

    /// Walks a finished session's exercises, compares each one's
    /// stats against the cached `PersonalRecord`, and upserts any
    /// new maxes. Returns the deltas so the UI can celebrate. The
    /// first value ever logged for a kind is stored as a silent
    /// baseline: a PR has to beat something.
    @discardableResult
    func ingest(session: WorkoutSession) -> [DetectedPR] {
        let stored = Self.loadRecordsByExercise()
        var records = stored
        let detected = apply(session: session, restrictTo: nil, records: &records)
        for (exerciseID, record) in records where stored[exerciseID] != record {
            SwiftDataRepository.shared.upsertPersonalRecord(record)
        }
        return detected
    }

    private static func loadRecordsByExercise() -> [String: PersonalRecord] {
        Dictionary(
            SwiftDataRepository.shared.loadPersonalRecords().map { ($0.exerciseID, $0) },
            uniquingKeysWith: { $0.merged(with: $1) }
        )
    }

    /// Compares the session against `records` and writes any new maxes
    /// back into it. Persisting is left to the caller.
    @discardableResult
    private func apply(
        session: WorkoutSession,
        restrictTo: Set<String>?,
        records: inout [String: PersonalRecord]
    ) -> [DetectedPR] {
        guard session.finishedAt != nil else { return [] }
        var detected: [DetectedPR] = []

        // Group session exercises by exerciseID — a routine could
        // (rarely) include the same lift twice; we want one PR row
        // per exercise, summing the volume across re-occurrences.
        let grouped = Dictionary(grouping: session.exercises, by: \.exerciseID)

        for (exerciseID, entries) in grouped {
            if let restrictTo, !restrictTo.contains(exerciseID) { continue }
            let allSets = entries.flatMap(\.sets).filter {
                $0.completed && !$0.isWarmup && ($0.measurement == nil
                    || $0.measurement?.kind == .repetitions || $0.measurement?.kind == .bodyweight)
            }
            guard !allSets.isEmpty else { continue }

            let bestE1RM = allSets.compactMap(\.estimatedOneRepMaxKg).max() ?? 0
            let bestAbs = allSets.map(\.weightKg).max() ?? 0
            let sessionVolume = allSets.reduce(0) { $0 + $1.volumeKg }
            // Bodyweight track: best reps across all weight-0 sets.
            // This is what "I did 35 push-ups today" looks like —
            // weight 0, reps high. Reported separately from the
            // weighted track so a bodyweight-only user still gets
            // celebration moments.
            let bodyweightSets = allSets.filter { $0.weightKg == 0 }
            let bestBodyweightReps = bodyweightSets.map(\.reps).max() ?? 0
            let finishedAt = session.finishedAt ?? Date()

            var record = records[exerciseID]
                ?? PersonalRecord(exerciseID: exerciseID)
            var dirty = false

            if bestE1RM > (record.bestEstimatedOneRepMaxKg ?? 0) {
                if record.bestEstimatedOneRepMaxKg != nil {
                    detected.append(.init(exerciseID: exerciseID,
                                          kind: .estimatedOneRepMax,
                                          value: bestE1RM))
                }
                record.bestEstimatedOneRepMaxKg = bestE1RM
                record.bestEstimatedOneRepMaxAt = finishedAt
                dirty = true
            }
            if bestAbs > (record.bestAbsoluteWeightKg ?? 0) {
                if record.bestAbsoluteWeightKg != nil {
                    detected.append(.init(exerciseID: exerciseID,
                                          kind: .absoluteWeight,
                                          value: bestAbs))
                }
                record.bestAbsoluteWeightKg = bestAbs
                record.bestAbsoluteWeightAt = finishedAt
                dirty = true
            }
            if sessionVolume > (record.bestSessionVolumeKg ?? 0) {
                if record.bestSessionVolumeKg != nil {
                    detected.append(.init(exerciseID: exerciseID,
                                          kind: .sessionVolume,
                                          value: sessionVolume))
                }
                record.bestSessionVolumeKg = sessionVolume
                record.bestSessionVolumeAt = finishedAt
                dirty = true
            }
            if bestBodyweightReps > (record.bestRepsBodyweight ?? 0) {
                if record.bestRepsBodyweight != nil {
                    detected.append(.init(exerciseID: exerciseID,
                                          kind: .bodyweightReps,
                                          value: Double(bestBodyweightReps)))
                }
                record.bestRepsBodyweight = bestBodyweightReps
                record.bestRepsBodyweightAt = finishedAt
                dirty = true
            }

            if dirty {
                records[exerciseID] = record
            }
        }

        if !detected.isEmpty {
            AppLog.training.info("Detected \(detected.count, privacy: .public) PR(s)")
        }
        return detected
    }
}
