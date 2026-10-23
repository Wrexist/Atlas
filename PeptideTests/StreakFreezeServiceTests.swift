import XCTest
@testable import Peptide

final class StreakFreezeServiceTests: XCTestCase {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    func test_dayKey_utcPlus2_returnsLocalCalendarDate() {
        let stockholm = calendar("Europe/Stockholm")
        let justAfterMidnight = stockholm.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 0, minute: 30))!
        XCTAssertEqual(StreakFreezeService.dayKey(for: justAfterMidnight, calendar: stockholm), "20261023")
    }

    func test_dayKey_afterTravel_stillNamesTheSameLocalDay() {
        let newYork = calendar("America/New_York")
        let lateEvening = newYork.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23))!
        XCTAssertEqual(StreakFreezeService.dayKey(for: lateEvening, calendar: newYork), "20261023")
    }

    func test_migratingLegacyKeys_eastOfUTC_movesToTheLocalDay() {
        // Old builds stored 23 Oct in Stockholm as the GMT date of local
        // midnight: 22 Oct.
        let migrated = StreakFreezeService.migratingLegacyKeys(["2026-10-22"], calendar: calendar("Europe/Stockholm"))
        XCTAssertEqual(migrated, ["20261023"])
    }

    func test_migratingLegacyKeys_westOfUTC_keepsTheDate() {
        let migrated = StreakFreezeService.migratingLegacyKeys(["2026-10-23"], calendar: calendar("America/Los_Angeles"))
        XCTAssertEqual(migrated, ["20261023"])
    }

    func test_migratingLegacyKeys_currentKeys_areUnchanged() {
        let stockholm = calendar("Europe/Stockholm")
        let once = StreakFreezeService.migratingLegacyKeys(["2026-10-22", "20261001"], calendar: stockholm)
        XCTAssertEqual(once, ["20261023", "20261001"])
        XCTAssertEqual(StreakFreezeService.migratingLegacyKeys(once, calendar: stockholm), once)
    }

    func test_applyFreeze_lastDayOfPreviousMonthWithBudgetUsed_returnsFalse() {
        let utc = calendar("UTC")
        var profile = UserProfile.fresh
        let octoberTenth = utc.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        let octoberLast = utc.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        profile.streakFreezeDays.insert(StreakFreezeService.dayKey(for: octoberTenth, calendar: utc))

        XCTAssertFalse(StreakFreezeService.applyFreeze(in: &profile, for: octoberLast, calendar: utc))
    }

    func test_applyFreeze_lastDayOfPreviousMonth_spendsThatMonthsFreeze() {
        let utc = calendar("UTC")
        var profile = UserProfile.fresh
        let octoberLast = utc.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        let novemberFirst = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!

        XCTAssertTrue(StreakFreezeService.applyFreeze(in: &profile, for: octoberLast, calendar: utc))
        XCTAssertEqual(StreakFreezeService.usedThisMonth(in: profile, now: octoberLast, calendar: utc), 1)
        XCTAssertTrue(StreakFreezeService.hasFreezeAvailable(in: profile, now: novemberFirst, calendar: utc))
    }
}
