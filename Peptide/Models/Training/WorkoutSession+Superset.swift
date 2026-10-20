import Foundation

/// Supersets: adjacent exercises worked in rounds, one set of each, with
/// rest only after the round. Membership is the shared `supersetGroup`.
extension WorkoutSession {

    /// The other members of `entryID`'s superset, in workout order.
    func supersetPartners(of entryID: UUID) -> [WorkoutExerciseEntry] {
        guard let group = exercises.first(where: { $0.id == entryID })?.supersetGroup else { return [] }
        return exercises
            .filter { $0.supersetGroup == group && $0.id != entryID }
            .sorted { $0.index < $1.index }
    }

    /// "A", "B"… lettered in the order supersets first appear.
    func supersetLetter(for entryID: UUID) -> String? {
        guard let group = exercises.first(where: { $0.id == entryID })?.supersetGroup else { return nil }
        var seen: [UUID] = []
        for entry in exercises.sorted(by: { $0.index < $1.index }) {
            if let other = entry.supersetGroup, !seen.contains(other) { seen.append(other) }
        }
        guard let position = seen.firstIndex(of: group) else { return nil }
        return String(Character(UnicodeScalar(UInt8(65 + position % 26))))
    }

    /// True while a round is still going: the target is another member
    /// that hasn't matched the source's set count yet, so the rest timer
    /// waits. Counting sets rather than comparing positions keeps a round
    /// started on a later member (B, then A) rest-free too.
    func continuesSuperset(from entryID: UUID, to targetID: UUID) -> Bool {
        guard entryID != targetID,
              let source = exercises.first(where: { $0.id == entryID }),
              let target = exercises.first(where: { $0.id == targetID }),
              let group = source.supersetGroup, target.supersetGroup == group
        else { return false }
        return target.completedWorkingSets.count < source.completedWorkingSets.count
    }

    /// The exercise below `entryID` in the workout, if any.
    func entryBelow(_ entryID: UUID) -> WorkoutExerciseEntry? {
        let ordered = exercises.sorted { $0.index < $1.index }
        guard let position = ordered.firstIndex(where: { $0.id == entryID }),
              ordered.indices.contains(position + 1)
        else { return nil }
        return ordered[position + 1]
    }

    /// Joins `entryID` and the exercise below it into one superset. Either
    /// side's existing superset is absorbed, so chaining builds a giant set.
    mutating func linkSupersetWithNext(_ entryID: UUID) {
        guard let source = exercises.first(where: { $0.id == entryID }),
              let below = entryBelow(entryID)
        else { return }
        let group = source.supersetGroup ?? below.supersetGroup ?? UUID()
        let absorbed: Set<UUID?> = [source.supersetGroup, below.supersetGroup]
        for i in exercises.indices
        where exercises[i].id == source.id || exercises[i].id == below.id
            || (exercises[i].supersetGroup != nil && absorbed.contains(exercises[i].supersetGroup)) {
            exercises[i].supersetGroup = group
        }
    }

    /// Takes `entryID` out of its superset. A superset left with one
    /// member is no superset, so that member is released too.
    mutating func unlinkSuperset(_ entryID: UUID) {
        guard let i = exercises.firstIndex(where: { $0.id == entryID }) else { return }
        exercises[i].supersetGroup = nil
        dissolveLoneSupersets()
    }

    mutating func dissolveLoneSupersets() {
        let counts = Dictionary(grouping: exercises.compactMap(\.supersetGroup), by: { $0 }).mapValues(\.count)
        for i in exercises.indices where exercises[i].supersetGroup.map({ counts[$0] == 1 }) == true {
            exercises[i].supersetGroup = nil
        }
    }
}
