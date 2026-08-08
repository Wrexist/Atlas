import XCTest
@testable import Peptide

final class SmartCyclePlannerTests: XCTestCase {

    // MARK: - Wrapping-up

    func test_wrappingUp_surfacesInLastFiveDays() {
        let proto = makeProtocol(daysAgo: 8 * 7 - 3, weeks: 8) // ~3 days remaining
        let result = SmartCyclePlanner.suggestions(protocols: [proto], entries: [])
        XCTAssertTrue(result.contains { if case .cycleWrappingUp = $0.kind { return true } else { return false } })
    }

    func test_wrappingUp_doesNotFireMidCycle() {
        let proto = makeProtocol(daysAgo: 14, weeks: 8) // 6 weeks remaining
        let result = SmartCyclePlanner.suggestions(protocols: [proto], entries: [])
        XCTAssertFalse(result.contains { if case .cycleWrappingUp = $0.kind { return true } else { return false } })
    }

    // MARK: - Idle / pause

    func test_idle_recommendsPauseAfterSevenDryDays() {
        let proto = makeProtocol(daysAgo: 30, weeks: 12)
        // No completed entries in the last 7 days.
        let result = SmartCyclePlanner.suggestions(protocols: [proto], entries: [])
        XCTAssertTrue(result.contains { if case .considerPausing = $0.kind { return true } else { return false } })
    }

    func test_idle_doesNotFireWhenRecentEntriesExist() {
        let proto = makeProtocol(daysAgo: 30, weeks: 12)
        let entries = [
            entry(for: proto, daysAgo: 1, completed: true),
            entry(for: proto, daysAgo: 3, completed: true),
        ]
        let result = SmartCyclePlanner.suggestions(protocols: [proto], entries: entries)
        XCTAssertFalse(result.contains { if case .considerPausing = $0.kind { return true } else { return false } })
    }

    // MARK: - Decaying compliance

    func test_decayingCompliance_recommendsShorterCycle() {
        // 50 days into a 56-day cycle, so the cycle's midpoint (day 28,
        // i.e. 22 days ago) is safely in the past.
        //
        // This used to start the protocol 28 days ago and was asserting
        // something the engine cannot produce: the engine splits on the
        // *cycle's* midpoint, and for an 8-week cycle begun 28 days ago
        // that midpoint is today — every entry landed in the first half,
        // the second half was empty, and the `secondHalf.count >= 10`
        // guard correctly returned nil. The rule needs a cycle that has
        // actually entered its second half, not one standing on the line.
        let proto = makeProtocol(daysAgo: 50, weeks: 8)
        // First half (days 40-49 ago): 10 entries, all completed.
        // Second half (days 12-21 ago): 10 entries, only 4 completed.
        var entries: [ProtocolEntry] = []
        for i in 0..<10 {
            entries.append(entry(for: proto, daysAgo: 49 - i, completed: true))
        }
        for i in 0..<10 {
            entries.append(entry(for: proto, daysAgo: 21 - i, completed: i < 4))
        }
        let result = SmartCyclePlanner.suggestions(protocols: [proto], entries: entries)
        XCTAssertTrue(result.contains {
            if case .shortenNextCycle(let cur, let suggested) = $0.kind {
                return cur == 8 && suggested == 6
            }
            return false
        })
    }

    // MARK: - Off-cycle ready

    func test_offCycle_surfacesOncePastRestWindow() {
        // 8-week cycle that ended 5 weeks ago — well past the 4-week
        // (50%) recommended rest window.
        let proto = makeProtocol(
            daysAgo: 8 * 7 + 5 * 7,
            weeks: 8,
            status: .completed
        )
        let result = SmartCyclePlanner.suggestions(protocols: [proto], entries: [])
        XCTAssertTrue(result.contains { if case .offCycleReady = $0.kind { return true } else { return false } })
    }

    // MARK: - Confidence ordering

    func test_suggestions_areOrderedByConfidence() {
        // Two protocols: one wrapping up tomorrow (high), one idle 8d (medium)
        let highSignal = makeProtocol(daysAgo: 8 * 7 - 1, weeks: 8)
        let mediumSignal = makeProtocol(daysAgo: 30, weeks: 12)
        let result = SmartCyclePlanner.suggestions(
            protocols: [mediumSignal, highSignal],
            entries: []
        )
        guard result.count >= 2 else {
            return XCTFail("expected at least two suggestions")
        }
        XCTAssertGreaterThanOrEqual(result[0].confidence.rawValue, result[1].confidence.rawValue)
    }

    // MARK: - Helpers

    private func makeProtocol(
        daysAgo: Int,
        weeks: Int,
        status: ProtocolStatus = .active
    ) -> PeptideProtocol {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return PeptideProtocol(
            id: UUID(),
            name: "Test \(weeks)w",
            peptides: [],
            schedule: ProtocolSchedule(
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                timesPerDay: 1,
                preferredTimes: ["8:00 AM"]
            ),
            cycleLengthWeeks: weeks,
            startDate: start,
            status: status,
            notes: ""
        )
    }

    private func entry(
        for proto: PeptideProtocol,
        daysAgo: Int,
        completed: Bool
    ) -> ProtocolEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let peptide = Peptide(
            name: "Test",
            abbreviation: "TST",
            category: .recovery,
            description: "",
            benefits: [],
            dosageRange: "",
            frequency: "",
            halfLife: "",
            adminRoute: "",
            researchLinks: [],
            imageSystemName: "flask.fill"
        )
        return ProtocolEntry(
            id: UUID(),
            protocolId: proto.id,
            peptide: peptide,
            date: date,
            dose: "1 mg",
            notes: "",
            completed: completed
        )
    }
}
