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

    // MARK: - Last injection site

    private func logged(scheduled: Date, site: String?, actualTime: Date? = nil) -> ProtocolEntry {
        var result = entry(scheduled: scheduled, completed: true, actualTime: actualTime)
        result.injectionSite = site
        return result
    }

    func test_lastInjectionSite_severalLoggedSites_returnsMostRecentlyTaken() {
        let pending = entry(scheduled: at(day: 23, hour: 20))
        let history = [
            logged(scheduled: at(day: 21, hour: 8), site: InjectionSite.leftAbdomen.rawValue),
            // Scheduled earlier but actually taken last.
            logged(scheduled: at(day: 22, hour: 8), site: InjectionSite.rightThigh.rawValue, actualTime: at(day: 23, hour: 9)),
            logged(scheduled: at(day: 22, hour: 20), site: InjectionSite.leftGlute.rawValue),
            pending,
        ]
        XCTAssertEqual(
            pending.lastInjectionSite(in: history, now: at(day: 23, hour: 12)),
            InjectionSite.rightThigh.rawValue
        )
    }

    func test_lastInjectionSite_ignoresTheDoseBeingEditedAndFutureEntries() {
        let editing = logged(scheduled: at(day: 23, hour: 8), site: InjectionSite.leftDeltoid.rawValue)
        let history = [
            logged(scheduled: at(day: 22, hour: 8), site: InjectionSite.rightAbdomen.rawValue),
            editing,
            logged(scheduled: at(day: 24, hour: 8), site: InjectionSite.leftThigh.rawValue),
        ]
        XCTAssertEqual(
            editing.lastInjectionSite(in: history, now: at(day: 23, hour: 12)),
            InjectionSite.rightAbdomen.rawValue
        )
    }

    func test_lastInjectionSite_uncheckedDoseWithSite_isIgnored() {
        let pending = entry(scheduled: at(day: 23, hour: 20))
        var unchecked = logged(scheduled: at(day: 23, hour: 8), site: InjectionSite.leftThigh.rawValue)
        unchecked.completed = false
        let history = [
            logged(scheduled: at(day: 22, hour: 8), site: InjectionSite.rightAbdomen.rawValue),
            unchecked,
            pending,
        ]
        XCTAssertEqual(
            pending.lastInjectionSite(in: history, now: at(day: 23, hour: 12)),
            InjectionSite.rightAbdomen.rawValue
        )
    }

    func test_lastInjectionSite_noSiteEverLogged_isNil() {
        let pending = entry(scheduled: at(day: 23, hour: 8))
        let history = [logged(scheduled: at(day: 22, hour: 8), site: nil), pending]
        XCTAssertNil(pending.lastInjectionSite(in: history, now: at(day: 23, hour: 12)))
    }
}
