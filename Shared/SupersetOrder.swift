import Foundation

/// Where to look for the next set after one is logged, shared by the phone's
/// `WorkoutSession` and the Watch's snapshot so both land on the same set.
/// Inside a superset the round comes first, so sets alternate A, B, A, B.
enum SupersetOrder {

    /// `ordered` in workout order, rearranged to search from `sourceID`: its
    /// superset partners after it, wrapping round to the source, then every
    /// other exercise in workout order. A standalone source leads alone.
    static func searchOrder<Item>(
        after sourceID: UUID,
        in ordered: [Item],
        id: (Item) -> UUID,
        group: (Item) -> UUID?
    ) -> [Item] {
        let round = self.round(after: sourceID, in: ordered, id: id, group: group)
        let roundIDs = Set(round.map(id))
        return round + ordered.filter { !roundIDs.contains(id($0)) }
    }

    /// True while a round is still going: the target is another member that
    /// hasn't matched the source's completed set count yet, so no rest runs.
    static func continuesRound(
        sourceID: UUID, sourceGroup: UUID?, sourceCompleted: Int,
        targetID: UUID, targetGroup: UUID?, targetCompleted: Int
    ) -> Bool {
        guard sourceID != targetID, let sourceGroup, targetGroup == sourceGroup else { return false }
        return targetCompleted < sourceCompleted
    }

    private static func round<Item>(
        after sourceID: UUID,
        in ordered: [Item],
        id: (Item) -> UUID,
        group: (Item) -> UUID?
    ) -> [Item] {
        guard let source = ordered.first(where: { id($0) == sourceID }) else { return [] }
        guard let sourceGroup = group(source) else { return [source] }
        let members = ordered.filter { group($0) == sourceGroup }
        let start = members.firstIndex { id($0) == sourceID } ?? 0
        return Array(members[(start + 1)...]) + Array(members[...start])
    }
}
