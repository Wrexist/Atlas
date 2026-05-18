import Foundation
import OSLog

/// Owns the user's single in-progress workout session. The invariant
/// enforced here: at most one `WorkoutSession` has `finishedAt == nil`
/// at any time. Mutations go through this service so the SwiftData
/// row, the in-memory observable state, and (in a later commit) the
/// Live Activity and Watch stay consistent.
@MainActor @Observable
final class WorkoutSessionService {
    static let shared = WorkoutSessionService()

    /// The session the user is currently working on, or `nil` when no
    /// workout is in progress. Mutations flow through the helper
    /// methods below so external code doesn't reach in and break the
    /// "one active session at a time" invariant.
    private(set) var activeSession: WorkoutSession?

    private init() {
        // Re-hydrate any session that was active when the process was
        // suspended so the user picks up where they left off.
        activeSession = SwiftDataRepository.shared.loadActiveWorkoutSession()
    }

    // MARK: - Lifecycle

    /// Begin a new session, optionally seeded from a routine.
    ///
    /// Idempotent under rapid double-tap and concurrent UI surfaces:
    /// if a session was started within the last 2 seconds (typical
    /// SwiftUI re-render window), the existing one is returned
    /// instead of being replaced. The destructive "discard the old
    /// workout to start a new one" path is reserved for the explicit
    /// UI alert that confirms the action.
    @discardableResult
    func startWorkout(routine: Routine? = nil) -> WorkoutSession {
        if let existing = activeSession {
            if existing.startedAt.timeIntervalSinceNow > -2 {
                // Recently-started session — collapse the duplicate
                // start (deep link + tab tap, two finger taps on the
                // CTA, etc.) into the existing session instead of
                // discarding the user's data.
                return existing
            }
            SwiftDataRepository.shared.deleteWorkoutSession(id: existing.id)
        }
        let exercises: [WorkoutExerciseEntry] = routine?.exercises.enumerated().map { idx, slot in
            let initialSets = (0..<max(1, slot.targetSets)).map { setIdx in
                SetEntry(
                    index: setIdx + 1,
                    weightKg: 0,
                    reps: slot.targetReps,
                    rpe: slot.targetRPE
                )
            }
            return WorkoutExerciseEntry(
                exerciseID: slot.exerciseID,
                index: idx,
                sets: initialSets,
                restSeconds: slot.restSeconds
            )
        } ?? []

        let session = WorkoutSession(
            name: routine?.name,
            routineID: routine?.id,
            startedAt: Date(),
            exercises: exercises
        )
        activeSession = session
        SwiftDataRepository.shared.upsertWorkoutSession(session)
        AppLog.training.info("Workout started (id: \(session.id, privacy: .public))")
        return session
    }

    /// Mark the session complete. Returns the finished session for
    /// the finish-screen render path; the service drops its
    /// `activeSession` so the next `startWorkout` is unambiguous.
    @discardableResult
    /// Finish-result bundle so the WorkoutFinishView can render PR
    /// detections without re-calling PRDetectionEngine.ingest (which
    /// mutates the records on first call and returns [] on every
    /// subsequent call against the same session — audit Train H4:
    /// "PR celebrations never fire on the finish screen").
    struct FinishedWorkout {
        let session: WorkoutSession
        let detectedPRs: [PRDetectionEngine.DetectedPR]
    }

    func finishWorkout(perceivedEffort: Int? = nil, note: String? = nil) -> FinishedWorkout? {
        guard var session = activeSession else { return nil }
        session.finishedAt = Date()
        session.perceivedEffort = perceivedEffort
        session.note = note
        SwiftDataRepository.shared.upsertWorkoutSession(session)
        let detections = PRDetectionEngine.shared.ingest(session: session)
        activeSession = nil
        AppLog.training.info("Workout finished (id: \(session.id, privacy: .public), sets: \(session.completedSetCount, privacy: .public), PRs: \(detections.count, privacy: .public))")
        return FinishedWorkout(session: session, detectedPRs: detections)
    }

