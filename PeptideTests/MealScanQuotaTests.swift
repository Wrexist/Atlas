import XCTest
@testable import Peptide

final class MealScanQuotaTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - remaining(count:isPro:)

    func test_remaining_freshWeek_returnsFullAllowance() {
        XCTAssertEqual(MealScanQuota.remaining(count: 0, isPro: false), 3)
    }

    func test_remaining_afterTwoScans_returnsOne() {
        XCTAssertEqual(MealScanQuota.remaining(count: 2, isPro: false), 1)
    }

    func test_remaining_overTheCap_clampsToZero() {
        XCTAssertEqual(MealScanQuota.remaining(count: 3, isPro: false), 0)
        XCTAssertEqual(MealScanQuota.remaining(count: 9, isPro: false), 0)
    }

    func test_remaining_pro_isUnlimited() {
        XCTAssertNil(MealScanQuota.remaining(count: 0, isPro: true))
        XCTAssertNil(MealScanQuota.remaining(count: 50, isPro: true))
    }

    // MARK: - weekKey(for:calendar:)

    func test_weekKey_sunday_belongsToWeekStartingMonday() {
        // Sunday 27 Sep 2026 closes ISO week 39 (Mon 21 – Sun 27).
        XCTAssertEqual(MealScanQuota.weekKey(for: date(2026, 9, 27, in: utc), calendar: utc), "mealScanCount-2026-W39")
        XCTAssertEqual(MealScanQuota.weekKey(for: date(2026, 9, 21, in: utc), calendar: utc), "mealScanCount-2026-W39")
    }

    func test_weekKey_mondayMidnight_rollsToNextWeek() {
        let sundayNight = utc.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 23, minute: 59))!
        let mondayMorning = utc.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 0, minute: 0))!
        XCTAssertEqual(MealScanQuota.weekKey(for: sundayNight, calendar: utc), "mealScanCount-2026-W39")
        XCTAssertEqual(MealScanQuota.weekKey(for: mondayMorning, calendar: utc), "mealScanCount-2026-W40")
    }

    func test_weekKey_sundayFirstLocale_stillRollsOnMonday() {
        var usCalendar = utc
        usCalendar.firstWeekday = 1
        XCTAssertEqual(
            MealScanQuota.weekKey(for: date(2026, 9, 27, in: usCalendar), calendar: usCalendar),
            MealScanQuota.weekKey(for: date(2026, 9, 26, in: usCalendar), calendar: usCalendar)
        )
    }

    func test_weekKey_earlyJanuary_belongsToPreviousYearsLastWeek() {
        // 2026 has 53 ISO weeks: Fri 1 Jan 2027 is still 2026-W53.
        XCTAssertEqual(MealScanQuota.weekKey(for: date(2027, 1, 1, in: utc), calendar: utc), "mealScanCount-2026-W53")
        XCTAssertEqual(MealScanQuota.weekKey(for: date(2027, 1, 4, in: utc), calendar: utc), "mealScanCount-2027-W01")
    }

    func test_weekKey_lateDecember_belongsToNextYearsFirstWeek() {
        // Mon 30 Dec 2024 opens ISO week 2025-W01.
        XCTAssertEqual(MealScanQuota.weekKey(for: date(2024, 12, 30, in: utc), calendar: utc), "mealScanCount-2025-W01")
    }

    func test_weekKey_usesTheCalendarsTimeZone() {
        // 23:30 Sunday in Los Angeles is already Monday in UTC.
        var la = utc
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let sundayLateInLA = la.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 23, minute: 30))!
        XCTAssertEqual(MealScanQuota.weekKey(for: sundayLateInLA, calendar: la), "mealScanCount-2026-W39")
        XCTAssertEqual(MealScanQuota.weekKey(for: sundayLateInLA, calendar: utc), "mealScanCount-2026-W40")
    }

    // MARK: - Persistence

    func test_recordSuccessfulScan_countsWithinWeek_andResetsNextWeek() {
        let suite = "MealScanQuotaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wednesday = date(2026, 9, 23, in: utc)
        let nextMonday = date(2026, 9, 28, in: utc)

        MealScanQuota.recordSuccessfulScan(on: wednesday, calendar: utc, defaults: defaults)
        MealScanQuota.recordSuccessfulScan(on: wednesday, calendar: utc, defaults: defaults)

        XCTAssertEqual(MealScanQuota.remainingThisWeek(isPro: false, on: wednesday, calendar: utc, defaults: defaults), 1)
        XCTAssertEqual(MealScanQuota.remainingThisWeek(isPro: false, on: nextMonday, calendar: utc, defaults: defaults), 3)
    }

    func test_recordAllowanceExhausted_spendsTheWeek_butNeverLowersTheCount() {
        let suite = "MealScanQuotaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let wednesday = date(2026, 9, 23, in: utc)

        MealScanQuota.recordAllowanceExhausted(on: wednesday, calendar: utc, defaults: defaults)
        XCTAssertEqual(MealScanQuota.remainingThisWeek(isPro: false, on: wednesday, calendar: utc, defaults: defaults), 0)

        for _ in 0..<5 { MealScanQuota.recordSuccessfulScan(on: wednesday, calendar: utc, defaults: defaults) }
        MealScanQuota.recordAllowanceExhausted(on: wednesday, calendar: utc, defaults: defaults)
        XCTAssertEqual(MealScanQuota.count(on: wednesday, calendar: utc, defaults: defaults), 8)
    }

    // MARK: - Proxy headers

    func test_weekID_matchesTheStorageKeyWithoutItsPrefix() {
        let sunday = date(2026, 9, 27, in: utc)
        XCTAssertEqual(MealScanQuota.weekID(for: sunday, calendar: utc), "2026-W39")
        XCTAssertEqual(MealScanQuota.weekKey(for: sunday, calendar: utc), "mealScanCount-" + MealScanQuota.weekID(for: sunday, calendar: utc))
    }

    func test_serverHeaders_freeUser_sendsMeteredInstallAndWeek_withoutEntitlement() {
        let headers = MealScanQuota.serverHeaders(installID: "6F9619FF-8B86-D011-B42D-00C04FC964FF", weekID: "2026-W43", entitlementJWS: nil)
        XCTAssertEqual(headers, [
            "X-Atlas-Scan-Metered": "1",
            "X-Atlas-Install-Id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "X-Atlas-Scan-Week": "2026-W43",
        ])
    }

    func test_serverHeaders_proUser_addsSignedTransaction() {
        let headers = MealScanQuota.serverHeaders(installID: "id", weekID: "2026-W43", entitlementJWS: "header.payload.signature")
        XCTAssertEqual(headers["X-Atlas-Entitlement"], "header.payload.signature")
        XCTAssertEqual(headers["X-Atlas-Scan-Metered"], "1")
    }

    func test_serverHeaders_emptyEntitlement_isOmitted() {
        let headers = MealScanQuota.serverHeaders(installID: "id", weekID: "2026-W43", entitlementJWS: "")
        XCTAssertNil(headers["X-Atlas-Entitlement"])
    }

    func test_isAllowanceRefusal_onlyForScanQuotaCode() {
        XCTAssertTrue(MealScanQuota.isAllowanceRefusal(Data(#"{"error":{"message":"Free scan limit reached","code":"scan_quota"}}"#.utf8)))
        XCTAssertFalse(MealScanQuota.isAllowanceRefusal(Data(#"{"error":{"message":"Too many requests"}}"#.utf8)))
        XCTAssertFalse(MealScanQuota.isAllowanceRefusal(Data()))
    }
}
