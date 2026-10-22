import XCTest
@testable import Peptide

/// Pins Today's day browsing: the picker's clamping, which sections a
/// past day keeps, and the day-scoped reads behind them.
@MainActor
final class TodayDayEngineTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// Wednesday 2026-10-21 at the given hour.
    private func wednesday(_ hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute)) ?? Date()
    }

    private func entry(at date: Date, protocolId: UUID) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: protocolId,
            peptide: MockPeptides.bpc157,
            date: date,
            dose: "250mcg",
            notes: "",
            completed: false
        )
    }

    // MARK: - Day clamping

    func test_day_zeroOffset_isStartOfToday() {
        let day = TodayDayEngine.day(offset: 0, from: wednesday(15), calendar: calendar)
        XCTAssertEqual(day, calendar.startOfDay(for: wednesday(15)))
    }

    func test_day_negativeOffset_stepsBackWholeDays() {
        let day = TodayDayEngine.day(offset: -2, from: wednesday(15), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: day), 19)
        XCTAssertEqual(day, calendar.startOfDay(for: day))
    }

    func test_day_futureOffset_clampsToToday() {
        let day = TodayDayEngine.day(offset: 3, from: wednesday(15), calendar: calendar)
        XCTAssertEqual(day, calendar.startOfDay(for: wednesday(15)))
    }

    func test_day_beyondLookback_clampsToOneYearFloor() {
        let floor = TodayDayEngine.day(offset: -LifestyleDataLogic.maxMealDayLookback, from: wednesday(15), calendar: calendar)
        let beyond = TodayDayEngine.day(offset: -5_000, from: wednesday(15), calendar: calendar)
        XCTAssertEqual(beyond, floor)
    }

    func test_isToday_zeroOrFutureOffset_true() {
        XCTAssertTrue(TodayDayEngine.isToday(offset: 0))
        XCTAssertTrue(TodayDayEngine.isToday(offset: 1))
    }

    func test_isToday_pastOffset_false() {
        XCTAssertFalse(TodayDayEngine.isToday(offset: -1))
    }

    // MARK: - Section visibility

    func test_isVisible_today_showsEverySection() {
        for section in TodayDayEngine.Section.allCases {
            XCTAssertTrue(TodayDayEngine.isVisible(section, isToday: true), "\(section) hidden on today")
        }
    }

    func test_isVisible_pastDay_keepsPerDayRecords() {
        let kept: [TodayDayEngine.Section] = [.habits, .checklist, .doses, .movement, .overview, .timeline]
        for section in kept {
            XCTAssertTrue(TodayDayEngine.isVisible(section, isToday: false), "\(section) hidden on a past day")
        }
    }

    func test_isVisible_pastDay_hidesLiveAndTodayOnlySections() {
        let hidden: [TodayDayEngine.Section] = [
            .quickActions, .notificationBanner, .atAGlance, .coaching,
            .weeklyRecap, .wellness, .momentum, .explore, .healthMonitor,
        ]
        for section in hidden {
            XCTAssertFalse(TodayDayEngine.isVisible(section, isToday: false), "\(section) shown on a past day")
        }
    }

    // MARK: - Day-scoped reads

    func test_dayRange_spansMidnightToNextMidnight() {
        let range = TodayDayEngine.dayRange(for: wednesday(15), calendar: calendar)
        XCTAssertEqual(range.lowerBound, calendar.startOfDay(for: wednesday(15)))
        XCTAssertTrue(range.contains(wednesday(23, minute: 59)))
        XCTAssertFalse(range.contains(calendar.date(byAdding: .day, value: 1, to: range.lowerBound) ?? .distantFuture))
    }

    func test_doseEntries_keepsOnlyThatDay_sortedByTime() {
        let protoId = UUID()
        let evening = entry(at: wednesday(20), protocolId: protoId)
        let morning = entry(at: wednesday(7), protocolId: protoId)
        let dayBefore = entry(at: wednesday(7).addingTimeInterval(-86_400), protocolId: protoId)

        let result = TodayDayEngine.doseEntries(
            [evening, dayBefore, morning],
            on: wednesday(12),
            protocolIds: [protoId],
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.id), [morning.id, evening.id])
    }

    func test_doseEntries_deletedProtocol_dropsOrphans() {
        let kept = entry(at: wednesday(8), protocolId: UUID())
        let orphan = entry(at: wednesday(9), protocolId: UUID())

        let result = TodayDayEngine.doseEntries(
            [kept, orphan],
            on: wednesday(12),
            protocolIds: [kept.protocolId],
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.id), [kept.id])
    }

    // MARK: - Habits on a past day

    func test_habitsSnapshot_pastDay_reportsThatDaysCompletion() {
        let habit = Habit(
            id: UUID(),
            name: "Walk",
            iconSymbol: "figure.walk",
            tintHex: 0x5BC489,
            schedule: .daily,
            targetValue: nil
        )
        let yesterday = calendar.startOfDay(for: wednesday(12).addingTimeInterval(-86_400))
        let entries = [HabitEntry(habitId: habit.id, date: yesterday, calendar: calendar)]

        let onYesterday = HabitsHeroSnapshot.build(
            activeHabits: [habit], entries: entries, on: yesterday, calendar: calendar
        )
        let onToday = HabitsHeroSnapshot.build(
            activeHabits: [habit], entries: entries, on: wednesday(12), calendar: calendar
        )

        XCTAssertEqual(onYesterday.doneCount, 1)
        XCTAssertEqual(onYesterday.dueCount, 1)
        XCTAssertEqual(onToday.doneCount, 0)
    }

    func test_habitsSnapshot_pastMissedDay_breaksStreak() {
        let habit = Habit(
            id: UUID(),
            name: "Walk",
            iconSymbol: "figure.walk",
            tintHex: 0x5BC489,
            schedule: .daily,
            targetValue: nil
        )
        let missedDay = calendar.startOfDay(for: wednesday(12))
        let tuesday = calendar.date(byAdding: .day, value: -1, to: missedDay)!
        let monday = calendar.date(byAdding: .day, value: -2, to: missedDay)!
        let thursday = calendar.date(byAdding: .day, value: 1, to: missedDay)!
        let entries = [
            HabitEntry(habitId: habit.id, date: monday, calendar: calendar),
            HabitEntry(habitId: habit.id, date: tuesday, calendar: calendar),
        ]

        let browsed = HabitsHeroSnapshot.build(
            activeHabits: [habit], entries: entries, on: missedDay, now: thursday, calendar: calendar
        )
        let live = HabitsHeroSnapshot.build(
            activeHabits: [habit], entries: entries, on: missedDay, now: wednesday(9), calendar: calendar
        )

        XCTAssertEqual(browsed.bestCurrentStreak, 0)
        XCTAssertEqual(live.bestCurrentStreak, 2)
    }
}