    /// Drop the in-progress session without recording it. Called when
    /// the user taps Discard on the finish-confirmation alert.
    func discardWorkout() {
        guard let session = activeSession else { return }
        SwiftDataRepository.shared.deleteWorkoutSession(id: session.id)
        activeSession = nil
        AppLog.training.info("Workout discarded (id: \(session.id, privacy: .public))")
    }

    // MARK: - Mutations

    func addExercise(_ exercise: Exercise) {
        guard var session = activeSession else { return }
        let nextIndex = session.exercises.count
        let entry = WorkoutExerciseEntry(
            exerciseID: exercise.id,
            index: nextIndex,
            sets: [SetEntry(index: 1, weightKg: 0, reps: 8)]
        )
        session.exercises.append(entry)
        persist(session)
    }

    func removeExercise(id: UUID) {
        guard var session = activeSession else { return }
        session.exercises.removeAll { $0.id == id }
        // Re-index so the display order stays contiguous.
        for i in session.exercises.indices {
            session.exercises[i].index = i
        }
        persist(session)
    }

    func addSet(toExerciseID exerciseEntryID: UUID) {
        guard var session = activeSession,
              let idx = session.exercises.firstIndex(where: { $0.id == exerciseEntryID })
        else { return }
        let prev = session.exercises[idx].sets.last
        let nextIndex = (session.exercises[idx].sets.last?.index ?? 0) + 1
        // Pre-fill from previous set so two-tap logging works.
        let next = SetEntry(
            index: nextIndex,
            weightKg: prev?.weightKg ?? 0,
            reps: prev?.reps ?? 8,
            rpe: prev?.rpe
        )
        session.exercises[idx].sets.append(next)
        persist(session)
    }

    func removeSet(setID: UUID, fromExerciseEntryID entryID: UUID) {
        guard var session = activeSession,
              let exIdx = session.exercises.firstIndex(where: { $0.id == entryID })
        else { return }
        session.exercises[exIdx].sets.removeAll { $0.id == setID }
        // Re-index remaining sets so the display reads 1, 2, 3, …
        for i in session.exercises[exIdx].sets.indices {
            session.exercises[exIdx].sets[i].index = i + 1
        }
        persist(session)
    }

    /// Update a single set in place. Used by the inline weight / rep
    /// pickers and by the "complete set" toggle.
    func updateSet(_ set: SetEntry, inExerciseEntryID entryID: UUID) {
        guard var session = activeSession,
              let exIdx = session.exercises.firstIndex(where: { $0.id == entryID }),
              let setIdx = session.exercises[exIdx].sets.firstIndex(where: { $0.id == set.id })
        else { return }
        var updated = set
        // Stamp completedAt when transitioning to completed; clear on un-check.
        if set.completed && session.exercises[exIdx].sets[setIdx].completedAt == nil {
            updated.completedAt = Date()
        } else if !set.completed {
            updated.completedAt = nil
        }
        session.exercises[exIdx].sets[setIdx] = updated
        persist(session)
    }

    func renameWorkout(_ name: String) {
        guard var session = activeSession else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.name = trimmed.isEmpty ? nil : trimmed
        persist(session)
    }

    /// Returns the last completed set the user logged for the given
    /// exercise in any prior workout session. Wires the "previous"
    /// cue on each SetEditorRow so the user sees "Last: 60 kg × 8"
    /// before they tap to log the next set (audit Train C1). Returns
    /// nil when the user hasn't ever logged this exercise.
    func lastCompletedSet(forExerciseID id: String) -> SetEntry? {
        let sessions = SwiftDataRepository.shared.loadWorkoutSessions()
        // Walk newest-first, skip the in-flight session.
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            if session.id == activeSession?.id { continue }
            guard let exerciseEntry = session.exercises.first(where: { $0.exerciseID == id })
            else { continue }
            if let lastCompleted = exerciseEntry.sets.last(where: { $0.completed }) {
                return lastCompleted
            }
        }
        return nil
    }

    // MARK: - Internals

    private func persist(_ session: WorkoutSession) {
        activeSession = session
        SwiftDataRepository.shared.upsertWorkoutSession(session)
    }
}
