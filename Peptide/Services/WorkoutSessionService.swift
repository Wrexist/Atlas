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
    private(set) var lastFinishError: String?
    private var pendingFinish: WorkoutSession?

    /// How recently a session must have started for a second `startWorkout`
    /// to be treated as a duplicate tap rather than a fresh workout. Roughly
    /// the SwiftUI re-render window.
    static let duplicateStartWindow: TimeInterval = 2

    private init() {
        // Re-hydrate any session that was active when the process was
        // suspended so the user picks up where they left off.
        activeSession = SwiftDataRepository.shared.loadActiveWorkoutSession()
        // An activity outlives the process, so a relaunch can inherit one
        // whose workout is long gone — or lose one whose workout isn't.
        reconcileRest()
        WorkoutLiveActivityService.shared.reconcile(active: activeSession)
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
    ///
    /// `now` is the start instant, injectable so the duplicate window can
    /// be tested without waiting it out.
    @discardableResult
    func startWorkout(routine: Routine? = nil, now: Date = Date()) -> WorkoutSession {
        if let existing = activeSession {
            if existing.startedAt.timeIntervalSince(now) > -Self.duplicateStartWindow {
                // Recently-started session — collapse the duplicate
                // start (deep link + tab tap, two finger taps on the
                // CTA, etc.) into the existing session instead of
                // discarding the user's data.
                return existing
            }
            NotificationService.cancelOneShot(id: restNotificationID(for: existing.id))
            SwiftDataRepository.shared.deleteWorkoutSession(id: existing.id)
        }
        // Cleared before seeding so the seed — and every "previous" hint for
        // the rest of this workout — reads history as it stands right now.
        cancelFinishAttempt()
        invalidatePreviousSetCache()
        // Seed from the routine before the session exists, so the weight
        // lookup below still sees the *previous* workout as the newest one.
        let exercises: [WorkoutExerciseEntry] = routine.map { routine in
            RoutineSeedEngine.sessionExercises(for: routine) { exerciseID in
                lastCompletedSet(forExerciseID: exerciseID)
            }
        } ?? []

        let session = WorkoutSession(
            name: routine?.name,
            routineID: routine?.id,
            startedAt: now,
            exercises: exercises,
            focus: WorkoutFocusState(selectedEntryID: exercises.first?.id)
        )
        activeSession = session
        SwiftDataRepository.shared.upsertWorkoutSession(session)
        WorkoutLiveActivityService.shared.start(session)
        DataStore.current?.refreshTrainingGlanceables()
        AppLog.training.info("Workout started (id: \(session.id, privacy: .public))")
        return session
    }

    /// Finish-result bundle so the WorkoutFinishView can render PR
    /// detections without re-calling PRDetectionEngine.ingest (which
    /// mutates the records on first call and returns [] on every
    /// subsequent call against the same session — audit Train H4:
    /// "PR celebrations never fire on the finish screen").
    struct FinishedWorkout {
        let session: WorkoutSession
        let detectedPRs: [PRDetectionEngine.DetectedPR]
    }

    /// Mark the session complete. Returns the finished session for
    /// the finish-screen render path; the service drops its
    /// `activeSession` so the next `startWorkout` is unambiguous.
    @discardableResult
    func finishWorkout(perceivedEffort: Int? = nil, note: String? = nil) -> FinishedWorkout? {
        guard var session = activeSession else { return nil }
        guard session.completedSetCount > 0 else {
            lastFinishError = "Complete at least one working set before finishing."
            return nil
        }
        let now = Date()
        session.focus?.resume(at: now)
        session.focus?.rest = nil
        session.finishedAt = now
        session.perceivedEffort = perceivedEffort
        session.note = note
        if let pendingFinish, pendingFinish.id == session.id { session = pendingFinish }
        else { pendingFinish = session }
        do { try SwiftDataRepository.shared.saveWorkoutDurably(session) }
        catch {
            lastFinishError = error.localizedDescription
            return nil
        }
        lastFinishError = nil
        pendingFinish = nil
        NotificationService.cancelOneShot(id: restNotificationID(for: session.id))
        let detections = PRDetectionEngine.shared.ingest(session: session)
        activeSession = nil
        invalidatePreviousSetCache()
        WorkoutLiveActivityService.shared.finish(session)
        // Reward training (and any new PR). Both this service and the
        // store are @MainActor, so the call is a direct hop.
        DataStore.current?.recordWorkoutFinished(detectedPRCount: detections.count)
        DataStore.current?.refreshTrainingGlanceables()
        AppLog.training.info("Workout finished (id: \(session.id, privacy: .public), sets: \(session.completedSetCount, privacy: .public), PRs: \(detections.count, privacy: .public))")
        return FinishedWorkout(session: session, detectedPRs: detections)
    }

    func cancelFinishAttempt() {
        pendingFinish = nil
        lastFinishError = nil
    }

    /// Drop the in-progress session without recording it. Called when
    /// the user taps Discard on the finish-confirmation alert.
    func discardWorkout() {
        cancelFinishAttempt()
        guard let session = activeSession else { return }
        NotificationService.cancelOneShot(id: restNotificationID(for: session.id))
        SwiftDataRepository.shared.deleteWorkoutSession(id: session.id)
        activeSession = nil
        invalidatePreviousSetCache()
        WorkoutLiveActivityService.shared.endAll()
        DataStore.current?.refreshTrainingGlanceables()
        AppLog.training.info("Workout discarded (id: \(session.id, privacy: .public))")
    }

    // MARK: - Mutations

    func addExercise(_ exercise: Exercise) {
        guard var session = activeSession else { return }
        let nextIndex = session.exercises.count
        // Seed the first set with the user's last working weight /
        // reps for this exercise so they aren't staring at a 0kg
        // placeholder every time (audit Train M4). Default to a
        // conservative 8 reps when no history exists.
        let seed = lastCompletedSet(forExerciseID: exercise.id)
        let entry = WorkoutExerciseEntry(
            exerciseID: exercise.id,
            index: nextIndex,
            sets: [SetEntry(
                index: 1,
                weightKg: seed?.weightKg ?? 0,
                reps: seed?.reps ?? 8
            )]
        )
        session.exercises.append(entry)
        if session.focus == nil { session.focus = WorkoutFocusState() }
        session.focus?.selectedEntryID = entry.id
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
    func updateSet(_ set: SetEntry, inExerciseEntryID entryID: UUID, now: Date = Date()) {
        guard var session = activeSession,
              let exIdx = session.exercises.firstIndex(where: { $0.id == entryID }),
              let setIdx = session.exercises[exIdx].sets.firstIndex(where: { $0.id == set.id })
        else { return }
        let prior = session.exercises[exIdx].sets[setIdx]
        if session.isPaused && prior.completed != set.completed { return }
        var updated = set
        // The service is the persistence boundary for set values — the
        // decimal-pad keyboard hint is bypassable (paste, hardware
        // keyboard), so clamp here rather than trusting the UI.
        updated.weightKg = SetEntryLimits.clampWeightKg(updated.weightKg)
        updated.reps = SetEntryLimits.clampReps(updated.reps)
        // Stamp completedAt when transitioning to completed; clear on un-check.
        if set.completed && session.exercises[exIdx].sets[setIdx].completedAt == nil {
            updated.completedAt = now
        } else if !set.completed {
            updated.completedAt = nil
        }
        session.exercises[exIdx].sets[setIdx] = updated
        if session.focus == nil { session.focus = WorkoutFocusState(selectedEntryID: entryID) }
        if !prior.completed && updated.completed && !updated.isWarmup {
            session.focus?.rest = nil
            let seconds = session.exercises[exIdx].restSeconds
                ?? DataStore.current?.profile.trainingPreferences?.restTimerDefault ?? 90
            if seconds > 0, let target = session.nextPendingSet(after: entryID) {
                session.focus?.rest = WorkoutRestContext(
                    sourceEntryID: entryID, sourceSetID: updated.id,
                    targetEntryID: target.entry, targetSetID: target.set,
                    endsAt: now.addingTimeInterval(TimeInterval(seconds)),
                    totalSeconds: TimeInterval(seconds)
                )
            }
        }
        persist(session)
    }

    /// Rest between sets for one exercise in the active session. `nil`
    /// falls back to the user's training-preferences default.
    func setRestSeconds(_ seconds: Int?, forExerciseEntryID entryID: UUID) {
        guard var session = activeSession,
              let idx = session.exercises.firstIndex(where: { $0.id == entryID })
        else { return }
        session.exercises[idx].restSeconds = seconds
        persist(session)
    }

    func renameWorkout(_ name: String) {
        guard var session = activeSession else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.name = trimmed.isEmpty ? nil : trimmed
        persist(session)
    }

    /// Returns the last completed set the user logged for the given
    /// exercise in any prior workout session. Seeds new sets with the
    /// user's last working weight. Returns nil when the user hasn't ever
    /// logged this exercise.
    func lastCompletedSet(forExerciseID id: String) -> SetEntry? {
        previousSessionSets(forExerciseID: id).last
    }

    /// The completed sets, in order, from the most recent prior session
    /// that logged this exercise — the source of each row's "previous"
    /// hint (see `PreviousSetEngine`). Empty when there is no history.
    ///
    /// Memoized per exercise: an uncached lookup deserializes every stored
    /// workout, and the exercise stack asks on every re-render. The active
    /// session is excluded from the lookup, so editing its sets can't
    /// change the answer — only a start, finish or discard can, and those
    /// clear the cache.
    func previousSessionSets(forExerciseID id: String) -> [SetEntry] {
        if let cached = previousSetCache[id] { return cached }
        let resolved = resolvePreviousSessionSets(forExerciseID: id)
        previousSetCache[id] = resolved
        return resolved
    }

    private func resolvePreviousSessionSets(forExerciseID id: String) -> [SetEntry] {
        let sessions = SwiftDataRepository.shared.loadWorkoutSessions()
        // Walk newest-first, skip the in-flight session.
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            if session.id == activeSession?.id { continue }
            guard let exerciseEntry = session.exercises.first(where: { $0.exerciseID == id })
            else { continue }
            let completed = exerciseEntry.sets.filter(\.completed)
            if !completed.isEmpty { return completed }
        }
        return []
    }

    // MARK: - Focus and session clocks

    func selectExercise(_ id: UUID) {
        guard var session = activeSession, session.exercises.contains(where: { $0.id == id }) else { return }
        if session.focus == nil { session.focus = WorkoutFocusState() }
        session.focus?.selectedEntryID = id
        persist(session)
    }

    func togglePause(now: Date = Date()) {
        guard var session = activeSession else { return }
        if session.focus == nil { session.focus = WorkoutFocusState(selectedEntryID: session.selectedExercise?.id) }
        if session.isPaused { session.focus?.resume(at: now) }
        else { session.focus?.pause(at: now) }
        persist(session)
    }

    func skipRest() {
        guard var session = activeSession, let rest = session.focus?.rest else { return }
        if session.selectedExercise?.id == rest.sourceEntryID {
            session.focus?.selectedEntryID = rest.targetEntryID
        }
        session.focus?.rest = nil
        persist(session)
    }

    func adjustRest(by seconds: TimeInterval, now: Date = Date()) {
        guard var session = activeSession, var rest = session.focus?.rest else { return }
        let remaining = max(0, rest.remaining(at: now) + seconds)
        if remaining == 0 { skipRest(); return }
        rest.totalSeconds = remaining
        if session.isPaused { rest.frozenSeconds = remaining }
        else { rest.endsAt = now.addingTimeInterval(remaining) }
        session.focus?.rest = rest
        persist(session)
    }

    func reconcileRest(now: Date = Date()) {
        guard let session = activeSession, !session.isPaused,
              let rest = session.focus?.rest, rest.remaining(at: now) <= 0 else { return }
        skipRest()
    }

    private func restNotificationID(for sessionID: UUID) -> String {
        "atlas.workout.rest.\(sessionID.uuidString)"
    }

    private func syncRestNotification(for session: WorkoutSession) {
        let id = restNotificationID(for: session.id)
        NotificationService.cancelOneShot(id: id)
        guard !session.isPaused, let rest = session.focus?.rest,
              rest.remaining(at: Date()) > 0 else { return }
        NotificationService.scheduleOneShot(
            id: id, title: "Time to lift", body: "Rest is over. Your next set is ready.",
            after: rest.remaining(at: Date())
        )
    }

    // MARK: - Internals

    /// `[exerciseID: previous session's completed sets]`. An empty array is
    /// a cached "no history" answer, distinct from a miss. Ignored by
    /// observation: it's filled from inside view bodies, and a tracked
    /// write there would re-render the reader for no visible change.
    @ObservationIgnored private var previousSetCache: [String: [SetEntry]] = [:]

    private func invalidatePreviousSetCache() {
        previousSetCache.removeAll(keepingCapacity: true)
    }

    private func persist(_ value: WorkoutSession) {
        var session = value
        session.repairFocus()
        let previousRest = activeSession?.focus?.rest
        activeSession = session
        if previousRest != session.focus?.rest {
            syncRestNotification(for: session)
        }
        SwiftDataRepository.shared.upsertWorkoutSession(session)
        WorkoutLiveActivityService.shared.update(session)
    }
}

