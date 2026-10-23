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

    private func entry(completed: Bool, dose: String = "250mcg") -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: referenceDay,
            dose: dose,
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

    func test_build_entryWithoutDose_showsDoseNotSet() {
        let result = marks(for: [entry(completed: false, dose: "")])
        XCTAssertEqual(result.first?.dose, String(localized: "Dose not set"))
    }

    func test_build_entryWithActualTime_showsActualTime() {
        var logged = entry(completed: true)
        let takenAt = referenceDay.addingTimeInterval(100 * 60)
        logged.actualTime = takenAt
        XCTAssertEqual(marks(for: [logged]).first?.time, takenAt.formatted(.dateTime.hour().minute()))
    }

    func test_build_duplicateProtocolIDs_doesNotTrapAndKeepsFirstStatus() {
        // CloudKit can sync two rows for one protocol id.
        let logged = entry(completed: true)
        let paused = PeptideProtocol(
            id: logged.protocolId,
            name: "Synced twice",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: referenceDay,
            status: .paused,
            notes: ""
        )
        var twin = paused
        twin.status = .active

        let map = DoseDayMap.build(
            for: referenceDay, entries: [logged], protocols: [paused, twin], calendar: calendar
        )

        XCTAssertEqual(map[calendar.startOfDay(for: referenceDay)]?.first?.protocolStatus, .paused)
    }
}
