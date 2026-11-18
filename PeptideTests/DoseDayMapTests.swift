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

    private func entry(completed: Bool, dose: String = "250mcg", date: Date? = nil) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: date ?? referenceDay,
            dose: dose,
            notes: "",
            completed: completed
        )
    }

    private func marks(for entries: [ProtocolEntry]) -> [CalendarDoseMark] {
        let map = DoseDayMap.build(
            for: referenceDay, entries: entries, protocols: [], today: referenceDay, calendar: calendar
        )
        return map[calendar.startOfDay(for: referenceDay)] ?? []
    }

    private func day(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: referenceDay))!
    }

    /// Active every day since a week before the reference day.
    private func dailyProtocol(times: [String]) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Daily",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: times.count, preferredTimes: times),
            cycleLengthWeeks: 8,
            startDate: day(offset: -7),
            status: .active,
            notes: ""
        )
    }

    private func scheduleMap(times: [String] = ["8:00 AM"]) -> [Date: [CalendarDoseMark]] {
        DoseDayMap.build(
            for: referenceDay, entries: [], protocols: [dailyProtocol(times: times)],
            today: referenceDay, calendar: calendar
        )
    }

    func test_build_pendingEntryOnPastDay_isMissed() {
        let past = entry(completed: false, date: day(offset: -2))
        let map = DoseDayMap.build(
            for: referenceDay, entries: [past], protocols: [], today: referenceDay, calendar: calendar
        )
        XCTAssertEqual(map[day(offset: -2)]?.map(\.kind), [.missed])
    }

    func test_build_pastScheduledDayWithoutEntry_isMissed() {
        XCTAssertEqual(scheduleMap()[day(offset: -1)]?.map(\.kind), [.missed])
    }

    func test_build_todayAndFutureWithoutEntry_areScheduled() {
        let map = scheduleMap()
        XCTAssertEqual(map[day(offset: 0)]?.map(\.kind), [.scheduled])
        XCTAssertEqual(map[day(offset: 1)]?.map(\.kind), [.scheduled])
    }

    func test_build_twiceDailySchedule_emitsOneMarkPerTime() {
        let marks = scheduleMap(times: ["8:00 AM", "8:00 PM"])[day(offset: 1)] ?? []
        XCTAssertEqual(marks.map(\.time), ["8:00 AM", "8:00 PM"])
        XCTAssertEqual(Set(marks.map(\.id)).count, 2)
    }

    func test_build_mark_carriesPeptideCategory() {
        XCTAssertEqual(marks(for: [entry(completed: true)]).first?.peptideCategory, MockPeptides.bpc157.category)
        XCTAssertEqual(scheduleMap()[day(offset: 1)]?.first?.peptideCategory, MockPeptides.bpc157.category)
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
