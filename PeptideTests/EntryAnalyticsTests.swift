import XCTest
@testable import Peptide

final class EntryAnalyticsTests: XCTestCase {

    private let calendar = Calendar(identifier: .iso8601)

    /// 09:00 on Wednesday Jan 7 2026 — the "now" every test pins to.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 9))!
    }

    private func entry(hoursFromNow: Double, completed: Bool) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: now.addingTimeInterval(hoursFromNow * 3600),
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    private func fraction(_ entries: [ProtocolEntry]) -> Double? {
        EntryAnalytics.weeklyComplianceFraction(in: entries, now: now, calendar: calendar)
    }

    func test_weeklyCompliance_doseLaterToday_isNotCountedAsMissed() {
        let entries = [
            entry(hoursFromNow: -1, completed: true),
            entry(hoursFromNow: 11, completed: false)
        ]
        XCTAssertEqual(fraction(entries), 1)
    }

    func test_weeklyCompliance_noDosesDueInWindow_returnsNil() {
        let entries = [
            entry(hoursFromNow: -24 * 30, completed: true),
            entry(hoursFromNow: 2, completed: false)
        ]
        XCTAssertNil(fraction(entries))
    }

    func test_weeklyCompliance_entryExactlySevenDaysAgo_isInWindow() {
        let entries = [
            entry(hoursFromNow: -24 * 7, completed: false),
            entry(hoursFromNow: -1, completed: true)
        ]
        XCTAssertEqual(fraction(entries), 0.5)
    }

    func test_weeklyCompliance_entryJustOverSevenDaysAgo_isExcluded() {
        let entries = [
            entry(hoursFromNow: -24 * 7 - 1, completed: false),
            entry(hoursFromNow: -1, completed: true)
        ]
        XCTAssertEqual(fraction(entries), 1)
    }
}
