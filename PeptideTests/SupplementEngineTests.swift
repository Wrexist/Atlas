import XCTest
@testable import Peptide

final class SupplementEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// 2026-10-<day> at the given time, Stockholm.
    private func october(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private func supplement(
        taken days: [Int] = [],
        minuteOfDay: Int? = nil,
        reminder: Bool = false,
        createdOn createdDay: Int = 1
    ) -> Supplement {
        Supplement(
            name: "Creatine",
            dose: "5 g",
            minuteOfDay: minuteOfDay,
            reminderEnabled: reminder,
            takenDays: days.map { SupplementEngine.dayKey(for: october($0), calendar: calendar) }.sorted(),
            createdAt: october(createdDay, 0)
        )
    }

    // MARK: - Day keys and toggling

    func test_dayKey_justAfterLocalMidnight_isTheLocalDayNotUTC() {
        // 00:30 in Stockholm is still 23:30 the day before in UTC.
        XCTAssertEqual(SupplementEngine.dayKey(for: october(28, 0, 30), calendar: calendar), "2026-10-28")
    }

    func test_toggled_untakenSupplement_isTakenToday() {
        let toggled = SupplementEngine.toggled(supplement(), on: october(28, 8), calendar: calendar)
        XCTAssertTrue(SupplementEngine.isTaken(toggled, on: october(28, 20), calendar: calendar))
    }

    func test_toggled_takenToday_isUntakenAndKeepsOtherDays() {
        let toggled = SupplementEngine.toggled(supplement(taken: [27, 28]), on: october(28, 9), calendar: calendar)
        XCTAssertFalse(SupplementEngine.isTaken(toggled, on: october(28), calendar: calendar))
        XCTAssertTrue(SupplementEngine.isTaken(toggled, on: october(27), calendar: calendar))
    }

    func test_toggled_outOfOrderHistory_keepsDaysSortedWithoutDuplicates() {
        var start = supplement(taken: [27, 25])
        start.takenDays = start.takenDays.reversed()
        let toggled = SupplementEngine.toggled(start, on: october(26), calendar: calendar)
        XCTAssertEqual(toggled.takenDays, ["2026-10-25", "2026-10-26", "2026-10-27"])
    }

    // MARK: - Midnight reset

    func test_isTaken_takenJustBeforeMidnight_resetsAtLocalMidnight() {
        let taken = SupplementEngine.toggled(supplement(), on: october(27, 23, 59), calendar: calendar)
        XCTAssertTrue(SupplementEngine.isTaken(taken, on: october(27, 23, 59), calendar: calendar))
        XCTAssertFalse(SupplementEngine.isTaken(taken, on: october(28, 0, 1), calendar: calendar))
    }

    func test_isTaken_otherTimeZoneCalendar_usesThatZonesMidnight() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        // 18:00 in Stockholm on the 27th is 02:00 on the 28th in Tokyo.
        let taken = SupplementEngine.toggled(supplement(), on: october(27, 18), calendar: calendar)
        XCTAssertFalse(SupplementEngine.isTaken(taken, on: october(27, 18), calendar: tokyo))
    }

    // MARK: - Streak

    func test_streak_takenTodayAndTwoDaysBefore_isThree() {
        XCTAssertEqual(SupplementEngine.streak(supplement(taken: [26, 27, 28]), now: october(28, 20), calendar: calendar), 3)
    }

    func test_streak_notYetTakenToday_countsTheRunEndingYesterday() {
        XCTAssertEqual(SupplementEngine.streak(supplement(taken: [26, 27]), now: october(28, 8), calendar: calendar), 2)
    }

    func test_streak_missedYesterday_isZeroUntilTakenToday() {
        XCTAssertEqual(SupplementEngine.streak(supplement(taken: [25, 26]), now: october(28, 8), calendar: calendar), 0)
    }

    func test_streak_gapInTheMiddle_countsOnlyTheLatestRun() {
        XCTAssertEqual(SupplementEngine.streak(supplement(taken: [20, 21, 22, 26, 27, 28]), now: october(28), calendar: calendar), 3)
    }

    func test_streak_acrossTheDaylightSavingChange_staysUnbroken() {
        // Sweden leaves summer time on 2026-10-25, a 25-hour day.
        XCTAssertEqual(SupplementEngine.streak(supplement(taken: [24, 25, 26]), now: october(26, 9), calendar: calendar), 3)
    }

    // MARK: - Week dots

    func test_week_returnsSevenDaysOldestFirstEndingToday() {
        let week = SupplementEngine.week(supplement(taken: [22, 28]), now: october(28, 15), calendar: calendar)
        XCTAssertEqual(week.count, SupplementEngine.weekLength)
        XCTAssertEqual(week.first?.day, calendar.startOfDay(for: october(22)))
        XCTAssertEqual(week.last?.day, calendar.startOfDay(for: october(28)))
        XCTAssertEqual(week.map(\.isTaken), [true, false, false, false, false, false, true])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, false, false, true])
    }

    // MARK: - Today rows

    func test_ordered_timedFirstByClockThenAnyTimeByCreation() {
        let evening = Supplement(name: "Magnesium", minuteOfDay: 20 * 60, createdAt: october(1))
        let morning = Supplement(name: "Vitamin D", minuteOfDay: 8 * 60, createdAt: october(3))
        let anyTimeOld = Supplement(name: "Omega-3", createdAt: october(2))
        let anyTimeNew = Supplement(name: "Zinc", createdAt: october(4))
        let ordered = SupplementEngine.ordered([anyTimeNew, evening, anyTimeOld, morning])
        XCTAssertEqual(ordered.map(\.name), ["Vitamin D", "Magnesium", "Omega-3", "Zinc"])
    }

    func test_rows_pastDay_leavesOutSupplementsAddedLater() {
        let old = supplement(taken: [20], createdOn: 1)
        let added = supplement(createdOn: 25)
        let rows = SupplementEngine.rows([old, added], on: october(20), calendar: calendar)
        XCTAssertEqual(rows.map(\.id), [old.id])
        XCTAssertEqual(rows.first?.isTaken, true)
    }

    func test_rows_dayItWasAdded_includesIt() {
        let added = supplement(createdOn: 28)
        XCTAssertEqual(SupplementEngine.rows([added], on: october(28, 22), calendar: calendar).count, 1)
    }

    // MARK: - Reminders

    func test_reminderPlan_notTakenToday_coversTodayAndLookahead() {
        let planned = SupplementEngine.reminderPlan(
            [supplement(minuteOfDay: 20 * 60, reminder: true)], now: october(28, 8), calendar: calendar
        )
        XCTAssertEqual(planned.count, SupplementEngine.lookaheadDays)
        XCTAssertEqual(planned.first?.fireDate, october(28, 20))
    }

    func test_reminderPlan_takenToday_dropsTodayKeepsTomorrow() {
        let planned = SupplementEngine.reminderPlan(
            [supplement(taken: [28], minuteOfDay: 20 * 60, reminder: true)], now: october(28, 8), calendar: calendar
        )
        XCTAssertEqual(planned.first?.fireDate, october(29, 20))
        XCTAssertEqual(planned.count, SupplementEngine.lookaheadDays - 1)
    }

    func test_reminderPlan_timeAlreadyPassed_startsTomorrow() {
        let planned = SupplementEngine.reminderPlan(
            [supplement(minuteOfDay: 8 * 60, reminder: true)], now: october(28, 9), calendar: calendar
        )
        XCTAssertEqual(planned.first?.fireDate, october(29, 8))
    }

    func test_reminderPlan_reminderOffOrNoTime_plansNothing() {
        let off = supplement(minuteOfDay: 8 * 60, reminder: false)
        let untimed = supplement(minuteOfDay: nil, reminder: true)
        XCTAssertTrue(SupplementEngine.reminderPlan([off, untimed], now: october(28, 6), calendar: calendar).isEmpty)
    }

    func test_reminderPlan_manySupplements_keepsTheSoonestWithinTheLimit() {
        let supplements = (0..<10).map { supplement(minuteOfDay: (8 + $0) * 60, reminder: true) }
        let planned = SupplementEngine.reminderPlan(supplements, now: october(28, 6), calendar: calendar, limit: 5)
        XCTAssertEqual(planned.count, 5)
        XCTAssertEqual(planned.map(\.fireDate), (8..<13).map { october(28, $0) })
    }

    func test_reminderIdentifier_isInTheDailyNamespaceAndUniquePerDay() {
        let id = UUID()
        let today = SupplementEngine.reminderIdentifier(supplementID: id, day: october(28), calendar: calendar)
        let tomorrow = SupplementEngine.reminderIdentifier(supplementID: id, day: october(29), calendar: calendar)
        XCTAssertTrue(today.hasPrefix(NotificationService.dailyIDPrefix))
        XCTAssertTrue(today.hasSuffix("20261028"))
        XCTAssertNotEqual(today, tomorrow)
    }

    // MARK: - Sync merge

    func test_reconcile_sameSupplementOnBothRows_keepsEveryTakenDay() {
        let shared = supplement(taken: [26])
        var otherCopy = shared
        otherCopy.takenDays = [SupplementEngine.dayKey(for: october(27), calendar: calendar)]
        var primary = UserProfile.fresh
        primary.supplements = [shared]
        var other = UserProfile.fresh
        other.supplements = [otherCopy, supplement(taken: [27])]

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(merged.supplements.count, 2)
        XCTAssertEqual(merged.supplements.first?.takenDays, ["2026-10-26", "2026-10-27"])
    }

    func test_profileDecode_olderProfileWithoutSupplements_decodesEmpty() throws {
        var profile = UserProfile.fresh
        profile.supplements = [supplement(taken: [28])]
        let data = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let roundTrip = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(roundTrip.supplements, profile.supplements)

        object.removeValue(forKey: "supplements")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(UserProfile.self, from: legacy).supplements, [])
    }
}
