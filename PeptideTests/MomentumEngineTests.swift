import XCTest
@testable import Peptide

final class MomentumEngineTests: XCTestCase {

    // MARK: - Daily points: empty / inactive

    func test_dailyPoints_noActiveDomains_returnsZero() {
        XCTAssertEqual(MomentumEngine.dailyPoints(.init()), 0)
    }

    func test_dailyPoints_nutritionTargetsButNoMeal_isZero() {
        // Targets make nutrition an active domain, but nothing logged → 0.
        let inputs = MomentumEngine.Inputs(hasNutritionTargets: true, mealLoggedToday: false)
        XCTAssertEqual(MomentumEngine.dailyPoints(inputs), 0)
    }

    func test_dailyPoints_noTargetsAndNoMeal_nutritionInactive() {
        // Without targets, an unlogged meal day shouldn't count nutrition at
        // all — so a habits-only user isn't diluted by an idle domain.
        let inputs = MomentumEngine.Inputs(habitsDone: 2, habitsDue: 2)
        XCTAssertEqual(MomentumEngine.dailyPoints(inputs), MomentumEngine.dailyMaxPoints)
    }

    // MARK: - Daily points: single domain

    func test_dailyPoints_habitsOnlyPerfectDay_isDailyMax() {
        let inputs = MomentumEngine.Inputs(habitsDone: 3, habitsDue: 3)
        XCTAssertEqual(MomentumEngine.dailyPoints(inputs), MomentumEngine.dailyMaxPoints)
    }

    func test_dailyPoints_habitsHalfDone_isHalfOfMax() {
        let inputs = MomentumEngine.Inputs(habitsDone: 1, habitsDue: 2)
        XCTAssertEqual(MomentumEngine.dailyPoints(inputs), MomentumEngine.dailyMaxPoints / 2)
    }

    func test_dailyPoints_mealLoggedWithoutTargets_isDailyMax() {
        let inputs = MomentumEngine.Inputs(mealLoggedToday: true)
        XCTAssertEqual(MomentumEngine.dailyPoints(inputs), MomentumEngine.dailyMaxPoints)
    }

    // MARK: - Daily points: redistributed across active domains

    func test_dailyPoints_ceilingIsSameRegardlessOfDomainCount() {
        // One perfect domain and three perfect domains both cap at the
        // daily max — partial-data users are never penalised.
        let oneDomain = MomentumEngine.Inputs(habitsDone: 1, habitsDue: 1)
        let threeDomains = MomentumEngine.Inputs(
            habitsDone: 2, habitsDue: 2,
            doseEntriesToday: 2, doseCompletedToday: 2,
            hasNutritionTargets: true, mealLoggedToday: true
        )
        XCTAssertEqual(MomentumEngine.dailyPoints(oneDomain), MomentumEngine.dailyMaxPoints)
        XCTAssertEqual(MomentumEngine.dailyPoints(threeDomains), MomentumEngine.dailyMaxPoints)
    }

    func test_dailyPoints_twoDomainsOneComplete_isHalfMax() {
        // Habits perfect (1.0), doses none (0.0) → 0.5 of the ceiling.
        let inputs = MomentumEngine.Inputs(
            habitsDone: 1, habitsDue: 1,
            doseEntriesToday: 2, doseCompletedToday: 0
        )
        XCTAssertEqual(MomentumEngine.dailyPoints(inputs), MomentumEngine.dailyMaxPoints / 2)
    }

    // MARK: - Level curve

    func test_level_baselineIsOne() {
        XCTAssertEqual(MomentumEngine.level(for: 0), 1)
        XCTAssertEqual(MomentumEngine.level(for: -10), 1)
    }

    func test_pointsRequired_levelOneIsFree_andIncreasesMonotonically() {
        XCTAssertEqual(MomentumEngine.pointsRequired(forLevel: 1), 0)
        var previous = MomentumEngine.pointsRequired(forLevel: 1)
        for level in 2...60 {
            let required = MomentumEngine.pointsRequired(forLevel: level)
            XCTAssertGreaterThan(required, previous, "Level \(level) must cost more than \(level - 1)")
            previous = required
        }
    }

    func test_level_crossesAtThreshold() {
        let level2Threshold = MomentumEngine.pointsRequired(forLevel: 2)
        XCTAssertEqual(MomentumEngine.level(for: level2Threshold - 1), 1)
        XCTAssertEqual(MomentumEngine.level(for: level2Threshold), 2)

        let level3Threshold = MomentumEngine.pointsRequired(forLevel: 3)
        XCTAssertEqual(MomentumEngine.level(for: level3Threshold - 1), 2)
        XCTAssertEqual(MomentumEngine.level(for: level3Threshold), 3)
    }

    // MARK: - Snapshot

    func test_snapshot_freshUser_isLevelOneBronzeNoProgress() {
        let snapshot = MomentumEngine.snapshot(score: 0, todayEarned: 0)
        XCTAssertEqual(snapshot.level, 1)
        XCTAssertEqual(snapshot.tier, .bronze)
        XCTAssertEqual(snapshot.pointsIntoLevel, 0)
        XCTAssertEqual(snapshot.progressInLevel, 0, accuracy: 0.0001)
    }

    func test_snapshot_progressWithinLevel_isProportional() {
        // Halfway between level 1 (0 pts) and level 2.
        let span = MomentumEngine.pointsRequired(forLevel: 2)
        let snapshot = MomentumEngine.snapshot(score: span / 2, todayEarned: 0)
        XCTAssertEqual(snapshot.level, 1)
        XCTAssertEqual(snapshot.progressInLevel, 0.5, accuracy: 0.05)
        XCTAssertEqual(snapshot.pointsIntoLevel + snapshot.pointsToNextLevel, snapshot.pointsForNextLevel)
    }

    func test_snapshot_progressInLevelStaysClamped() {
        for score in stride(from: 0, through: 5000, by: 137) {
            let snapshot = MomentumEngine.snapshot(score: score, todayEarned: 0)
            XCTAssertGreaterThanOrEqual(snapshot.progressInLevel, 0)
            XCTAssertLessThanOrEqual(snapshot.progressInLevel, 1)
        }
    }

    func test_snapshot_negativeTodayEarnedClampsToZero() {
        let snapshot = MomentumEngine.snapshot(score: 100, todayEarned: -20)
        XCTAssertEqual(snapshot.todayEarned, 0)
    }

    // MARK: - Tiers

    func test_tier_bandsByLevel() {
        XCTAssertEqual(MomentumEngine.Tier.forLevel(1), .bronze)
        XCTAssertEqual(MomentumEngine.Tier.forLevel(9), .bronze)
        XCTAssertEqual(MomentumEngine.Tier.forLevel(10), .silver)
        XCTAssertEqual(MomentumEngine.Tier.forLevel(20), .gold)
        XCTAssertEqual(MomentumEngine.Tier.forLevel(40), .platinum)
        XCTAssertEqual(MomentumEngine.Tier.forLevel(70), .diamond)
        XCTAssertEqual(MomentumEngine.Tier.forLevel(500), .diamond)
    }
}
