import XCTest
@testable import Peptide

final class OfflineWeeklySummaryFormatterTests: XCTestCase {

    private func aggregate(
        pct: Double = 0.8,
        total: Int = 10,
        outcomes: WeeklyAggregate.Outcomes? = nil,
        nutrition: WeeklyAggregate.Nutrition? = nil,
        hrvDelta: Int? = nil,
        training: WeeklyAggregate.Training? = nil,
        newPanels: Int = 0
    ) -> WeeklyAggregate {
        WeeklyAggregate(
            weekStart: "2026-01-05",
            compliance: .init(
                completed: Int((pct * Double(total)).rounded()),
                total: total,
                pct: pct,
                bestDayPct: 1,
                activeDaysCount: 5
            ),
            streak: .init(current: 0, best: 0),
            outcomes: outcomes,
            nutrition: nutrition,
            biometrics: hrvDelta.map { WeeklyAggregate.Biometrics(hrvAvg: 60, hrvDelta: $0, rhrAvg: nil, sleepHoursAvg: nil) },
            training: training,
            labs: .init(newPanelsLogged: newPanels),
            topInsightCategory: nil
        )
    }

    private func summary(_ aggregate: WeeklyAggregate) -> String {
        OfflineWeeklySummaryFormatter.summary(from: aggregate)
    }

    private func nutrition(avgCalories: Int) -> WeeklyAggregate.Nutrition {
        .init(avgCalories: avgCalories, targetCalories: 2000, mealLoggingDays: 5, proteinAvgG: 120, proteinTargetG: 150)
    }

    // MARK: - Compliance bands

    func test_summary_pctAtNinety_isStrongWeek() {
        let text = summary(aggregate(pct: 0.9))
        XCTAssertTrue(text.hasPrefix("Strong week — 9 of 10 doses logged (90% adherence)."))
        XCTAssertTrue(text.contains("consistency at this level compounds"))
    }

    func test_summary_pctJustUnderNinety_opensAndClosesAsStrongWeek() {
        let text = summary(aggregate(pct: 0.896, total: 29))
        XCTAssertTrue(text.hasPrefix("Strong week"))
        XCTAssertTrue(text.contains("consistency at this level compounds"))
    }

    func test_summary_pctJustUnderSeventy_opensAndClosesAsSolidWeek() {
        let text = summary(aggregate(pct: 0.696, total: 23))
        XCTAssertTrue(text.hasPrefix("Solid week"))
        XCTAssertTrue(text.contains("tighten one missed dose"))
    }

    func test_summary_pctJustUnderForty_opensAndClosesAsMixedWeek() {
        let text = summary(aggregate(pct: 0.396, total: 48))
        XCTAssertTrue(text.hasPrefix("Mixed week"))
        XCTAssertTrue(text.contains("one consistent time block"))
    }

    func test_summary_pctAtSeventy_isSolidWeek() {
        let text = summary(aggregate(pct: 0.7))
        XCTAssertTrue(text.hasPrefix("Solid week"))
        XCTAssertTrue(text.contains("tighten one missed dose"))
    }

    func test_summary_pctAtForty_isMixedWeek() {
        let text = summary(aggregate(pct: 0.4))
        XCTAssertTrue(text.hasPrefix("Mixed week"))
        XCTAssertTrue(text.contains("one consistent time block"))
    }

    func test_summary_pctBelowForty_isQuietWeek() {
        let text = summary(aggregate(pct: 0.39))
        XCTAssertTrue(text.hasPrefix("Quiet week"))
        XCTAssertTrue(text.contains("Start with one dose tomorrow"))
    }

    func test_summary_noDosesScheduled_doesNotMentionDoses() {
        let text = summary(aggregate(pct: 0, total: 0, nutrition: nutrition(avgCalories: 2000)))
        XCTAssertFalse(text.lowercased().contains("dose"))
        XCTAssertTrue(text.hasPrefix("Your week in review — meals logged on 5 of 7 days."))
    }

    func test_summary_noDosesAndNoSignals_usesNeutralOpener() {
        let text = summary(aggregate(pct: 0, total: 0))
        XCTAssertFalse(text.lowercased().contains("dose"))
        XCTAssertTrue(text.hasPrefix("Your week in review."))
    }

    // MARK: - Observations

    func test_summary_noOptionalSignals_hasNoObservationParagraph() {
        let paragraphs = summary(aggregate()).components(separatedBy: "\n\n")
        XCTAssertEqual(paragraphs.count, 2)
    }

    func test_summary_hrvDeltaOfThree_isMentionedInBothDirections() {
        XCTAssertTrue(summary(aggregate(hrvDelta: 3)).contains("HRV moved up 3 ms"))
        XCTAssertTrue(summary(aggregate(hrvDelta: -3)).contains("HRV moved down 3 ms"))
    }

    func test_summary_hrvDeltaBelowThree_isOmitted() {
        XCTAssertFalse(summary(aggregate(hrvDelta: 2)).contains("HRV"))
    }

    func test_summary_outcomesPresent_reportsCompositeAverage() {
        let outcomes = WeeklyAggregate.Outcomes(
            energyAvg: 4, sleepAvg: 4, recoveryAvg: 4, moodAvg: 4, focusAvg: 4,
            compositeDelta: 0.5, checkInsCount: 5
        )
        XCTAssertTrue(summary(aggregate(outcomes: outcomes)).contains("averaged 4.0 of 5 — up from last week"))
    }

    func test_summary_nutritionWithinTarget_isOnTarget() {
        XCTAssertTrue(summary(aggregate(nutrition: nutrition(avgCalories: 2150))).contains("stayed on target"))
    }

    func test_summary_nutritionUnderTarget_isUnder() {
        XCTAssertTrue(summary(aggregate(nutrition: nutrition(avgCalories: 1849))).contains("under target at \(1849.formatted()) kcal/day"))
    }

    func test_summary_nutritionOverTarget_isOver() {
        XCTAssertTrue(summary(aggregate(nutrition: nutrition(avgCalories: 2151))).contains("over target at \(2151.formatted()) kcal/day"))
    }

    func test_summary_labPanels_pluralisesPanelWord() {
        XCTAssertTrue(summary(aggregate(newPanels: 1)).contains("Logged 1 new lab panel this week."))
        XCTAssertTrue(summary(aggregate(newPanels: 2)).contains("Logged 2 new lab panels this week."))
    }
}
