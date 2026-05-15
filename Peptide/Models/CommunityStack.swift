import Foundation

/// A curated, shareable peptide stack with author attribution.
/// Backed by `community-stacks.json` shipped in the app bundle. Read-only
/// today — user-published stacks are deferred to a future backend release.
struct CommunityStack: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let authorName: String
    let authorHandle: String?
    let authorTitle: String?
    let description: String
    let goalTags: [String]
    let peptideAbbreviations: [String]
    let cycleLengthWeeks: Int
    let scheduleDaysOfWeek: [Int]
    let scheduleTimesPerDay: Int
    let popularityScore: Int
    let featured: Bool
}
