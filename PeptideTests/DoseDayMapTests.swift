import XCTest
@testable import Peptide

final class DoseDayMapTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var referenceDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 9))!
    }

    private func entry(completed: Bool) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: referenceDay,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    private func marks(for entries: [ProtocolEntry]) -> [CalendarDoseMark] {
        let map = DoseDayMap.build(for: referenceDay, entries: entries, protocols: [], calendar: calendar)
        return map[calendar.startOfDay(for: referenceDay)] ?? []
    }

    func test_build_completedEntry_isLogged() {
        XCTAssertEqual(marks(for: [entry(completed: true)]).map(\.kind), [.logged])
    }

    func test_build_pendingEntry_isScheduledNotLogged() {
        let pending = entry(completed: false)
        let result = marks(for: [pending])
        XCTAssertEqual(result.map(\.kind), [.scheduled])
        XCTAssertEqual(result.first?.entryID, pending.id)
    }
}
