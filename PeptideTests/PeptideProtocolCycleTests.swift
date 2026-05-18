import XCTest
@testable import Peptide

/// Pins the cycle / week math added in audit Library P2.14 — once a
/// user rolls into a second cycle (8-on-4-off, repeated), the bare
/// `weekNumber` is meaningless on its own and the UI needs
/// `cycleNumber` to label "Cycle 2 · Week 3".
@MainActor
final class PeptideProtocolCycleTests: XCTestCase {

    private func makeProtocol(
        startDate: Date,
        cycleLengthWeeks: Int = 8,
        washoutWeeks: Int = 4
    ) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Test",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            startDate: startDate,
            status: .active
        )
    }

    private func date(weeksAgo weeks: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
    }

    // MARK: - cycleNumber

    func test_cycleNumber_isOne_atStart() {
        let proto = makeProtocol(startDate: Date())
        XCTAssertEqual(proto.cycleNumber, 1)
    }

    func test_cycleNumber_isOne_throughFirstFullCycleAndWashout() {
        // 8-week cycle + 4-week washout = 12 calendar weeks per cycle.
        // Week 6 should still be cycle 1, week 11 still cycle 1.
        XCTAssertEqual(makeProtocol(startDate: date(weeksAgo: 6)).cycleNumber, 1)
        XCTAssertEqual(makeProtocol(startDate: date(weeksAgo: 11)).cycleNumber, 1)
    }

    func test_cycleNumber_advancesToTwo_atStartOfSecondCycle() {
        // After 12 full weeks we roll into cycle 2 week 1.
        let proto = makeProtocol(startDate: date(weeksAgo: 12))
        XCTAssertEqual(proto.cycleNumber, 2)
    }

    func test_cycleNumber_handlesProtocolWithoutWashout() {
        // A protocol with no washout simply repeats every
        // `cycleLengthWeeks`. After 9 weeks of an 8-week cycle the
        // user is in cycle 2.
        let proto = makeProtocol(startDate: date(weeksAgo: 9), cycleLengthWeeks: 8, washoutWeeks: 0)
        XCTAssertEqual(proto.cycleNumber, 2)
    }

    func test_cycleNumber_defaultsToOne_forZeroCycleLength() {
        // Defensive — a malformed protocol with no defined cycle
        // shouldn't divide by zero or report a nonsense number.
        let proto = makeProtocol(startDate: date(weeksAgo: 50), cycleLengthWeeks: 0, washoutWeeks: 0)
        XCTAssertEqual(proto.cycleNumber, 1)
    }

    // MARK: - weekNumber wrap

    func test_weekNumber_wrapsIntoCurrentCycle() {
        // 13 weeks in = cycle 2, week 1.
        let proto = makeProtocol(startDate: date(weeksAgo: 13))
        XCTAssertEqual(proto.cycleNumber, 2)
        XCTAssertEqual(proto.weekNumber, 2,
                       "13 calendar weeks elapsed → week 2 of the second cycle (1-indexed)")
    }

    func test_weekNumber_capsAtCycleLength_withinFirstCycle() {
        let proto = makeProtocol(startDate: date(weeksAgo: 6))
        XCTAssertLessThanOrEqual(proto.weekNumber, proto.cycleLengthWeeks)
    }
}
