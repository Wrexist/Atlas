import Foundation

/// Loads the bundled `community-stacks.json` and produces forked
/// `PeptideProtocol` instances with author attribution preserved.
@MainActor
final class CommunityStackService {
    static let shared = CommunityStackService()

    private(set) var stacks: [CommunityStack]

    private init(stacks: [CommunityStack]? = nil) {
        self.stacks = stacks ?? Self.loadFromBundle()
    }

    /// Returns stacks ordered by popularity, with featured items floated
    /// to the front in popularity order.
    func ranked() -> [CommunityStack] {
        let featured = stacks.filter(\.featured).sorted { $0.popularityScore > $1.popularityScore }
        let rest = stacks.filter { !$0.featured }.sorted { $0.popularityScore > $1.popularityScore }
        return featured + rest
    }

    /// Forks a community stack into a `PeptideProtocol` ready to be saved
    /// via `DataStore.addProtocol`. Keeps the original author attribution
    /// and a permanent backlink (`forkedFromStackId`).
    func forkToProtocol(_ stack: CommunityStack) -> PeptideProtocol {
        let peptides = stack.peptideAbbreviations.compactMap { PeptideDatabase.peptide(matching: $0) }
        let times = Self.defaultTimes(for: stack.scheduleTimesPerDay)
        let schedule = ProtocolSchedule(
            daysOfWeek: stack.scheduleDaysOfWeek,
            timesPerDay: stack.scheduleTimesPerDay,
            preferredTimes: times
        )
        return PeptideProtocol(
            id: UUID(),
            name: stack.name,
            peptides: peptides,
            schedule: schedule,
            cycleLengthWeeks: stack.cycleLengthWeeks,
            startDate: Date(),
            status: .active,
            notes: "Forked from \(stack.authorName)'s community stack.\n\n\(stack.description)",
            authorName: stack.authorName,
            authorHandle: stack.authorHandle,
            forkedFromStackId: stack.id,
            createdAt: Date()
        )
    }

    /// All goal tags surfaced by the bundled stacks, sorted alphabetically.
    var allGoalTags: [String] {
        let set = Set(stacks.flatMap(\.goalTags))
        return set.sorted()
    }

    // MARK: - Loading

    private static func loadFromBundle() -> [CommunityStack] {
        guard let url = Bundle.main.url(forResource: "community-stacks", withExtension: "json") else {
            AppLog.database.warning("community-stacks.json not found in bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([CommunityStack].self, from: data)
        } catch {
            AppLog.database.error("Failed to decode community-stacks.json: \(error.localizedDescription, privacy: .public)")
            assertionFailure("Failed to decode community-stacks.json: \(error)")
            return []
        }
    }

    private static func defaultTimes(for count: Int) -> [String] {
        switch max(1, count) {
        case 1: ["8:00 AM"]
        case 2: ["8:00 AM", "8:00 PM"]
        case 3: ["8:00 AM", "1:00 PM", "8:00 PM"]
        // ≥4: spread across the waking window instead of returning
        // N identical "8:00 AM" entries, which would render as
        // overlapping morning slots in the schedule editor.
        default:
            let anchors = ["8:00 AM", "12:00 PM", "4:00 PM", "8:00 PM"]
            return (0..<count).map { anchors[$0 % anchors.count] }
        }
    }

    // MARK: - Test seam

    #if DEBUG
    static func makeForTesting(stacks: [CommunityStack]) -> CommunityStackService {
        CommunityStackService(stacks: stacks)
    }
    #endif
}
