import XCTest
@testable import Peptide

final class DoseLoggedTimeTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func entry(scheduled: Date, completed: Bool = false, actualTime: Date? = nil) -> ProtocolEntry {
        var entry = ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.all[0],
            date: scheduled,
            dose: "250 mcg",
            notes: "",
            completed: completed
        )
        entry.actualTime = actualTime
        return entry
    }

    func test_defaultLoggedTime_lateMorningLogOfEarlyDose_usesNow() {
        let now = at(day: 23, hour: 10, minute: 30)
        XCTAssertEqual(entry(scheduled: at(day: 23, hour: 8)).defaultLoggedTime(now: now, calendar: calendar), now)
    }

    func test_defaultLoggedTime_earlyLogOfEveningDose_isNotInTheFuture() {
        let now = at(day: 23, hour: 19, minute: 30)
        XCTAssertEqual(entry(scheduled: at(day: 23, hour: 22)).defaultLoggedTime(now: now, calendar: calendar), now)
    }

    func test_defaultLoggedTime_editOfTakenDose_keepsRecordedTime() {
        let recorded = at(day: 23, hour: 8, minute: 12)
        let taken = entry(scheduled: at(day: 23, hour: 8), completed: true, actualTime: recorded)
        XCTAssertEqual(taken.defaultLoggedTime(now: at(day: 23, hour: 12), calendar: calendar), recorded)
    }

    func test_defaultLoggedTime_pastDayDose_keepsScheduledTime() {
        let scheduled = at(day: 21, hour: 8)
        XCTAssertEqual(entry(scheduled: scheduled).defaultLoggedTime(now: at(day: 23, hour: 9), calendar: calendar), scheduled)
    }
}
