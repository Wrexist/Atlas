import XCTest
@testable import Peptide

final class UpsellSchedulerTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func shouldShow(
        declinedAt: Date? = nil,
        activeDayCount: Int = 3,
        alreadyShown: Bool = false,
        isPro: Bool = false,
        isTrialEligible: Bool = true,
        now: Date? = nil
    ) -> Bool {
        UpsellScheduler.shouldShowWinBack(
            declinedAt: declinedAt ?? date(9, 20),
            activeDayCount: activeDayCount,
            alreadyShown: alreadyShown,
            isPro: isPro,
            isTrialEligible: isTrialEligible,
            now: now ?? date(9, 23),
            calendar: utc
        )
    }

    // MARK: - shouldShowWinBack

    func test_shouldShowWinBack_allConditionsMet_returnsTrue() {
        XCTAssertTrue(shouldShow())
    }

    func test_shouldShowWinBack_neverDeclined_returnsFalse() {
        XCTAssertFalse(UpsellScheduler.shouldShowWinBack(
            declinedAt: nil, activeDayCount: 10, alreadyShown: false,
            isPro: false, isTrialEligible: true, now: date(9, 23), calendar: utc
        ))
    }

    func test_shouldShowWinBack_fewerThanThreeActiveDays_returnsFalse() {
        XCTAssertFalse(shouldShow(activeDayCount: 2))
    }

    func test_shouldShowWinBack_twoDaysAfterDecline_returnsFalse() {
        XCTAssertFalse(shouldShow(now: date(9, 22)))
    }

    func test_shouldShowWinBack_countsCalendarDays_notHours() {
        // Declined late on the 20th, back early on the 23rd: under 72
        // hours, but three calendar days.
        XCTAssertTrue(shouldShow(declinedAt: date(9, 20, hour: 23), now: date(9, 23, hour: 7)))
    }

    func test_shouldShowWinBack_alreadyShown_returnsFalse() {
        XCTAssertFalse(shouldShow(alreadyShown: true))
    }

    func test_shouldShowWinBack_pro_returnsFalse() {
        XCTAssertFalse(shouldShow(isPro: true))
    }

    func test_shouldShowWinBack_trialAlreadyRedeemed_returnsFalse() {
        XCTAssertFalse(shouldShow(isTrialEligible: false))
    }

    // MARK: - Active days

    func test_addingActiveDay_sameDayTwice_countsOnce() {
        let days = UpsellScheduler.addingActiveDay("2026-09-23", to: ["2026-09-23"])
        XCTAssertEqual(days, ["2026-09-23"])
    }

    func test_addingActiveDay_capsStoredDays_keepingNewest() {
        let existing = (1...UpsellScheduler.maxStoredActiveDays).map { String(format: "2026-08-%02d", $0) }
        let days = UpsellScheduler.addingActiveDay("2026-09-01", to: existing)
        XCTAssertEqual(days.count, UpsellScheduler.maxStoredActiveDays)
        XCTAssertEqual(days.last, "2026-09-01")
        XCTAssertFalse(days.contains("2026-08-01"))
    }

    func test_dayKey_usesTheCalendarsTimeZone() {
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let lateUTC = date(9, 23, hour: 20)
        XCTAssertEqual(UpsellScheduler.dayKey(for: lateUTC, calendar: utc), "2026-09-23")
        XCTAssertEqual(UpsellScheduler.dayKey(for: lateUTC, calendar: tokyo), "2026-09-24")
    }

    func test_isWinBackDue_readsPersistedState_andStopsAfterShown() {
        let suite = "UpsellSchedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        UpsellScheduler.recordTrialDeclined(now: date(9, 20), defaults: defaults)
        for day in [20, 21, 21, 23] {
            UpsellScheduler.recordActiveDay(now: date(9, day), calendar: utc, defaults: defaults)
        }
        XCTAssertTrue(UpsellScheduler.isWinBackDue(
            isPro: false, isTrialEligible: true, now: date(9, 23), calendar: utc, defaults: defaults
        ))

        UpsellScheduler.markWinBackShown(defaults: defaults)
        XCTAssertFalse(UpsellScheduler.isWinBackDue(
            isPro: false, isTrialEligible: true, now: date(9, 30), calendar: utc, defaults: defaults
        ))
    }
}
