import XCTest
@testable import Peptide

final class WeeklySummaryEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    /// Reference Monday of the test week — picked far enough in the
    /// past that no calendar-rollover edge case interferes. Every
    /// time-dependent test pins to this Monday + adds day offsets.
    private var weekMonday: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5  // Monday Jan 5 2026
        components.hour = 9
        return calendar.date(from: components)!
    }

    private func entry(daysFromMonday: Int, hour: Int = 9, completed: Bool) -> ProtocolEntry {
        let date = calendar.date(
            byAdding: .day, value: daysFromMonday, to: weekMonday
        )!
            .addingTimeInterval(TimeInterval((hour - 9) * 3600))
        return ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: date,
            dose: "250mcg",
            notes: "",
            completed: completed
        )
    }

    // MARK: - Suppression gates

    func test_build_belowMinDoseDays_returnsNil() {
        // Only 2 active days — below the 3-day floor.
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
        ]
        let agg = WeeklySummaryEngine.build(
            profile: .fresh,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        )
        XCTAssertNil(agg)
    }

    func test_build_threeActiveDays_returnsAggregate() {
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: true),
            entry(daysFromMonday: 2, completed: true),
        ]
        let agg = WeeklySummaryEngine.build(
            profile: .fresh,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        )
        XCTAssertNotNil(agg)
        XCTAssertEqual(agg?.compliance.activeDaysCount, 3)
    }

    // MARK: - Compliance math

    func test_compliance_partial_reportsExactPct() throws {
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: false),
            entry(daysFromMonday: 2, completed: true),
            entry(daysFromMonday: 3, completed: true),
        ]
        let agg = WeeklySummaryEngine.build(
            profile: .fresh,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        )
        XCTAssertEqual(agg?.compliance.completed, 4)
        XCTAssertEqual(agg?.compliance.total, 5)
        XCTAssertEqual(try XCTUnwrap(agg?.compliance.pct), 0.8, accuracy: 0.001)
    }

    func test_compliance_bestDay_reportsHighestDayFraction() throws {
        // Day 0: 2/2 = 100%. Day 1: 0/1 = 0%. Day 2: 1/2 = 50%.
        let entries = [
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 0, completed: true),
            entry(daysFromMonday: 1, completed: false),
            entry(daysFromMonday: 2, completed: true),
            entry(daysFromMonday: 2, completed: false),
        ]
        let agg = WeeklySummaryEngine.build(
            profile: .fresh,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        )
        XCTAssertEqual(try XCTUnwrap(agg?.compliance.bestDayPct), 1.0, accuracy: 0.001)
    }

    // MARK: - Outcomes

    func test_outcomes_belowThreeCheckIns_returnsNil() {
        var profile = UserProfile.fresh
        profile.outcomeHistory = [
            OutcomeEntry(date: weekMonday, energy: 4, sleepQuality: 4, recovery: 4, mood: 4, focus: 4),
            OutcomeEntry(date: calendar.date(byAdding: .day, value: 1, to: weekMonday)!,
                         energy: 4, sleepQuality: 4, recovery: 4, mood: 4, focus: 4),
        ]
        let entries = (0..<3).map { entry(daysFromMonday: $0, completed: true) }
        let agg = WeeklySummaryEngine.build(
            profile: profile,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        )
        XCTAssertNil(agg?.outcomes)
    }

    func test_outcomes_threeCheckIns_reportsAverages() throws {
        var profile = UserProfile.fresh
        profile.outcomeHistory = (0..<3).map { offset in
            OutcomeEntry(
                date: calendar.date(byAdding: .day, value: offset, to: weekMonday)!,
                energy: 4, sleepQuality: 5, recovery: 3, mood: 4, focus: 4
            )
        }
        let entries = (0..<3).map { entry(daysFromMonday: $0, completed: true) }
        let agg = WeeklySummaryEngine.build(
            profile: profile,
            protocols: [],
            entries: entries,
            referenceDate: weekMonday
        )
        XCTAssertEqual(try XCTUnwrap(agg?.outcomes?.energyAvg), 4.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(agg?.outcomes?.sleepAvg), 5.0, accuracy: 0.001)
        XCTAssertEqual(agg?.outcomes?.checkInsCount, 3)
    }

    // MARK: - Nutrition

    func test_nutrition_requiresTargetsAndTwoDays() {
        var profile = UserProfile.fresh
        let entries = (0..<3).map { entry(daysFromMonday: $0, completed: true) }

        // ISO yyyy-MM-dd string keys, matching the production
        // `dailyConsumption` shape — DailyConsumption is keyed by
        // local-day ISO date string, not raw Date.
        let keyFormatter = ISO8601DateFormatter()
        keyFormatter.formatOptions = [.withFullDate]
        keyFormatter.timeZone = calendar.timeZone
        func consumptionKey(for day: Date) -> String {
            keyFormatter.string(from: calendar.startOfDay(for: day))
        }

        // No targets → nutrition nil even with logged days.
        profile.dailyConsumption = [
            consumptionKey(for: weekMonday): DailyConsumption(
                date: calendar.startOfDay(for: weekMonday),
                caloriesKcal: 2000, proteinG: 150, carbsG: 200, fatG: 70, waterOz: 48
            )
        ]
        let agg1 = WeeklySummaryEngine.build(
            profile: profile, protocols: [], entries: entries, referenceDate: weekMonday
        )
        XCTAssertNil(agg1?.nutrition)

        // Targets + 2 logging days → reports.
        profile.nutritionTargets = NutritionTargets(
            calories: 2400, proteinG: 180, carbsG: 240, fatG: 80, fiberG: 30
        )
        let day1 = calendar.date(byAdding: .day, value: 1, to: weekMonday)!
        profile.dailyConsumption[consumptionKey(for: day1)] = DailyConsumption(
            date: calendar.startOfDay(for: day1),
            caloriesKcal: 2200, proteinG: 160, carbsG: 220, fatG: 75, waterOz: 32
        )
        let agg2 = WeeklySummaryEngine.build(
            profile: profile, protocols: [], entries: entries, referenceDate: weekMonday
        )
        XCTAssertEqual(agg2?.nutrition?.avgCalories, 2100)
        XCTAssertEqual(agg2?.nutrition?.mealLoggingDays, 2)
    }

    // MARK: - Biometrics

    func test_biometrics_emptySeries_returnsNil() {
        let entries = (0..<3).map { entry(daysFromMonday: $0, completed: true) }
        let agg = WeeklySummaryEngine.build(
            profile: .fresh, protocols: [], entries: entries,
            referenceDate: weekMonday,
            hrvSeries: [], rhrSeries: [], sleepSeries: []
        )
        XCTAssertNil(agg?.biometrics)
    }

    func test_biometrics_hrvDeltaVsPriorWeek() {
        let entries = (0..<3).map { entry(daysFromMonday: $0, completed: true) }
        // Current week: HRV 60
        // Prior week: HRV 56 → delta +4
        let priorMonday = calendar.date(byAdding: .day, value: -7, to: weekMonday)!
        let hrvSeries: [(date: Date, value: Double)] = [
            (weekMonday, 60),
            (calendar.date(byAdding: .day, value: 1, to: weekMonday)!, 60),
            (priorMonday, 56),
            (calendar.date(byAdding: .day, value: 1, to: priorMonday)!, 56),
        ]
        let agg = WeeklySummaryEngine.build(
            profile: .fresh, protocols: [], entries: entries,
            referenceDate: weekMonday,
            hrvSeries: hrvSeries
        )
        XCTAssertEqual(agg?.biometrics?.hrvAvg, 60)
        XCTAssertEqual(agg?.biometrics?.hrvDelta, 4)
    }

    // MARK: - Privacy

    func test_aggregate_doesNotLeakPeptideNames() throws {
        var profile = UserProfile.fresh
        profile.outcomeHistory = (0..<3).map { offset in
            OutcomeEntry(
                date: calendar.date(byAdding: .day, value: offset, to: weekMonday)!,
                energy: 4, sleepQuality: 4, recovery: 4, mood: 4, focus: 4,
                note: "Felt great after BPC-157"  // user note must not leak
            )
        }
        let entries = (0..<3).map { entry(daysFromMonday: $0, completed: true) }
        let agg = WeeklySummaryEngine.build(
            profile: profile, protocols: [], entries: entries,
            referenceDate: weekMonday,
            topInsightCategory: "neutral"  // category code, not free text
        )
        let encoded = try JSONEncoder().encode(agg)
        let json = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("BPC-157"), "peptide name leaked into aggregate")
        XCTAssertFalse(json.contains("Felt great"), "outcome note leaked into aggregate")
    }

    // MARK: - changeHeadline (week-over-week diff for the notification body)

    private func makeSummary(
        weekStart: String,
        compliancePct: Double = 0.7,
        currentStreak: Int = 3,
        hrvDelta: Int? = nil
    ) -> WeeklySummary {
        WeeklySummary(
            weekStart: weekStart,
            text: "",
            keyStats: WeeklySummary.KeyStats(
                compliancePct: compliancePct,
                dosesCompleted: 7,
                dosesTotal: 10,
                currentStreak: currentStreak,
                avgCheckInScore: nil,
                avgCalories: nil,
                hrvDelta: hrvDelta
            ),
            kind: .offline,
            generatedAt: weekMonday
        )
    }

    func test_changeHeadline_noPrevious_returnsNil() {
        let current = makeSummary(weekStart: "2026-01-05")
        XCTAssertNil(WeeklySummaryEngine.changeHeadline(current: current, previous: nil))
    }

    func test_changeHeadline_meaningfulComplianceIncrease_reportsPercent() {
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.9)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "Compliance up 20% from last week")
    }

    func test_changeHeadline_meaningfulComplianceDecrease_reportsDownDirection() {
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.6)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.8)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "Compliance down 20% from last week")
    }

    func test_changeHeadline_noiseLevelComplianceChange_fallsThroughToNil() {
        // 3-point swing is below the 8-point floor, and streak/HRV are
        // both unchanged/nil — nothing meaningful to report.
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.73, currentStreak: 3)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.70, currentStreak: 3)
        XCTAssertNil(WeeklySummaryEngine.changeHeadline(current: current, previous: previous))
    }

    func test_changeHeadline_meaningfulStreakGrowth_reportsStreak() {
        // Compliance unchanged (below the noise floor); streak grew by
        // the minimum meaningful amount (2 days).
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.7, currentStreak: 5)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7, currentStreak: 3)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "Your streak grew by 2 days this week")
    }

    func test_changeHeadline_streakShrinking_isNotReportedAsGrowth() {
        // A shrinking streak isn't a "grew by N days" moment — the
        // engine only ever reports positive streak growth here.
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.7, currentStreak: 1, hrvDelta: nil)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7, currentStreak: 5, hrvDelta: nil)
        XCTAssertNil(WeeklySummaryEngine.changeHeadline(current: current, previous: previous))
    }

    func test_changeHeadline_meaningfulHRVDelta_reportsHRV() {
        // Compliance and streak both unchanged; only HRV moved enough
        // to matter.
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.7, currentStreak: 3, hrvDelta: 5)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7, currentStreak: 3, hrvDelta: nil)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "HRV up 5 ms versus last week")
    }

    func test_changeHeadline_negativeHRVDelta_reportsDownDirection() {
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.7, currentStreak: 3, hrvDelta: -4)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7, currentStreak: 3, hrvDelta: nil)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "HRV down 4 ms versus last week")
    }

    func test_changeHeadline_belowNoiseFloorOnEveryMetric_returnsNil() {
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.71, currentStreak: 3, hrvDelta: 2)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.70, currentStreak: 3, hrvDelta: nil)
        XCTAssertNil(WeeklySummaryEngine.changeHeadline(current: current, previous: previous))
    }

    func test_changeHeadline_priorityOrder_complianceBeatsStreakAndHRVWhenAllMeaningful() {
        // All three deltas are meaningful at once — compliance is
        // checked first, so it wins even though streak and HRV also
        // qualify.
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.9, currentStreak: 6, hrvDelta: 10)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7, currentStreak: 3, hrvDelta: nil)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "Compliance up 20% from last week")
    }

    func test_changeHeadline_priorityOrder_streakBeatsHRVWhenBothMeaningful() {
        // Compliance below the noise floor; streak and HRV both
        // qualify — streak is checked first and wins.
        let current = makeSummary(weekStart: "2026-01-12", compliancePct: 0.7, currentStreak: 6, hrvDelta: 10)
        let previous = makeSummary(weekStart: "2026-01-05", compliancePct: 0.7, currentStreak: 3, hrvDelta: nil)
        let headline = WeeklySummaryEngine.changeHeadline(current: current, previous: previous)
        XCTAssertEqual(headline, "Your streak grew by 3 days this week")
    }
}
