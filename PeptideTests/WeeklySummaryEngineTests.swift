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

    func test_compliance_partial_reportsExactPct() {
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
        XCTAssertEqual(agg?.compliance.pct ?? 0, 0.8, accuracy: 0.001)
    }

    func test_compliance_bestDay_reportsHighestDayFraction() {
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
        XCTAssertEqual(agg?.compliance.bestDayPct ?? 0, 1.0, accuracy: 0.001)
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

    func test_outcomes_threeCheckIns_reportsAverages() {
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
        XCTAssertEqual(agg?.outcomes?.energyAvg ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(agg?.outcomes?.sleepAvg ?? 0, 5.0, accuracy: 0.001)
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
            topInsight: "Worth noting"  // arbitrary opaque string is allowed
        )
        let encoded = try JSONEncoder().encode(agg)
        let json = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("BPC-157"), "peptide name leaked into aggregate")
        XCTAssertFalse(json.contains("Felt great"), "outcome note leaked into aggregate")
    }
}
