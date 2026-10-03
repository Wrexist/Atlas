import Foundation

/// Optional on older sessions. Stored separately from the exercise payload so
/// adding the focus experience never changes existing set IDs or history.
struct WorkoutFocusState: Codable, Hashable, Sendable {
    var selectedEntryID: UUID?
    var pausedAt: Date?
    var pausedSeconds: TimeInterval = 0
    var rest: WorkoutRestContext?

    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
        if var rest {
            rest.frozenSeconds = rest.remaining(at: now)
            rest.endsAt = nil
            self.rest = rest.frozenSeconds == 0 ? nil : rest
        }
    }

    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedSeconds += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        if var rest, let remaining = rest.frozenSeconds {
            rest.endsAt = now.addingTimeInterval(remaining)
            rest.frozenSeconds = nil
            self.rest = rest
        }
    }
}

struct WorkoutRestContext: Codable, Hashable, Sendable {
    var sourceEntryID: UUID
    var sourceSetID: UUID
    var targetEntryID: UUID
    var targetSetID: UUID
    var endsAt: Date?
    var totalSeconds: TimeInterval
    var frozenSeconds: TimeInterval?

    func remaining(at now: Date) -> TimeInterval {
        max(0, frozenSeconds ?? endsAt?.timeIntervalSince(now) ?? 0)
    }

    func remainingFraction(at now: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, remaining(at: now) / totalSeconds)
    }
}

extension WorkoutSession {
    var isPaused: Bool { focus?.pausedAt != nil }

    var selectedExercise: WorkoutExerciseEntry? {
        exercises.first { $0.id == focus?.selectedEntryID }
            ?? exercises.first { $0.sets.contains { !$0.completed } }
            ?? exercises.first
    }

    /// Continue the selected exercise before moving through the rest of the
    /// workout. Stable entry IDs allow the same catalog exercise twice.
    func nextPendingSet(after entryID: UUID) -> (entry: UUID, set: UUID)? {
        let ordered = exercises.sorted { $0.index < $1.index }
        let preferred = ordered.filter { $0.id == entryID } + ordered.filter { $0.id != entryID }
        for entry in preferred {
            if let set = entry.sets.first(where: { !$0.completed && !$0.isWarmup }) {
                return (entry.id, set.id)
            }
        }
        return nil
    }

    mutating func repairFocus() {
        guard var focus else { return }
        if !exercises.contains(where: { $0.id == focus.selectedEntryID }) {
            focus.selectedEntryID = selectedExercise?.id
        }
        if let rest = focus.rest {
            let sourceValid = exercises.contains { entry in
                entry.id == rest.sourceEntryID && entry.sets.contains { $0.id == rest.sourceSetID && $0.completed }
            }
            let targetValid = exercises.contains { entry in
                entry.id == rest.targetEntryID && entry.sets.contains { $0.id == rest.targetSetID && !$0.completed }
            }
            if !sourceValid || !targetValid { focus.rest = nil }
        }
        self.focus = focus
    }
}
