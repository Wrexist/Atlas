import XCTest
@testable import Peptide

@MainActor
final class TodayOverviewSnapshotTests: XCTestCase {

    // MARK: - Empty state

    func test_build_brandNewProfile_hasNoSignal() {
        let store = DataStore(seedSampleData: false)
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertFalse(snapshot.hasAnySignal)
        XCTAssertNil(snapshot.complianceFraction)
        XCTAssertNil(snapshot.nextDose)
        XCTAssertNil(snapshot.checkInScore)
        XCTAssertNil(snapshot.latestLab)
        XCTAssertEqual(snapshot.caloriesToday, 0)
        XCTAssertEqual(snapshot.waterToday, 0)
    }

    // MARK: - Nutrition signal flips the card on

    func test_build_withCalorieTarget_setsTargetAndFlipsSignalOn() {
        let store = DataStore(seedSampleData: false)
        store.updateNutritionTargets(
            NutritionTargets(calories: 2400, proteinG: 180, carbsG: 240, fatG: 80, fiberG: 30)
        )
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertEqual(snapshot.calorieTarget, 2400)
        XCTAssertTrue(snapshot.hasAnySignal)
    }

    func test_build_withWaterLogged_reportsWater() {
        let store = DataStore(seedSampleData: false)
        store.logWater(oz: 32)
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertEqual(snapshot.waterToday, 32)
        XCTAssertTrue(snapshot.hasAnySignal)
    }

    // MARK: - Check-in

    func test_build_withTodayOutcome_populatesCompositeScore() {
        let store = DataStore(seedSampleData: false)
        store.logOutcome(
            OutcomeEntry(date: Date(), energy: 4, sleepQuality: 5, recovery: 4, mood: 4, focus: 3)
        )
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertNotNil(snapshot.checkInScore)
        XCTAssertEqual(snapshot.checkInScore ?? 0, 4.0, accuracy: 0.001)
    }

    func test_build_outcomeFromYesterday_doesNotPopulateTodayScore() {
        let store = DataStore(seedSampleData: false)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        store.logOutcome(
            OutcomeEntry(date: yesterday, energy: 5, sleepQuality: 5, recovery: 5, mood: 5, focus: 5)
        )
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertNil(snapshot.checkInScore)
    }

    // MARK: - Lab summary

    func test_build_latestLab_reportsShortNameAndDaysAgo() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        store.saveLabValue(LabValue(date: fiveDaysAgo, panel: .totalTestosterone, value: 712))
        store.saveLabValue(
            LabValue(
                date: Calendar.current.date(byAdding: .day, value: -30, to: now)!,
                panel: .igf1,
                value: 180
            )
        )
        let snapshot = TodayOverviewSnapshot.build(from: store, now: now)
        XCTAssertEqual(snapshot.latestLab?.panelShortName, "Total T")
        XCTAssertEqual(snapshot.latestLab?.daysAgo, 5)
        XCTAssertEqual(snapshot.latestLab?.valueDisplay, "712 ng/dL")
    }

    func test_build_latestLab_subTenValue_formatsWithOneDecimal() {
        let store = DataStore(seedSampleData: false)
        store.saveLabValue(LabValue(date: Date(), panel: .tsh, value: 2.4))
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertEqual(snapshot.latestLab?.valueDisplay, "2.4 μIU/mL")
    }

    // MARK: - Bottom insight selection

    func test_build_bottomInsight_prioritisesProtocolInsightOverLab() {
        let store = DataStore(seedSampleData: false)
        // Insight engine fires a streak insight at 7+ consecutive days.
        // Add a fresh lab too — the engine output should still win the slot.
        for offset in 0..<10 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            store.entries.append(
                ProtocolEntry(
                    id: UUID(),
                    protocolId: UUID(),
                    peptide: MockPeptides.bpc157,
                    date: date,
                    dose: "250mcg",
                    notes: "",
                    completed: true
                )
            )
        }
        store.saveLabValue(LabValue(date: Date(), panel: .igf1, value: 180))
        let snapshot = TodayOverviewSnapshot.build(from: store)
        guard case .protocolInsight = snapshot.bottomInsight else {
            XCTFail("Expected protocol insight to win over latest-lab")
            return
        }
    }

    func test_build_bottomInsight_freshUserGetsCalorieTargetNudge() {
        let store = DataStore(seedSampleData: false)
        let snapshot = TodayOverviewSnapshot.build(from: store)
        // No insights, no labs, no target → calorie-target nudge fires.
        guard case .nudge(let title, _, _) = snapshot.bottomInsight else {
            XCTFail("Expected nudge insight for empty profile")
            return
        }
        XCTAssertTrue(title.contains("calorie") || title.contains("Calorie"))
    }

    func test_build_bottomInsight_oldLabFallsThroughToNudge() {
        let store = DataStore(seedSampleData: false)
        // Lab older than 60 days shouldn't surface as the insight —
        // the staleness implies the user has moved on, and the
        // calorie-target nudge is more actionable.
        let oldDate = Calendar.current.date(byAdding: .day, value: -120, to: Date())!
        store.saveLabValue(LabValue(date: oldDate, panel: .totalTestosterone, value: 712))
        let snapshot = TodayOverviewSnapshot.build(from: store)
        XCTAssertNotNil(snapshot.latestLab) // still surfaced in the lab field
        if case .latestLab = snapshot.bottomInsight {
            XCTFail("Stale lab should not surface as bottom insight")
        }
    }
}
