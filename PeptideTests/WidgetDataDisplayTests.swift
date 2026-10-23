import XCTest
@testable import Peptide

/// Pins what the widgets show when the app hasn't written since an
/// earlier day or week. The rules run in the widget extension, which
/// nothing else would catch drifting: a regression shows yesterday's
/// calories as today's, or last week's sessions as this week's.
final class WidgetDataDisplayTests: XCTestCase {

    /// Gregorian, Monday-first, UTC, so the day and week edges don't
    /// depend on the runner's locale.
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        cal.firstWeekday = 2
        return cal
    }()

    /// Wednesday 2025-06-11, 12:00 UTC.
    private let written = Date(timeIntervalSince1970: 1_749_643_200)

    private func payload(
        writtenAt: Date? = nil,
        totalToday: Int = 2,
        hasActiveProtocol: Bool = true,
        startedAt: Date? = nil,
        pausedSeconds: Double = 0,
        pausedAt: Date? = nil
    ) -> WidgetData {
        WidgetData(
            nextPeptideName: "BPC", nextDose: "250 mcg",
            nextDoseTime: totalToday > 0 ? written.addingTimeInterval(3600) : nil,
            completedToday: 1, totalToday: totalToday,
            lastUpdated: writtenAt ?? written,
            hasActiveProtocol: hasActiveProtocol,
            caloriesToday: 1_450, calorieTarget: 2_200,
            proteinToday: 95, carbsToday: 160, fatToday: 48,
            proteinTarget: 150,
            mealsByCategory: [WidgetMealSlot(category: "Lunch", calories: 680, entryCount: 2)],
            workoutsThisWeek: 3, weeklySetCount: 42, weeklyVolumeKg: 12_480,
            activeWorkoutStartedAt: startedAt,
            activeWorkoutPausedSeconds: pausedSeconds,
            activeWorkoutPausedAt: pausedAt,
            trainingDaysThisWeek: [written]
        )
    }

    // MARK: - Day rollover

    func test_forDisplay_sameDay_keepsTheDaysIntake() {
        let shown = payload().forDisplay(at: written.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(shown.caloriesToday, 1_450)
        XCTAssertEqual(shown.proteinToday, 95)
        XCTAssertEqual(shown.mealsByCategory.first?.entryCount, 2)
    }

    func test_forDisplay_payloadFromYesterday_zeroesIntakeButKeepsTargets() {
        let shown = payload().forDisplay(at: written.addingTimeInterval(86_400), calendar: calendar)
        XCTAssertEqual(shown.caloriesToday, 0)
        XCTAssertEqual(shown.proteinToday, 0)
        XCTAssertEqual(shown.carbsToday, 0)
        XCTAssertEqual(shown.fatToday, 0)
        XCTAssertEqual(shown.calorieTarget, 2_200)
        XCTAssertEqual(shown.proteinTarget, 150)
        XCTAssertEqual(shown.mealsByCategory, [WidgetMealSlot(category: "Lunch", calories: 0, entryCount: 0)])
    }

    func test_isProtocolOutdated_payloadFromYesterday_isOutdated() {
        XCTAssertTrue(payload().isProtocolOutdated(at: written.addingTimeInterval(86_400), calendar: calendar))
    }

    func test_isProtocolOutdated_sameDay_isCurrent() {
        XCTAssertFalse(payload().isProtocolOutdated(at: written.addingTimeInterval(3600), calendar: calendar))
    }

    /// Written on a rest day, read on a dose day: the widget must ask
    /// for today's doses, not say there is no protocol.
    func test_isProtocolOutdated_restDayPayloadFromYesterday_isOutdated() {
        let restDay = payload(totalToday: 0)
        XCTAssertTrue(restDay.isProtocolOutdated(at: written.addingTimeInterval(86_400), calendar: calendar))
    }

    func test_isProtocolOutdated_noProtocolFromYesterday_staysCurrent() {
        let none = payload(totalToday: 0, hasActiveProtocol: false)
        XCTAssertFalse(none.isProtocolOutdated(at: written.addingTimeInterval(86_400), calendar: calendar))
    }

    // MARK: - Week rollover

    func test_forDisplay_laterSameWeek_keepsTheWeek() {
        let saturday = written.addingTimeInterval(3 * 86_400)
        let shown = payload().forDisplay(at: saturday, calendar: calendar)
        XCTAssertEqual(shown.workoutsThisWeek, 3)
        XCTAssertEqual(shown.trainingDaysThisWeek, [written])
    }

    func test_forDisplay_payloadFromLastWeek_resetsTheWeek() {
        let nextMonday = written.addingTimeInterval(5 * 86_400)
        let shown = payload().forDisplay(at: nextMonday, calendar: calendar)
        XCTAssertEqual(shown.workoutsThisWeek, 0)
        XCTAssertEqual(shown.weeklySetCount, 0)
        XCTAssertEqual(shown.weeklyVolumeKg, 0)
        XCTAssertEqual(shown.trainingDaysThisWeek, [])
    }

    // MARK: - Running workout

    func test_activeWorkoutPausedElapsed_openPause_isPauseMinusStartMinusPausedTime() {
        let start = written.addingTimeInterval(-3_600)
        let data = payload(startedAt: start, pausedSeconds: 300, pausedAt: written.addingTimeInterval(-600))
        XCTAssertEqual(data.activeWorkoutPausedElapsed, 3_000 - 300)
        XCTAssertEqual(data.activeWorkoutClockStart, start.addingTimeInterval(300))
    }

    func test_activeWorkoutPausedElapsed_clockRunning_isNil() {
        let data = payload(startedAt: written.addingTimeInterval(-3_600), pausedSeconds: 300)
        XCTAssertNil(data.activeWorkoutPausedElapsed)
    }

    // MARK: - Reload schedule

    func test_nextRefresh_midDay_isFifteenMinutesOut() {
        XCTAssertEqual(WidgetData.nextRefresh(after: written, calendar: calendar), written.addingTimeInterval(900))
    }

    func test_nextRefresh_justBeforeMidnight_stopsAtMidnight() {
        let lateEvening = calendar.startOfDay(for: written).addingTimeInterval(86_400 - 300)
        XCTAssertEqual(
            WidgetData.nextRefresh(after: lateEvening, calendar: calendar),
            calendar.startOfDay(for: written).addingTimeInterval(86_400)
        )
    }

    /// 2025-03-30 is 23 hours long in Stockholm; the reload must still
    /// land on the next midnight, not an hour past it.
    func test_nextRefresh_shortDSTDay_neverPassesMidnight() throws {
        var stockholm = Calendar(identifier: .gregorian)
        stockholm.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        let dstDay = try XCTUnwrap(stockholm.date(from: DateComponents(year: 2025, month: 3, day: 30, hour: 23, minute: 50)))
        let midnight = try XCTUnwrap(stockholm.date(from: DateComponents(year: 2025, month: 3, day: 31)))

        XCTAssertEqual(WidgetData.nextMidnight(after: dstDay, calendar: stockholm), midnight)
        XCTAssertEqual(WidgetData.nextRefresh(after: dstDay, minutes: 30, calendar: stockholm), midnight)
    }

    // MARK: - Wire format

    func test_decode_payloadWithoutHasActiveProtocol_defaultsToFalse() throws {
        let json = #"{"nextPeptideName":"","nextDose":"","completedToday":0,"totalToday":0,"lastUpdated":"2025-06-11T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetData.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.hasActiveProtocol)
    }
}
