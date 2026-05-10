import XCTest
@testable import Peptide

@MainActor
final class CycleMilestoneServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var service: CycleMilestoneService!

    override func setUp() {
        super.setUp()
        // Each test gets a fresh, isolated UserDefaults suite so the
        // suppression state can't leak across runs or contaminate the
        // shared CycleMilestoneService.shared singleton.
        let suiteName = "test.cycle.milestone.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        service = CycleMilestoneService(defaults: defaults, calendar: .current)
    }

    override func tearDown() {
        defaults = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Eligibility

    func test_pendingMilestone_emptyProtocols_returnsNil() {
        XCTAssertNil(service.pendingMilestone(in: []))
    }

    func test_pendingMilestone_freshProtocol_returnsNil() {
        let proto = makeProtocol(daysAgo: 0)
        XCTAssertNil(service.pendingMilestone(in: [proto]))
    }

    func test_pendingMilestone_day7Eligible_returnsDay7() {
        let proto = makeProtocol(daysAgo: 7)
        let result = service.pendingMilestone(in: [proto])
        XCTAssertEqual(result?.milestone, .day7)
        XCTAssertEqual(result?.proto.id, proto.id)
    }

    /// Day-30 wins over day-7 once both are eligible — the spec walks
    /// the milestone enum in declared order, so day-7 still surfaces
    /// first unless it has been marked shown.
    func test_pendingMilestone_bothDay7AndDay30Eligible_surfacesDay7First() {
        let proto = makeProtocol(daysAgo: 30)
        XCTAssertEqual(service.pendingMilestone(in: [proto])?.milestone, .day7)
    }

    func test_pendingMilestone_day7AlreadyShown_skipsToDay30() {
        let proto = makeProtocol(daysAgo: 30)
        service.markShown(.day7, for: proto.id)
        XCTAssertEqual(service.pendingMilestone(in: [proto])?.milestone, .day30)
    }

    func test_pendingMilestone_completedProtocol_surfacesCompleted() {
        let proto = makeProtocol(daysAgo: 56, status: .completed)
        service.markShown(.day7, for: proto.id)
        service.markShown(.day30, for: proto.id)
        XCTAssertEqual(service.pendingMilestone(in: [proto])?.milestone, .completed)
    }

    func test_pendingMilestone_pausedProtocol_isSkipped() {
        let proto = makeProtocol(daysAgo: 30, status: .paused)
        XCTAssertNil(service.pendingMilestone(in: [proto]))
    }

    // MARK: - Suppression

    func test_markShown_preventsRePrompt() {
        let proto = makeProtocol(daysAgo: 7)
        XCTAssertNotNil(service.pendingMilestone(in: [proto]))
        service.markShown(.day7, for: proto.id)
        XCTAssertNil(service.pendingMilestone(in: [proto]))
    }

    func test_markShown_isPerProtocol() {
        let a = makeProtocol(daysAgo: 7)
        let b = makeProtocol(daysAgo: 7)
        service.markShown(.day7, for: a.id)
        // a should be suppressed, b should still surface.
        let result = service.pendingMilestone(in: [a, b])
        XCTAssertEqual(result?.proto.id, b.id)
    }

    // MARK: - Ordering

    /// Two protocols both eligible for day-7 — the one with the earlier
    /// startDate wins so the user sees their longest-running cycle's
    /// milestone first.
    func test_pendingMilestone_picksEarliestStartFirst() {
        let earlier = makeProtocol(daysAgo: 14)
        let later = makeProtocol(daysAgo: 7)
        let result = service.pendingMilestone(in: [later, earlier])
        XCTAssertEqual(result?.proto.id, earlier.id)
    }

    // MARK: - Helpers

    private func makeProtocol(daysAgo: Int, status: ProtocolStatus = .active) -> PeptideProtocol {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return PeptideProtocol(
            id: UUID(),
            name: "Test \(daysAgo)d",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: start,
            status: status,
            notes: ""
        )
    }
}
