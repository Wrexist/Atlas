import XCTest
@testable import Peptide

/// Pins `PeptideProtocol.adherence(entries:days:now:calendar:)`: entries
/// only exist for days the app was opened, so the due count has to come
/// from the schedule or skipped days silently read as 100%.
final class ProtocolAdherenceTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Wednesday 14 Jan 2026, 20:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 14, hour: 20))!
    }

    private func makeProtocol(startDaysAgo: Int, cycleLengthWeeks: Int = 8, washoutWeeks: Int = 0) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Test",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
            startDate: calendar.date(byAdding: .day, value: -startDaysAgo, to: now)!,
            status: .active,
            notes: ""
        )
    }

    private func entry(for proto: PeptideProtocol, daysAgo: Int, hour: Int = 8, completed: Bool) -> ProtocolEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return ProtocolEntry(
            id: UUID(),
            protocolId: proto.id,
            peptide: MockPeptides.bpc157,
            date: day.addingTimeInterval(TimeInterval(hour * 3600)),
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    func test_adherence_daysTheAppWasNotOpened_countAsMissed() {
        let proto = makeProtocol(startDaysAgo: 4)
        let entries = [
            entry(for: proto, daysAgo: 4, completed: true),
            entry(for: proto, daysAgo: 2, completed: true),
            entry(for: proto, daysAgo: 0, completed: true)
        ]

        let ratio = proto.adherence(entries: entries, days: 14, now: now, calendar: calendar)

        XCTAssertEqual(ratio ?? -1, 3.0 / 5.0, accuracy: 0.0001)
    }

    func test_adherence_todaysDoseNotYetDue_isNotAMiss() {
        let proto = makeProtocol(startDaysAgo: 0)
        let entries = [entry(for: proto, daysAgo: 0, hour: 21, completed: false)]

        XCTAssertNil(proto.adherence(entries: entries, days: 14, now: now, calendar: calendar))
    }

    func test_adherence_window_ignoresDaysBeforeItStarts() {
        let proto = makeProtocol(startDaysAgo: 30)
        let entries = (0..<14).map { entry(for: proto, daysAgo: $0, completed: true) }

        let ratio = proto.adherence(entries: entries, days: 14, now: now, calendar: calendar)

        XCTAssertEqual(ratio ?? -1, 1.0, accuracy: 0.0001)
    }

    func test_adherence_unopenedWashoutDays_areNotMissed() {
        let proto = makeProtocol(startDaysAgo: 13, cycleLengthWeeks: 1, washoutWeeks: 1)
        let entries = (7...13).map { entry(for: proto, daysAgo: $0, completed: true) }

        let ratio = proto.adherence(entries: entries, days: 14, now: now, calendar: calendar)

        XCTAssertEqual(ratio ?? -1, 1.0, accuracy: 0.0001)
    }
}
