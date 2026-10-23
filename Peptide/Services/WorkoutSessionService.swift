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
    /// Set when `closeIfStale` closed a forgotten workout, so the Train
    /// tab can say so once. Cleared by `acknowledgeStaleClosure`.
    private(set) var staleClosure: StaleClosure?

    enum StaleClosure: Equatable {
        case discarded, finished
    }

    /// How recently a session must have started for a second `startWorkout`
    /// to be treated as a duplicate tap rather than a fresh workout. Roughly
    /// the SwiftUI re-render window.
    static let duplicateStartWindow: TimeInterval = 2

    private init() {
        // Re-hydrate any session that was active when the process was
        // suspended so the user picks up where they left off.
        activeSession = SwiftDataRepository.shared.loadActiveWorkoutSession()
        // Deferred: clearing an expired rest and closing both reach
        // DataStore, which reads `.shared` — still mid-initialisation here.
        Task { [weak self] in
            // The Live Activity and the Watch name the current exercise,
            // which reads "Unknown exercise" until the library has loaded.
            await ExerciseLibrary.shared.load()
            guard let self else { return }
            // An activity outlives the process, so a relaunch can inherit
            // one whose workout is long gone — or lose one whose workout isn't.
            WorkoutLiveActivityService.shared.reconcile(active: self.activeSession)
            DataStore.current?.pushWorkoutToWatch()
            self.reconcileRest()
            self.closeIfStale()
            self.closeStaleOrphans()
        }
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
    /// `linksRoutine` is false when `routine` is only a template built for
    /// the occasion (repeating an ad-hoc workout), so the session doesn't
    /// point at a routine that isn't in the library.
    ///
    /// `now` is the start instant, injectable so the duplicate window can
    /// be tested without waiting it out.
    @discardableResult
    func startWorkout(routine: Routine? = nil, linksRoutine: Bool = true, now: Date = Date()) -> WorkoutSession {
        if let existing = activeSession {
            if existing.startedAt.timeIntervalSince(now) > -Self.duplicateStartWindow {
                // Recently-started session — collapse the duplicate
                // start (deep link + tab tap, two finger taps on the
                // CTA, etc.) into the existing session instead of
                // discarding the user's data.
                return existing
            }
            discardWorkout()
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
            .map { entry in progressed(entry, routine: routine) }
        } ?? []

        let session = WorkoutSession(
            name: routine?.name,
            routineID: linksRoutine ? routine?.id : nil,
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
    /// `end` is the recorded finish time — earlier than now only when a
    /// forgotten workout is closed after the fact.
    @discardableResult
    func finishWorkout(perceivedEffort: Int? = nil, note: String? = nil, at end: Date = Date()) -> FinishedWorkout? {
        guard var session = activeSession else { return nil }
        guard session.completedSetCount > 0 else {
            lastFinishError = String(localized: "Complete at least one working set before finishing.")
            return nil
        }
        session.focus?.resume(at: end)
        session.focus?.rest = nil
        session.finishedAt = end
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
        if HealthSyncSettings.isEnabled {
            Task { await HealthKitService.shared.writeWorkout(session) }
        }
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

    /// Closes a workout left open for hours (see `WorkoutStalenessEngine`)
    /// through the normal finish / discard paths, so HealthKit, PRs, the
    /// Watch and widgets all hear about it. Runs on relaunch and whenever
    /// the app returns to the foreground.
    @discardableResult
    func closeIfStale(now: Date = Date()) -> StaleClosure? {
        guard let session = activeSession else { return nil }
        let closure: StaleClosure
        switch WorkoutStalenessEngine.verdict(for: session, now: now) {
        case .keep:
            return nil
        case .discard:
            discardWorkout()
            closure = .discarded
        case .finish(let end):
            // A failed finish attempt's snapshot would override `end`.
            cancelFinishAttempt()
            guard finishWorkout(at: end) != nil else {
                cancelFinishAttempt()
                return nil
            }
            // Skip the Live Activity's summary beat: it celebrates a
            // workout that ended hours ago.
            WorkoutLiveActivityService.shared.endAll()
            closure = .finished
        }
        staleClosure = closure
        AppLog.training.info("Stale workout closed (id: \(session.id, privacy: .public), \(String(describing: closure), privacy: .public))")
        return closure
    }

    /// Closes in-progress rows other than `activeSession` — left by a crash
    /// or synced in from another device — with the same verdicts as
    /// `closeIfStale`. A fresh one may be live on the other device, so it
    /// stays until it idles out. No HealthKit write: the device that ran
    /// the workout owns that.
    func closeStaleOrphans(now: Date = Date()) {
        let repo = SwiftDataRepository.shared
        let orphans = repo.loadUnfinishedWorkoutSessions().filter { $0.id != activeSession?.id }
        var changed = false
        for var orphan in orphans {
            switch WorkoutStalenessEngine.verdict(for: orphan, now: now) {
            case .keep:
                continue
            case .discard:
                repo.deleteWorkoutSession(id: orphan.id)
            case .finish(let end):
                orphan.focus?.resume(at: end)
                orphan.focus?.rest = nil
                orphan.finishedAt = end
                repo.upsertWorkoutSession(orphan)
                PRDetectionEngine.shared.ingest(session: orphan)
            }
            changed = true
            AppLog.training.info("Orphaned workout closed (id: \(orphan.id, privacy: .public))")
        }
        if changed {
            invalidatePreviousSetCache()
            DataStore.current?.refreshTrainingGlanceables()
        }
    }

    /// Re-reads the in-progress session after an iCloud account switch,
    /// so the previous account's workout doesn't stay on screen.
    func reloadActiveSession() {
        activeSession = SwiftDataRepository.shared.loadActiveWorkoutSession()
        WorkoutLiveActivityService.shared.reconcile(active: activeSession)
    }

    func acknowledgeStaleClosure() {
        staleClosure = nil
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
        let entry = progressed(WorkoutExerciseEntry(
            exerciseID: exercise.id,
            index: nextIndex,
            sets: [SetEntry(
                index: 1,
                weightKg: seed?.weightKg ?? 0,
                reps: seed?.reps ?? 8,
                measurement: seed?.measurement
            )]
        ), routine: nil)
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
        session.dissolveLoneSupersets()
        persist(session)
    }

    /// Supersets `entryID` with the exercise below it.
    func supersetWithNext(_ entryID: UUID) {
        guard var session = activeSession else { return }
        session.linkSupersetWithNext(entryID)
        persist(session)
    }

    func removeFromSuperset(_ entryID: UUID) {
        guard var session = activeSession else { return }
        session.unlinkSuperset(entryID)
        persist(session)
    }

    /// `id` is supplied by the Watch, which names the set it added so it
    /// can log it before this side answers.
    func addSet(toExerciseID exerciseEntryID: UUID, id: UUID = UUID()) {
        guard var session = activeSession,
              let idx = session.exercises.firstIndex(where: { $0.id == exerciseEntryID }),
              !session.exercises[idx].sets.contains(where: { $0.id == id })
        else { return }
        let prev = session.exercises[idx].sets.last
        let nextIndex = (session.exercises[idx].sets.last?.index ?? 0) + 1
        // Pre-fill from previous set so two-tap logging works.
        let next = SetEntry(
            id: id,
            index: nextIndex,
            weightKg: prev?.weightKg ?? 0,
            reps: prev?.reps ?? 8,
            rpe: prev?.rpe,
            measurement: prev?.measurement
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

    /// The set as the session holds it now. Row bindings read through
    /// this rather than a render-time copy: a weight committed on focus
    /// loss right after the check is tapped would otherwise write back
    /// the copy's stale `completed == false`.
    func currentSet(id setID: UUID, inExerciseEntryID entryID: UUID) -> SetEntry? {
        activeSession?.exercises.first { $0.id == entryID }?.sets.first { $0.id == setID }
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
            if let target = session.nextPendingSet(after: entryID),
               session.continuesSuperset(from: entryID, to: target.entry) {
                session.focus?.selectedEntryID = target.entry
            } else if seconds > 0, let target = session.nextPendingSet(after: entryID) {
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

    /// Undo only the set responsible for the currently displayed rest. Resolve
    /// the live record so edits to load/reps made during rest are preserved.
    func undoRestSourceSet() {
        guard let session = activeSession, !session.isPaused,
              let rest = session.focus?.rest,
              let entry = session.exercises.first(where: { $0.id == rest.sourceEntryID }),
              var set = entry.sets.first(where: { $0.id == rest.sourceSetID }), set.completed
        else { return }
        set.completed = false
        updateSet(set, inExerciseEntryID: entry.id)
        selectExercise(entry.id)
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
    /// Read from a memo of every exercise built in one pass over the recent
    /// history window: a lookup deserializes the stored workouts, and
    /// seeding a routine plus the exercise stack's re-renders ask once per
    /// exercise. Only finished sessions count — not the active one, nor one
    /// still open on another device — so editing sets can't change the
    /// answer; only a start, finish, discard, orphan closure or history
    /// edit can, and those clear the memo. A lift missing from the window
    /// is looked up once in the rest of the history, decoding only the
    /// workouts that log it, so one last done hundreds of workouts ago
    /// still has a previous without decoding every workout at start. An
    /// exercise logged twice in one session contributes both entries'
    /// sets, in entry order.
    func previousSessionSets(forExerciseID id: String) -> [SetEntry] {
        if let sets = previousSetsByExercise()[id] { return sets }
        let older = SwiftDataRepository.shared.loadFinishedWorkoutSessions(touching: [id])
            .reversed()
            .lazy
            .map { Self.completedSets(of: id, in: $0) }
            .first { !$0.isEmpty } ?? []
        previousSetCache?[id] = older
        return older
    }

    private func previousSetsByExercise() -> [String: [SetEntry]] {
        if let cached = previousSetCache { return cached }
        var byExercise: [String: [SetEntry]] = [:]
        // Newest first, so each exercise keeps its most recent session.
        for session in SwiftDataRepository.shared.loadWorkoutSessions() where session.finishedAt != nil {
            for exerciseID in Set(session.exercises.map(\.exerciseID)) where byExercise[exerciseID] == nil {
                let completed = Self.completedSets(of: exerciseID, in: session)
                if !completed.isEmpty { byExercise[exerciseID] = completed }
            }
        }
        previousSetCache = byExercise
        return byExercise
    }

    nonisolated private static func completedSets(of exerciseID: String, in session: WorkoutSession) -> [SetEntry] {
        session.exercises
            .filter { $0.exerciseID == exerciseID }
            .sorted { $0.index < $1.index }
            .flatMap { $0.sets.filter { $0.completed && $0.supportsRepLogging } }
    }

    // MARK: - Progression

    /// The next step for an exercise in the active workout, read from the
    /// last session that logged it. Nil without history or comparable load.
    func progression(for entry: WorkoutExerciseEntry) -> ProgressionEngine.Suggestion? {
        let routine = activeSession?.routineID.flatMap { id in
            RoutineStore.shared.routines.first { $0.id == id }
        }
        return progression(for: entry.exerciseID, targetReps: targetReps(for: entry, in: routine))
    }

    /// Fills the exercise's unchecked working sets with its suggestion.
    func applyProgression(toExerciseEntryID entryID: UUID) {
        guard var session = activeSession,
              let idx = session.exercises.firstIndex(where: { $0.id == entryID }),
              let suggestion = progression(for: session.exercises[idx])
        else { return }
        session.exercises[idx].sets = ProgressionEngine.apply(suggestion, to: session.exercises[idx].sets)
        persist(session)
    }

    /// The slot this entry was seeded from. Entries take their slot's
    /// position, so a routine listing one exercise twice keeps each slot's
    /// own target; an entry moved since falls back to the first match.
    private func targetReps(for entry: WorkoutExerciseEntry, in routine: Routine?) -> Int? {
        guard let slots = routine?.exercises.sorted(by: { $0.index < $1.index }) else { return nil }
        if slots.indices.contains(entry.index), slots[entry.index].exerciseID == entry.exerciseID {
            return slots[entry.index].targetReps
        }
        return slots.first(where: { $0.exerciseID == entry.exerciseID })?.targetReps
    }

    private func progression(for id: String, targetReps target: Int?) -> ProgressionEngine.Suggestion? {
        let exercise = ExerciseLibrary.shared.lookup(id: id)
        let profile = DataStore.current?.profile
        let unit = profile?.bodyMetrics.unit ?? .metric
        let plates = (profile?.trainingPreferences ?? TrainingPreferences()).plates(for: unit)
        return ProgressionEngine.suggestion(
            previous: previousSessionSets(forExerciseID: id),
            repRange: ProgressionEngine.repRange(targetReps: target, mechanic: exercise?.mechanic),
            incrementKg: ProgressionEngine.incrementKg(for: exercise?.equipmentKind ?? .other, unit: unit, plates: plates)
        )
    }

    /// Seeds a new entry at its suggested load when auto-progression is on
    /// (the default), so the workout opens at the weight to beat.
    private func progressed(_ entry: WorkoutExerciseEntry, routine: Routine?) -> WorkoutExerciseEntry {
        guard DataStore.current?.profile.trainingPreferences?.autoProgression ?? true,
              let suggestion = progression(for: entry.exerciseID, targetReps: targetReps(for: entry, in: routine))
        else { return entry }
        var seeded = entry
        seeded.sets = ProgressionEngine.apply(suggestion, to: entry.sets)
        return seeded
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
        // The widget's timer ticks on its own, so it only learns about a
        // pause from a fresh payload.
        DataStore.current?.refreshTrainingGlanceables()
    }

    func skipRest() {
        guard var session = activeSession, let rest = session.focus?.rest else { return }
        if session.selectedExercise?.id == rest.sourceEntryID {
            session.focus?.selectedEntryID = rest.targetEntryID
        }
        session.focus?.rest = nil
        persist(session)
    }

    /// The Live Activity's "Complete set": ticks the set the rest is
    /// counting down to, or else the next open set of the current
    /// exercise, exactly as checking it off in the app would.
    func completeNextSet(now: Date = Date()) {
        guard let session = activeSession, !session.isPaused else { return }
        let target = session.focus?.rest.map { (entry: $0.targetEntryID, set: $0.targetSetID) }
            ?? session.selectedExercise.flatMap { session.nextPendingSet(after: $0.id) }
        guard let target,
              var set = session.exercises.first(where: { $0.id == target.entry })?
                .sets.first(where: { $0.id == target.set }),
              !set.completed
        else { return }
        set.completed = true
        updateSet(set, inExerciseEntryID: target.entry, now: now)
    }

    func adjustRest(by seconds: TimeInterval, now: Date = Date()) {
        guard var session = activeSession, var rest = session.focus?.rest else { return }
        let remaining = max(0, rest.remaining(at: now) + seconds)
        if remaining == 0 { skipRest(); return }
        // The ring draws remaining / total, so the total only grows when
        // the rest is extended past it; resetting it would refill the ring.
        rest.totalSeconds = max(rest.totalSeconds, remaining)
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

    // MARK: - Watch

    /// Applies a tap from the Watch through the same mutations the phone's
    /// own controls use. A request for a workout that has since finished
    /// or been replaced is dropped.
    func apply(_ request: WatchWorkoutRequest, now: Date = Date()) {
        guard let session = activeSession, session.id == request.sessionId else { return }
        // A tap queued while the phone was away still starts its rest from
        // the tap; a watch clock running ahead can't start one in the future.
        let tappedAt = min(request.issuedAt, now)
        switch request.command {
        case let .completeSet(entryID, setID, weightKg, reps):
            guard var set = session.exercises.first(where: { $0.id == entryID })?
                    .sets.first(where: { $0.id == setID }),
                  !set.completed
            else { return }
            selectExercise(entryID)
            if set.supportsRepLogging {
                set.weightKg = weightKg
                set.reps = reps
            }
            set.completed = true
            updateSet(set, inExerciseEntryID: entryID, now: tappedAt)
        case .skipRest:
            guard session.restWasRunning(at: tappedAt) else { return }
            skipRest()
        case let .extendRest(seconds):
            guard session.restWasRunning(at: tappedAt) else { return }
            adjustRest(by: TimeInterval(seconds), now: tappedAt)
        case let .selectExercise(entryID):
            selectExercise(entryID)
        case let .addSet(entryID, setID):
            addSet(toExerciseID: entryID, id: setID)
            selectExercise(entryID)
        case let .setPaused(paused):
            if session.isPaused != paused { togglePause(now: tappedAt) }
        }
    }

    /// Rest-end request IDs, under `NotificationService.adHocIDPrefix`.
    /// `NotificationDelegate` reads it to keep the system banner off the
    /// workout screen, which already signals rest end itself.
    nonisolated static let restNotificationPrefix = "atlas.workout.rest."

    private func restNotificationID(for sessionID: UUID) -> String {
        "\(Self.restNotificationPrefix)\(sessionID.uuidString)"
    }

    private func syncRestNotification(for session: WorkoutSession) {
        let id = restNotificationID(for: session.id)
        NotificationService.cancelOneShot(id: id)
        guard !session.isPaused, let rest = session.focus?.rest,
              rest.remaining(at: Date()) > 0 else { return }
        NotificationService.scheduleOneShot(
            id: id, title: String(localized: "Time to lift"),
            body: String(localized: "Rest is over. Your next set is ready."),
            after: rest.remaining(at: Date())
        )
    }

    // MARK: - Internals

    /// `[exerciseID: previous session's completed sets]`; nil until first
    /// read. Ignored by observation: it's filled from inside view bodies,
    /// and a tracked write there would re-render the reader for no visible
    /// change.
    @ObservationIgnored private var previousSetCache: [String: [SetEntry]]?

    /// Called whenever stored history changes under an active workout.
    func invalidatePreviousSetCache() {
        previousSetCache = nil
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
        DataStore.current?.pushWorkoutToWatch()
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
        if seconds < 60 { return String(localized: "\(seconds) sec") }
        if seconds % 60 == 0 { return String(localized: "\(seconds / 60) min") }
        let minutesSeconds = Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        return String(localized: "\(minutesSeconds) min")
    }
}
