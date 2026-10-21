import XCTest
@testable import Peptide

/// Covers the onboarding page sequence (`OnboardingStep`) and the
/// defaults `OnboardingPlanEngine` applies when a value was skipped or
/// left untouched.
@MainActor
final class OnboardingFlowTests: XCTestCase {

    // MARK: - Page sequence

    func test_pageCount_isAtMostNine() {
        XCTAssertLessThanOrEqual(OnboardingStep.allCases.count, 9)
    }

    func test_planSummary_isLastPageAndOnlyOneOpeningPaywall() {
        XCTAssertEqual(OnboardingStep.allCases.last, .plan)
        XCTAssertEqual(OnboardingStep.allCases.filter(\.presentsPaywall), [.plan])
    }

    func test_dataPages_allPrecedePlanSummary() {
        let dataPages: [OnboardingStep] = [.name, .goal, .bodyMetrics, .training]
        for step in dataPages {
            XCTAssertLessThan(step, .plan, "\(step) must feed the plan the paywall follows")
        }
    }

    func test_disclaimer_isAcknowledgedBeforePaywall() {
        XCTAssertLessThan(OnboardingStep.disclaimer, .plan)
    }

    func test_rawValues_areContiguousFromZero() {
        XCTAssertEqual(OnboardingStep.allCases.map(\.rawValue), Array(0..<OnboardingStep.allCases.count))
    }

    func test_nextAndPrevious_walkTheWholeSequence() {
        var step = OnboardingStep.welcome
        var visited = [step]
        while let next = step.next {
            XCTAssertEqual(next.previous, step)
            step = next
            visited.append(step)
        }
        XCTAssertEqual(visited, OnboardingStep.allCases)
        XCTAssertNil(OnboardingStep.welcome.previous)
    }

    func test_funnelNames_areUniqueAndStable() {
        let names = OnboardingStep.allCases.map(\.funnelName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names, [
            "welcome", "name", "goal_and_experience", "body_metrics",
            "training", "permissions", "referral", "disclaimer", "plan",
        ])
    }

    func test_skip_isOfferedOnlyOnOptionalPages() {
        XCTAssertEqual(OnboardingStep.allCases.filter(\.isSkippable), [.permissions, .referral])
    }

    // MARK: - Defaults for skipped or untouched data

    func test_untouchedBodyMetrics_resolveToDisplayedWheelDefaults() {
        let resolved = OnboardingPlanEngine.resolvedBodyMetrics(.unspecified)
        XCTAssertEqual(resolved.heightCm, Double(BodyMetricsRanges.defaultHeightCm))
        XCTAssertEqual(resolved.weightKg, Double(BodyMetricsRanges.defaultWeightKg))
        XCTAssertEqual(resolved.age, BodyMetricsRanges.defaultAge)
    }

    func test_untouchedBodyMetrics_stillProduceNutritionTargets() {
        XCTAssertNil(NutritionMath.dailyTargets(for: .unspecified))
        XCTAssertNotNil(NutritionMath.dailyTargets(for: OnboardingPlanEngine.resolvedBodyMetrics(.unspecified)))
    }

    func test_enteredBodyMetrics_areNeverOverwrittenByDefaults() {
        var metrics = BodyMetrics.unspecified
        metrics.heightCm = 190
        metrics.weightKg = 92
        metrics.age = 41
        let resolved = OnboardingPlanEngine.resolvedBodyMetrics(metrics)
        XCTAssertEqual(resolved.heightCm, 190)
        XCTAssertEqual(resolved.weightKg, 92)
        XCTAssertEqual(resolved.age, 41)
    }

    func test_defaultGoalDate_isTwelveWeeksOut() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = OnboardingPlanEngine.defaultGoalDate(from: now)
        XCTAssertEqual(OnboardingPlanEngine.goalWeeks(until: date, from: now), 12)
    }

    func test_goalWeeks_pastDate_clampsToOneWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(OnboardingPlanEngine.goalWeeks(until: now.addingTimeInterval(-86_400), from: now), 1)
    }

    func test_activityLevel_mapsExperienceAndDefaultsUnknownToLight() {
        XCTAssertEqual(OnboardingPlanEngine.activityLevel(forExperience: "beginner"), .light)
        XCTAssertEqual(OnboardingPlanEngine.activityLevel(forExperience: "intermediate"), .moderate)
        XCTAssertEqual(OnboardingPlanEngine.activityLevel(forExperience: "advanced"), .active)
        XCTAssertEqual(OnboardingPlanEngine.activityLevel(forExperience: "unknown"), .light)
    }

    func test_skippedTrainingPreferences_fallBackToThreeDaysBodyweight() {
        let defaults = TrainingPreferences()
        XCTAssertEqual(defaults.daysPerWeek, 3)
        XCTAssertEqual(defaults.timeOfDay, .anytime)
        XCTAssertEqual(defaults.equipmentAccess, [.bodyweight])
    }

    // MARK: - Plan summary

    func test_programName_coversEveryGoal() {
        for goal in OnboardingView.PrimaryGoal.allCases {
            XCTAssertFalse(OnboardingPlanEngine.programName(goal: goal, daysPerWeek: 3).isEmpty, "\(goal)")
        }
    }

    func test_programName_buildMuscle_switchesSplitAtFiveDays() {
        XCTAssertEqual(OnboardingPlanEngine.programName(goal: .buildMuscle, daysPerWeek: 4), "Upper / Lower")
        XCTAssertEqual(OnboardingPlanEngine.programName(goal: .buildMuscle, daysPerWeek: 5), "Push Pull Legs")
    }
}
