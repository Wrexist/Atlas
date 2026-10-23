import Foundation

@MainActor @Observable
final class WorkoutRecapStore {
    private(set) var session: WorkoutSession
    private(set) var summary: WorkoutRecapEngine.Summary?
    private(set) var week: WorkoutRecapEngine.Week?
    private(set) var metadataUnavailable = false
    private(set) var historyUnavailable = false
    /// Set once the user saves an edit, so the summary stops celebrating
    /// records the edit may have removed.
    private(set) var wasEdited = false
    /// A recap reopened from history charts the workout's own week, not today's.
    private let anchorsWeekOnSession: Bool

    init(session: WorkoutSession, anchorsWeekOnSession: Bool = false) {
        self.session = session
        self.anchorsWeekOnSession = anchorsWeekOnSession
    }

    func load(now: Date = Date(), calendar: Calendar = .current) async {
        let library = ExerciseLibrary.shared
        await library.load()
        refresh(now: now, calendar: calendar)
    }

    private func refresh(now: Date = Date(), calendar: Calendar = .current) {
        let library = ExerciseLibrary.shared
        let repo = SwiftDataRepository.shared
        library.attachCustomExercises(repo.loadCustomExercises())
        if let saved = repo.loadWorkoutSession(id: session.id) { session = saved }
        var history: [WorkoutSession] = []
        historyUnavailable = false
        let anchor = anchorsWeekOnSession ? session.startedAt : now
        if let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) {
            do { history = try repo.loadWorkoutRecapWeek(in: interval.start..<interval.end) }
            catch { historyUnavailable = true }
        } else { historyUnavailable = true }
        var catalog: [String: Exercise] = [:]
        for id in Set((history + [session]).flatMap { $0.exercises.map(\.exerciseID) }) {
            catalog[id] = library.lookup(id: id)
        }
        metadataUnavailable = !library.isLoaded
        summary = WorkoutRecapEngine.derive(session, catalog: catalog)
        week = historyUnavailable ? nil : WorkoutRecapEngine.week(
            sessions: history, catalog: catalog, anchor: anchor, now: now, calendar: calendar)
    }

    func saveEdits(_ edited: WorkoutSession) throws {
        try WorkoutEditValidation.validate(edited, original: session)
        try SwiftDataRepository.shared.saveWorkoutDurably(edited)
        let affected = Set((session.exercises + edited.exercises).map(\.exerciseID))
        session = edited
        wasEdited = true
        DataStore.current?.workoutWasEdited(exerciseIDs: affected)
        refresh()
    }
}