/// Pairs each set in the active workout with the set it should echo from
/// the previous session, so row 3's hint reads last time's third set
/// rather than every row repeating the final one.
enum PreviousSetEngine {
    /// `[current set id: previous set]`. Working sets pair by position
    /// among working sets, so a warm-up added or dropped this time doesn't
    /// shift every hint below it; rows past the end of last session's list
    /// fall back to its final set. Warm-up rows get no hint.
    static func hints(for current: [SetEntry], previous: [SetEntry]) -> [UUID: SetEntry] {
        let ordered = previous.sorted { $0.index < $1.index }
        let working = ordered.filter { !$0.isWarmup }
        let candidates = working.isEmpty ? ordered : working
        guard let fallback = candidates.last else { return [:] }

        var hints: [UUID: SetEntry] = [:]
        var position = 0
        for set in current.sorted(by: { $0.index < $1.index }) where !set.isWarmup {
            hints[set.id] = candidates.indices.contains(position) ? candidates[position] : fallback
            position += 1
        }
        return hints
    }
}

/// The rest durations offered by the active workout and routine editor.
enum RestTimeOptions {
    static let seconds = [30, 60, 90, 120, 180, 240]

    /// The standard options plus `current` when it's a value set elsewhere
    /// (an older build, a backup) — a picker whose selection has no
    /// matching row renders blank.
    static func choices(including current: Int?) -> [Int] {
        guard let current, current > 0, !seconds.contains(current) else { return seconds }
        return (seconds + [current]).sorted()
    }

    /// "30 sec", "1 min", "1:30 min".
    static func label(for seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }
}
