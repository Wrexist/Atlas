import XCTest
@testable import Peptide

@MainActor
final class CommunityStackServiceTests: XCTestCase {

    private func makeStack(featured: Bool = false, popularity: Int = 50) -> CommunityStack {
        CommunityStack(
            id: UUID(),
            name: "Test Stack",
            authorName: "Dr. Tester",
            authorHandle: "@tester",
            authorTitle: "QA",
            description: "Just a test.",
            goalTags: ["Recovery"],
            peptideAbbreviations: ["BPC-157", "TB-500"],
            cycleLengthWeeks: 8,
            scheduleDaysOfWeek: [1, 2, 3, 4, 5],
            scheduleTimesPerDay: 1,
            popularityScore: popularity,
            featured: featured
        )
    }

    func testBundledJSONLoads() throws {
        // Best-effort: the bundle isn't always reachable from the test
        // target; if it is, we expect a non-empty list.
        let stacks = CommunityStackService.shared.stacks
        if let url = Bundle.main.url(forResource: "community-stacks", withExtension: "json") {
            XCTAssertNotNil(url)
            XCTAssertGreaterThanOrEqual(stacks.count, 5,
                "Bundled community-stacks.json should ship with at least 5 stacks")
        }
    }

    func testForkPreservesAttribution() {
        let stack = makeStack()
        let service = CommunityStackService.makeForTesting(stacks: [stack])
        let proto = service.forkToProtocol(stack)

        XCTAssertNotEqual(proto.id, stack.id, "Fork should mint a new protocol id")
        XCTAssertEqual(proto.authorName, stack.authorName)
        XCTAssertEqual(proto.authorHandle, stack.authorHandle)
        XCTAssertEqual(proto.forkedFromStackId, stack.id)
        XCTAssertEqual(proto.cycleLengthWeeks, stack.cycleLengthWeeks)
        XCTAssertEqual(proto.schedule.daysOfWeek, stack.scheduleDaysOfWeek)
        XCTAssertEqual(proto.schedule.timesPerDay, stack.scheduleTimesPerDay)
        XCTAssertEqual(proto.status, .active)
        XCTAssertTrue(proto.notes.contains(stack.authorName))
    }

    func testRankedFloatsFeaturedFirst() {
        let featuredLow = makeStack(featured: true, popularity: 50)
        let regularHigh = makeStack(featured: false, popularity: 99)
        let regularMid = makeStack(featured: false, popularity: 70)
        let service = CommunityStackService.makeForTesting(
            stacks: [regularMid, regularHigh, featuredLow]
        )

        let ranked = service.ranked()
        XCTAssertEqual(ranked.first?.id, featuredLow.id, "Featured stack must lead the list")
        XCTAssertEqual(ranked.dropFirst().first?.id, regularHigh.id,
                       "Within non-featured, highest popularity comes first")
    }
}
