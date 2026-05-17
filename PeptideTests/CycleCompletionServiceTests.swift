import XCTest
@testable import Peptide

@MainActor
final class CycleCompletionServiceTests: XCTestCase {

    private var service: CycleCompletionService!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        // Suite-scoped UserDefaults so the in-process suppression
        // state doesn't bleed across tests via the standard store.
        defaults = UserDefaults(suiteName: "test.cycleCompletion.\(UUID().uuidString)")
        service = CycleCompletionService(defaults: defaults, calendar: .current)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
        defaults = nil
        service = nil
        try await super.tearDown()
    }

    // MARK: - Detection

    func test_pendingCompletion_protocolBeforeCycleEnd_returnsNil() {
        let proto = makeProtocol(weeksAgo: 2, cycleLengthWeeks: 8)
        XCTAssertNil(service.pendingCompletion(in: [proto]))
    }

    func test_pendingCompletion_protocolPastCycleEnd_returnsIt() {
        let proto = makeProtocol(weeksAgo: 10, cycleLengthWeeks: 8)
        XCTAssertEqual(service.pendingCompletion(in: [proto])?.id, proto.id)
    }

    func test_pendingCompletion_pausedProtocol_isIgnored() {
        let proto = makeProtocol(weeksAgo: 10, cycleLengthWeeks: 8, status: .paused)
        XCTAssertNil(service.pendingCompletion(in: [proto]))
    }

    func test_pendingCompletion_completedProtocol_isIgnored() {
        let proto = makeProtocol(weeksAgo: 10, cycleLengthWeeks: 8, status: .completed)
        XCTAssertNil(service.pendingCompletion(in: [proto]))
    }

    func test_pendingCompletion_earliestStartDateFirst() {
        let oldest = makeProtocol(weeksAgo: 12, cycleLengthWeeks: 4)
        let newer = makeProtocol(weeksAgo: 6, cycleLengthWeeks: 4)
        let result = service.pendingCompletion(in: [newer, oldest])
        XCTAssertEqual(result?.id, oldest.id,
                       "When multiple protocols are past cycle end, the earliest start wins")
    }

    // MARK: - Auto-completion sweep

    func test_protocolsDueForAutoCompletion_pastGracePeriod() {
        let proto = makeProtocol(weeksAgo: 9, cycleLengthWeeks: 8)
        // 9 weeks since start, 8-week cycle → 1 week past end →
        // exactly at the 7-day grace boundary.
        let due = service.protocolsDueForAutoCompletion(in: [proto])
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.id, proto.id)
    }

    func test_protocolsDueForAutoCompletion_dismissThreshold() {
        let proto = makeProtocol(weeksAgo: 8, cycleLengthWeeks: 8)
        // Exactly at cycle end — 0 days past, no grace yet.
        XCTAssertTrue(service.protocolsDueForAutoCompletion(in: [proto]).isEmpty)

        // Three dismissals trips the auto-complete threshold.
        service.recordDismissal(for: proto)
        service.recordDismissal(for: proto)
        service.recordDismissal(for: proto)
        let due = service.protocolsDueForAutoCompletion(in: [proto])
        XCTAssertEqual(due.count, 1, "Three dismissals should trigger auto-completion")
    }

    func test_markAutoCompleted_suppressesPrompt() {
        let proto = makeProtocol(weeksAgo: 10, cycleLengthWeeks: 8)
        XCTAssertEqual(service.pendingCompletion(in: [proto])?.id, proto.id)
        service.markAutoCompleted(proto)
        XCTAssertNil(service.pendingCompletion(in: [proto]),
                     "Once auto-completed, the prompt must not re-fire for this cycle")
    }

    func test_restartWithSameID_resetsSuppression() {
        // A user who marks-complete + then restarts the same protocol
        // (same UUID, new startDate) should get fresh prompts when the
        // new cycle ends, just like CycleMilestoneService.
        let id = UUID()
        let firstCycle = PeptideProtocol(
            id: id, name: "Restart", peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1,2,3,4,5,6,7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date()) ?? Date(),
            status: .active, notes: ""
        )
        service.markAutoCompleted(firstCycle)
        // Restart at a fresh startDate
        let restarted = PeptideProtocol(
            id: id, name: "Restart", peptides: [],
            schedule: firstCycle.schedule,
            cycleLengthWeeks: 8,
            startDate: Calendar.current.date(byAdding: .weekOfYear, value: -10, to: Date()) ?? Date(),
            status: .active, notes: ""
        )
        XCTAssertEqual(service.pendingCompletion(in: [restarted])?.id, id,
                       "A restarted cycle (new startDate) should re-fire its completion prompt")
    }

    // MARK: - Edge cases

    func test_cycleLengthZero_clampsViaSafeCycleLengthWeeks() {
        // Defensive: cycleLengthWeeks should never be 0 per
        // safeCycleLengthWeeks, but if it is, the service should still
        // produce sensible answers (treat 0 as 1).
        let proto = makeProtocol(weeksAgo: 2, cycleLengthWeeks: 0)
        // 2 weeks past start with safe cycle = 1 week → past end.
        XCTAssertEqual(service.pendingCompletion(in: [proto])?.id, proto.id)
    }

    // MARK: - Helpers

    private func makeProtocol(
        weeksAgo: Int,
        cycleLengthWeeks: Int,
        status: ProtocolStatus = .active
    ) -> PeptideProtocol {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date()) ?? Date()
        return PeptideProtocol(
            id: UUID(),
            name: "Cycle \(weeksAgo)w-ago",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1,2,3,4,5,6,7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: cycleLengthWeeks,
            startDate: start,
            status: status,
            notes: ""
        )
    }
}
