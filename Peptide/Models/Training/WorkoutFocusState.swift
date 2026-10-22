import Foundation

/// Optional on older sessions. Stored separately from the exercise payload so
/// adding the focus experience never changes existing set IDs or history.
struct WorkoutFocusState: Codable, Hashable, Sendable {
    enum Timing: String, Codable, Sendable { case tracked, notTracked, unavailable }
    var timing: Timing?
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
    /// True when the current rest had started and not yet run out at
    /// `date` — so a queued watch tap from then was aimed at this rest,
    /// not at one a later set started.
    func restWasRunning(at date: Date) -> Bool {
        guard let rest = focus?.rest, rest.remaining(at: date) > 0 else { return false }
        let startedAt = exercises.first { $0.id == rest.sourceEntryID }?
            .sets.first { $0.id == rest.sourceSetID }?.completedAt
        return (startedAt ?? .distantPast) <= date
    }

    var isPaused: Bool { focus?.pausedAt != nil }

    var selectedExercise: WorkoutExerciseEntry? {
        exercises.first { $0.id == focus?.selectedEntryID }
            ?? exercises.first { $0.sets.contains { !$0.completed } }
            ?? exercises.first
    }

    /// Continue the selected exercise before moving through the rest of the
    /// workout. Stable entry IDs allow the same catalog exercise twice.
    /// Inside a superset the round comes first, so sets alternate A, B, A, B.
    func nextPendingSet(after entryID: UUID) -> (entry: UUID, set: UUID)? {
        let ordered = exercises.sorted { $0.index < $1.index }
        let round = supersetRound(after: entryID, in: ordered)
        let preferred = round + ordered.filter { entry in !round.contains { $0.id == entry.id } }
        for entry in preferred {
            if let set = entry.sets.first(where: { !$0.completed && !$0.isWarmup }) {
                return (entry.id, set.id)
            }
        }
        return nil
    }

    /// The source alone, or its superset partners after it wrapping round
    /// to the source itself.
    private func supersetRound(after entryID: UUID, in ordered: [WorkoutExerciseEntry]) -> [WorkoutExerciseEntry] {
        guard let source = ordered.first(where: { $0.id == entryID }) else { return [] }
        guard let group = source.supersetGroup else { return [source] }
        let members = ordered.filter { $0.supersetGroup == group }
        let start = members.firstIndex { $0.id == entryID } ?? 0
        return Array(members[(start + 1)...]) + Array(members[...start])
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
