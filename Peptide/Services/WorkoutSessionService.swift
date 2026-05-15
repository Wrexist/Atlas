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
    /// Discards any pre-existing in-progress session — the user
    /// should be prompted before this is called (the UI will show a
    /// "Discard current workout?" alert).
    @discardableResult
    func startWorkout(routine: Routine? = nil) -> WorkoutSession {
        if let existing = activeSession {
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
    func finishWorkout(perceivedEffort: Int? = nil, note: String? = nil) -> WorkoutSession? {
        guard var session = activeSession else { return nil }
        session.finishedAt = Date()
        session.perceivedEffort = perceivedEffort
        session.note = note
        SwiftDataRepository.shared.upsertWorkoutSession(session)
        PRDetectionEngine.shared.ingest(session: session)
        activeSession = nil
        AppLog.training.info("Workout finished (id: \(session.id, privacy: .public), sets: \(session.completedSetCount, privacy: .public))")
        return session
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

    // MARK: - Internals

    private func persist(_ session: WorkoutSession) {
        activeSession = session
        SwiftDataRepository.shared.upsertWorkoutSession(session)
    }
}
