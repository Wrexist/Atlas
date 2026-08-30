import Foundation
import OSLog

/// The user's routine library, held in memory so the list, the builder,
/// and the Train overview all read the same array and re-render together.
/// Every mutation runs a `RoutineEditEngine` transform, writes through to
/// `SwiftDataRepository`, and leaves `routines` in the order the list
/// should draw.
@MainActor @Observable
final class RoutineStore {
    static let shared = RoutineStore()

    private(set) var routines: [Routine] = []

    private var repository: SwiftDataRepository { .shared }

    private init() {}

    /// Pulls the library out of SwiftData. Cheap enough to call from
    /// `.task` on every routine surface — the rows are small and the
    /// exercise list is a single JSON blob per routine.
    func load() {
        routines = repository.loadRoutines()
    }

    // MARK: - Library

    @discardableResult
    func create(name: String, exercises: [RoutineExercise] = []) -> Routine {
        let routine = RoutineEditEngine.normalized(
            Routine(
                name: RoutineEditEngine.sanitizedName(name) ?? Self.untitledName,
                exercises: exercises,
                sortIndex: nextSortIndex
            )
        )
        repository.upsertRoutine(routine)
        load()
        return routine
    }

    /// Persists an edited routine and re-sorts the library around it.
    /// The builder's own edits come through here on every keystroke-free
    /// commit (add exercise, change targets, reorder slots).
    func save(_ routine: Routine) {
        var updated = routine
        updated.updatedAt = Date()
        if updated.sortIndex == nil { updated.sortIndex = nextSortIndex }
        repository.upsertRoutine(updated)
        load()
    }

    func rename(id: UUID, to name: String) {
        guard var routine = routines.first(where: { $0.id == id }),
              let sanitized = RoutineEditEngine.sanitizedName(name)
        else { return }
        routine.name = sanitized
        save(routine)
    }

    @discardableResult
    func duplicate(id: UUID) -> Routine? {
        guard let original = routines.first(where: { $0.id == id }) else { return nil }
        let copy = RoutineEditEngine.duplicate(original, existingNames: routines.map(\.name))
        // Land the copy directly under its original rather than at the
        // bottom — the user duplicated it to edit it, and a library of
        // twelve routines would otherwise scroll away from the source.
        var reordered = routines
        let position = reordered.firstIndex { $0.id == id }.map { $0 + 1 } ?? reordered.count
        reordered.insert(copy, at: position)
        persist(RoutineEditEngine.reindexed(reordered))
        return copy
    }

    func delete(id: UUID) {
        repository.deleteRoutine(id: id)
        persist(RoutineEditEngine.reindexed(routines.filter { $0.id != id }))
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        persist(RoutineEditEngine.moved(routines, fromOffsets: source, toOffset: destination))
    }

    // MARK: - Starting a workout

    /// The payoff: one tap from the routine card to a session seeded with
    /// the routine's exercises, target sets and the user's last weights.
    @discardableResult
    func startWorkout(from routine: Routine) -> WorkoutSession {
        AppLog.training.info("Starting workout from routine (id: \(routine.id, privacy: .public))")
        return WorkoutSessionService.shared.startWorkout(routine: routine)
    }

    // MARK: - Internals

    static let untitledName = "New routine"

    private var nextSortIndex: Int {
        (routines.compactMap(\.sortIndex).max() ?? routines.count - 1) + 1
    }

    /// Writes an already-ordered list back and adopts it as the in-memory
    /// order, rather than re-reading — a fetch would re-sort by the values
    /// we just wrote and cost a round-trip to show the same array.
    private func persist(_ ordered: [Routine]) {
        for routine in ordered {
            repository.upsertRoutine(routine)
        }
        routines = ordered
    }
}
