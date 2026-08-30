import Foundation

/// Every structural edit the routine list and builder can make, as pure
/// value transforms. `RoutineStore` decides *when* an edit happens and
/// persists the result; this decides *what* the result is, so the fiddly
/// parts — re-indexing after a drag, giving a duplicate fresh identity —
/// are testable without a store.
enum RoutineEditEngine {

    /// Longest routine or note string accepted from the editor. Free text
    /// from a keyboard is a system boundary; a pasted essay shouldn't
    /// become a row title that pushes the Start button off the card.
    static let nameLimit = 60

    static let targetSets: ClosedRange<Int> = 1...20
    static let targetReps: ClosedRange<Int> = 1...100

    // MARK: - The list

    /// Renumbers `sortIndex` to match array order. Every list-level edit
    /// ends here so the stored order and the displayed order can't drift.
    static func reindexed(_ routines: [Routine]) -> [Routine] {
        routines.enumerated().map { position, routine in
            var copy = routine
            copy.sortIndex = position
            return copy
        }
    }

    /// Applies a drag-to-reorder and renumbers the whole list.
    static func moved(
        _ routines: [Routine],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Routine] {
        var reordered = routines
        reordered.move(fromOffsets: source, toOffset: destination)
        return reindexed(reordered)
    }

    /// Copies a routine into a fresh identity: new routine id, new slot
    /// ids, and a name that doesn't collide with anything already in the
    /// library. Sharing slot ids with the original would make the two
    /// routines edit each other through any id-keyed lookup.
    static func duplicate(
        _ routine: Routine,
        existingNames: [String],
        now: Date = Date()
    ) -> Routine {
        Routine(
            name: copyName(of: routine.name, avoiding: Set(existingNames)),
            subtitle: routine.subtitle,
            exercises: routine.exercises.map { slot in
                RoutineExercise(
                    exerciseID: slot.exerciseID,
                    index: slot.index,
                    targetSets: slot.targetSets,
                    targetReps: slot.targetReps,
                    targetRPE: slot.targetRPE,
                    targetPercentOf1RM: slot.targetPercentOf1RM,
                    restSeconds: slot.restSeconds,
                    note: slot.note
                )
            },
            defaultRestSeconds: routine.defaultRestSeconds,
            updatedAt: now,
            sortIndex: routine.sortIndex
        )
    }

    /// "Push day" → "Push day copy" → "Push day copy 2", Finder-style.
    private static func copyName(of name: String, avoiding taken: Set<String>) -> String {
        let base = truncated("\(name) copy")
        guard taken.contains(base) else { return base }
        for suffix in 2...99 {
            let candidate = truncated("\(name) copy \(suffix)")
            if !taken.contains(candidate) { return candidate }
        }
        return base
    }

    /// Trims and length-caps a name typed into the editor. Returns nil
    /// when nothing is left, so callers can fall back to a default rather
    /// than storing an untappable blank row.
    static func sanitizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : truncated(trimmed)
    }

    private static func truncated(_ value: String) -> String {
        String(value.prefix(nameLimit))
    }

    // MARK: - The exercise slots

    static func appending(exerciseID: String, to routine: Routine, now: Date = Date()) -> Routine {
        var updated = routine
        updated.exercises.append(
            RoutineExercise(exerciseID: exerciseID, index: routine.exercises.count)
        )
        updated.updatedAt = now
        return normalized(updated)
    }

    static func removingSlot(id: UUID, from routine: Routine, now: Date = Date()) -> Routine {
        var updated = routine
        updated.exercises.removeAll { $0.id == id }
        updated.updatedAt = now
        return normalized(updated)
    }

    static func movingSlots(
        in routine: Routine,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        now: Date = Date()
    ) -> Routine {
        var updated = normalized(routine)
        updated.exercises.move(fromOffsets: source, toOffset: destination)
        // Renumber in *array* order, not by index — sorting here would
        // read the pre-move indices back and undo the drag.
        updated.exercises = renumbered(updated.exercises)
        updated.updatedAt = now
        return updated
    }

    /// Rewrites one slot's target scheme, clamping both figures to what a
    /// set editor can actually render.
    static func updatingTargets(
        slotID: UUID,
        sets: Int,
        reps: Int,
        in routine: Routine,
        now: Date = Date()
    ) -> Routine {
        guard let index = routine.exercises.firstIndex(where: { $0.id == slotID }) else {
            return routine
        }
        var updated = routine
        updated.exercises[index].targetSets = clamp(sets, to: targetSets)
        updated.exercises[index].targetReps = clamp(reps, to: targetReps)
        updated.updatedAt = now
        return updated
    }

    /// Sorts slots by index and renumbers them contiguously from zero.
    /// Any structural edit leaves gaps or duplicates otherwise, and the
    /// session seeder reads `index` as the source of truth for order.
    static func normalized(_ routine: Routine) -> Routine {
        var updated = routine
        updated.exercises = renumbered(routine.exercises.sorted { $0.index < $1.index })
        return updated
    }

    private static func renumbered(_ slots: [RoutineExercise]) -> [RoutineExercise] {
        slots.enumerated().map { position, slot in
            var copy = slot
            copy.index = position
            return copy
        }
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
