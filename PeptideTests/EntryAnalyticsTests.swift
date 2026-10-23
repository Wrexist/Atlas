import XCTest
@testable import Peptide

final class EntryAnalyticsTests: XCTestCase {

    private let calendar = Calendar(identifier: .iso8601)

    /// 09:00 on Wednesday Jan 7 2026 — the "now" every test pins to.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 9))!
    }

    private func daily(startedDaysAgo: Int, cycleWeeks: Int = 8, washoutWeeks: Int = 0) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Daily",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: cycleWeeks,
            washoutWeeks: washoutWeeks,
            startDate: calendar.date(byAdding: .day, value: -startedDaysAgo, to: calendar.startOfDay(for: now))!,
            status: .active,
            notes: ""
        )
    }

    private func entry(_ proto: PeptideProtocol, hoursFromNow: Double, completed: Bool) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: proto.id,
            peptide: MockPeptides.bpc157,
            date: now.addingTimeInterval(hoursFromNow * 3600),
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    private func fraction(_ entries: [ProtocolEntry], _ protocols: [PeptideProtocol]) -> Double? {
        EntryAnalytics.weeklyComplianceFraction(in: entries, protocols: protocols, now: now, calendar: calendar)
    }

    func test_weeklyCompliance_doseLaterToday_isNotCountedAsMissed() {
        let proto = daily(startedDaysAgo: 0)
        let entries = [
            entry(proto, hoursFromNow: -1, completed: true),
            entry(proto, hoursFromNow: 11, completed: false)
        ]
        XCTAssertEqual(fraction(entries, [proto]), 1)
    }

    func test_weeklyCompliance_noDosesDueInWindow_returnsNil() {
        let proto = daily(startedDaysAgo: 0)
        XCTAssertNil(fraction([entry(proto, hoursFromNow: 2, completed: false)], [proto]))
    }

    func test_weeklyCompliance_scheduledDayWithNoEntries_countsAsMissed() {
        // Jan 5 was scheduled but the app never generated its entry.
        let proto = daily(startedDaysAgo: 2)
        let entries = [
            entry(proto, hoursFromNow: -25, completed: true),
            entry(proto, hoursFromNow: -1, completed: true)
        ]
        XCTAssertEqual(fraction(entries, [proto])!, 2.0 / 3.0, accuracy: 0.0001)
    }

    func test_weeklyCompliance_washoutDays_haveNothingDue() {
        // One week on, one week off, started 14 days ago: Jan 1–6 are
        // wash-out and today opens cycle 2.
        let proto = daily(startedDaysAgo: 14, cycleWeeks: 1, washoutWeeks: 1)
        XCTAssertEqual(fraction([entry(proto, hoursFromNow: -1, completed: true)], [proto]), 1)
    }

    func test_weeklyCompliance_poolsDosesAcrossProtocols() {
        let first = daily(startedDaysAgo: 0)
        let second = daily(startedDaysAgo: 0)
        let entries = [
            entry(first, hoursFromNow: -1, completed: true),
            entry(second, hoursFromNow: -1, completed: false)
        ]
        XCTAssertEqual(fraction(entries, [first, second]), 0.5)
    }
}
