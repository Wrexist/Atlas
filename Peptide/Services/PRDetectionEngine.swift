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
        for exerciseID in exerciseIDs {
            repo.deletePersonalRecord(exerciseID: exerciseID)
        }
        // Records are loaded once and threaded through every session —
        // reloading them per session made this O(sessions × PRs).
        var records = Self.loadRecordsByExercise()
        // Full history, oldest first, so "achieved at" lands on the
        // earliest session that set each surviving best.
        for session in repo.loadAllWorkoutSessions() where session.finishedAt != nil {
            guard session.exercises.contains(where: { exerciseIDs.contains($0.exerciseID) })
            else { continue }
            apply(session: session, restrictTo: exerciseIDs, records: &records)
        }
    }

    /// Walks a finished session's exercises, compares each one's
    /// stats against the cached `PersonalRecord`, and upserts any
    /// new maxes. Returns the deltas so the UI can celebrate.
    @discardableResult
    func ingest(session: WorkoutSession, restrictTo: Set<String>? = nil) -> [DetectedPR] {
        var records = Self.loadRecordsByExercise()
        return apply(session: session, restrictTo: restrictTo, records: &records)
    }

    private static func loadRecordsByExercise() -> [String: PersonalRecord] {
        Dictionary(uniqueKeysWithValues:
            SwiftDataRepository.shared.loadPersonalRecords().map { ($0.exerciseID, $0) }
        )
    }

    /// Compares the session against `records`, upserting and writing
    /// back any new maxes so a caller ingesting several sessions sees
    /// the same state a fresh load would return.
    @discardableResult
    private func apply(
        session: WorkoutSession,
        restrictTo: Set<String>?,
        records: inout [String: PersonalRecord]
    ) -> [DetectedPR] {
        guard session.finishedAt != nil else { return [] }
        let repo = SwiftDataRepository.shared
        var detected: [DetectedPR] = []

        // Group session exercises by exerciseID — a routine could
        // (rarely) include the same lift twice; we want one PR row
        // per exercise, summing the volume across re-occurrences.
        let grouped = Dictionary(grouping: session.exercises, by: \.exerciseID)

        for (exerciseID, entries) in grouped {
            if let restrictTo, !restrictTo.contains(exerciseID) { continue }
            let allSets = entries.flatMap(\.sets).filter { $0.completed && !$0.isWarmup }
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
                record.bestEstimatedOneRepMaxKg = bestE1RM
                record.bestEstimatedOneRepMaxAt = finishedAt
                detected.append(.init(exerciseID: exerciseID,
                                      kind: .estimatedOneRepMax,
                                      value: bestE1RM))
                dirty = true
            }
            if bestAbs > (record.bestAbsoluteWeightKg ?? 0) {
                record.bestAbsoluteWeightKg = bestAbs
                record.bestAbsoluteWeightAt = finishedAt
                detected.append(.init(exerciseID: exerciseID,
                                      kind: .absoluteWeight,
                                      value: bestAbs))
                dirty = true
            }
            if sessionVolume > (record.bestSessionVolumeKg ?? 0) {
                record.bestSessionVolumeKg = sessionVolume
                record.bestSessionVolumeAt = finishedAt
                detected.append(.init(exerciseID: exerciseID,
                                      kind: .sessionVolume,
                                      value: sessionVolume))
                dirty = true
            }
            if bestBodyweightReps > (record.bestRepsBodyweight ?? 0) {
                record.bestRepsBodyweight = bestBodyweightReps
                record.bestRepsBodyweightAt = finishedAt
                detected.append(.init(exerciseID: exerciseID,
                                      kind: .bodyweightReps,
                                      value: Double(bestBodyweightReps)))
                dirty = true
            }

            if dirty {
                repo.upsertPersonalRecord(record)
                records[exerciseID] = record
            }
        }

        if !detected.isEmpty {
            AppLog.training.info("Detected \(detected.count, privacy: .public) PR(s)")
        }
        return detected
    }
}
