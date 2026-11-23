import XCTest
@testable import Peptide

/// Covers the onboarding page sequence (`OnboardingStep`) and the
/// defaults `OnboardingPlanEngine` applies when a value was skipped or
/// left untouched.
@MainActor
final class OnboardingFlowTests: XCTestCase {

    // MARK: - Page sequence

    func test_pageCount_isAtMostEight() {
        XCTAssertLessThanOrEqual(OnboardingStep.allCases.count, 8)
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
            "training", "permissions", "disclaimer", "plan",
        ])
    }

    func test_skip_isOfferedOnlyOnOptionalPages() {
        XCTAssertEqual(OnboardingStep.allCases.filter(\.isSkippable), [.permissions])
    }

    // MARK: - Progress and choice load

    func test_progressFraction_welcomeAlreadyBegun_planComplete() {
        XCTAssertGreaterThan(OnboardingStep.welcome.progressFraction, 0)
        XCTAssertEqual(OnboardingStep.plan.progressFraction, 1, accuracy: 0.0001)
    }

    func test_progressFraction_risesOnEveryStep() {
        let fractions = OnboardingStep.allCases.map(\.progressFraction)
        XCTAssertEqual(fractions, fractions.sorted())
        XCTAssertEqual(Set(fractions).count, fractions.count)
    }

    func test_visibleGoals_collapsed_showsSixFeaturedInCaseOrder() {
        let visible = OnboardingView.PrimaryGoal.visible(showingAll: false, selected: [])
        XCTAssertEqual(visible.count, 6)
        XCTAssertEqual(visible, OnboardingView.PrimaryGoal.allCases.filter(visible.contains))
    }

    func test_visibleGoals_selectionOutsideFeatured_showsEveryGoal() {
        let visible = OnboardingView.PrimaryGoal.visible(showingAll: false, selected: [.buildMuscle, .energy])
        XCTAssertEqual(visible, OnboardingView.PrimaryGoal.allCases)
    }

    func test_visibleGoals_expanded_showsEveryGoal() {
        XCTAssertEqual(
            OnboardingView.PrimaryGoal.visible(showingAll: true, selected: []),
            OnboardingView.PrimaryGoal.allCases
        )
    }

    // MARK: - Defaults for skipped or untouched data

    func test_untouchedBodyMetrics_stillProduceNutritionTargets() {
        XCTAssertNil(NutritionMath.recommendedTargets(for: .unspecified, goalRaw: nil))
        XCTAssertNotNil(NutritionMath.recommendedTargets(
            for: BodyMetricsRanges.filledWithDefaults(.unspecified),
            goalRaw: nil
        ))
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

    func test_goalWeeks_acrossDSTChange_countsWholeWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        // Sweden springs forward on 29 March 2026; the span loses an hour.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 9)))
        let goal = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 3, hour: 9)))
        XCTAssertEqual(OnboardingPlanEngine.goalWeeks(until: goal, from: now, calendar: calendar), 2)
    }

    // MARK: - Goal selection

    func test_toggling_firstGoal_becomesPrimary() {
        let result = OnboardingPlanEngine.toggling(.loseFat, in: [], primary: .buildMuscle)
        XCTAssertEqual(result.selected, [.loseFat])
        XCTAssertEqual(result.primary, .loseFat)
    }

    func test_toggling_laterGoal_keepsPrimary() {
        let result = OnboardingPlanEngine.toggling(.energy, in: [.loseFat], primary: .loseFat)
        XCTAssertEqual(result.selected, [.loseFat, .energy])
        XCTAssertEqual(result.primary, .loseFat)
    }

    func test_toggling_deselectingPrimary_promotesNextInCaseOrder() {
        let result = OnboardingPlanEngine.toggling(.loseFat, in: [.loseFat, .energy, .getStronger], primary: .loseFat)
        XCTAssertEqual(result.selected, [.energy, .getStronger])
        XCTAssertEqual(result.primary, .getStronger)
    }

    func test_toggling_deselectingLastGoal_leavesEmptySetAndKeepsPrimary() {
        let result = OnboardingPlanEngine.toggling(.recomp, in: [.recomp], primary: .recomp)
        XCTAssertTrue(result.selected.isEmpty)
        XCTAssertEqual(result.primary, .recomp)
    }

    // MARK: - Schedule

    func test_togglingPreferredDay_beyondWeeklyCount_raisesCount() {
        let result = OnboardingPlanEngine.togglingPreferredDay(.friday, in: [.monday, .wednesday, .thursday], daysPerWeek: 3)
        XCTAssertEqual(result.days, [.monday, .wednesday, .thursday, .friday])
        XCTAssertEqual(result.daysPerWeek, 4)
    }

    func test_togglingPreferredDay_pastRangeTop_isRefused() {
        let six: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let result = OnboardingPlanEngine.togglingPreferredDay(.sunday, in: six, daysPerWeek: 6)
        XCTAssertEqual(result.days, six)
        XCTAssertEqual(result.daysPerWeek, 6)
        XCTAssertTrue(OnboardingPlanEngine.daysPerWeekRange.contains(result.daysPerWeek))
    }

    func test_togglingPreferredDay_deselect_keepsCount() {
        let result = OnboardingPlanEngine.togglingPreferredDay(.monday, in: [.monday, .friday], daysPerWeek: 4)
        XCTAssertEqual(result.days, [.friday])
        XCTAssertEqual(result.daysPerWeek, 4)
    }

    func test_preferredDays_belowSelectedCount_dropsLatestDays() {
        let capped = OnboardingPlanEngine.preferredDays([.monday, .wednesday, .friday, .sunday], cappedAt: 2)
        XCTAssertEqual(capped, [.monday, .wednesday])
    }

    // MARK: - Projection

    func test_projectedLeanGain_isHalfToFullTypicalRate() {
        let gain = OnboardingPlanEngine.projectedLeanGainKg(experience: "beginner", weeks: 52)
        XCTAssertEqual(gain.upperBound, 9, accuracy: 0.0001)
        XCTAssertEqual(gain.lowerBound, 4.5, accuracy: 0.0001)
    }

    func test_projectedLeanGain_fallsWithExperience() {
        let beginner = OnboardingPlanEngine.projectedLeanGainKg(experience: "beginner", weeks: 12)
        let advanced = OnboardingPlanEngine.projectedLeanGainKg(experience: "advanced", weeks: 12)
        XCTAssertGreaterThan(beginner.upperBound, advanced.upperBound)
    }

    func test_projectedStrengthGain_longerSpan_promisesMore() {
        let eightWeeks = OnboardingPlanEngine.projectedStrengthGainPercent(experience: "intermediate", weeks: 8)
        let sixMonths = OnboardingPlanEngine.projectedStrengthGainPercent(experience: "intermediate", weeks: 26)
        XCTAssertLessThan(eightWeeks.upperBound, sixMonths.upperBound)
        XCTAssertLessThan(eightWeeks.lowerBound, sixMonths.lowerBound)
    }

    func test_projectedStrengthGain_beginnerOutpacesAdvanced() {
        let beginner = OnboardingPlanEngine.projectedStrengthGainPercent(experience: "beginner", weeks: 12)
        let advanced = OnboardingPlanEngine.projectedStrengthGainPercent(experience: "advanced", weeks: 12)
        XCTAssertGreaterThan(beginner.lowerBound, advanced.upperBound)
    }

    func test_projectedStrengthGain_longSpan_staysWithinForty() {
        let gain = OnboardingPlanEngine.projectedStrengthGainPercent(experience: "beginner", weeks: 104)
        XCTAssertLessThanOrEqual(gain.upperBound, 40)
        XCTAssertLessThanOrEqual(gain.lowerBound, gain.upperBound)
    }

    func test_projectedFatLoss_scalesWithSpanAndClamps() {
        XCTAssertEqual(OnboardingPlanEngine.projectedFatLossKg(weightKg: 80, weeks: 12), 4)
        XCTAssertEqual(OnboardingPlanEngine.projectedFatLossKg(weightKg: 80, weeks: 24), 8)
        XCTAssertEqual(OnboardingPlanEngine.projectedFatLossKg(weightKg: 150, weeks: 52), 10)
        XCTAssertEqual(OnboardingPlanEngine.projectedFatLossKg(weightKg: 50, weeks: 1), 1)
    }

    func test_projectedFatLoss_unknownWeight_assumes75Kg() {
        XCTAssertEqual(
            OnboardingPlanEngine.projectedFatLossKg(weightKg: nil, weeks: 12),
            OnboardingPlanEngine.projectedFatLossKg(weightKg: 75, weeks: 12)
        )
    }

    // MARK: - Saving answers over an existing profile

    func test_goalStep_deselectAfterBack_removesGoalFromProfile() {
        let saved = OnboardingPlanEngine.savedGoals(existing: [], selected: [.buildMuscle, .loseFat], primary: .buildMuscle)

        let afterBack = OnboardingPlanEngine.savedGoals(existing: Array(saved), selected: [.buildMuscle], primary: .buildMuscle)

        XCTAssertEqual(afterBack, ["buildMuscle"])
    }

    func test_goalStep_goalOnboardingDoesNotOffer_isKept() {
        let saved = OnboardingPlanEngine.savedGoals(
            existing: ["legacyFocus", "loseFat"],
            selected: [.getStronger],
            primary: .getStronger
        )

        XCTAssertEqual(saved, ["legacyFocus", "getStronger"])
    }

    func test_trainingStep_overSavedPreferences_keepsSettingsTheStepDoesNotAsk() {
        var saved = TrainingPreferences(restTimerDefault: 150, plateInventoryKg: [20, 10], autoProgression: false,
                                        equipmentAccess: [.barbell, .plate])
        saved.plateInventoryLb = [45, 25]
        saved.barWeightsKg = ["barbell": 15]
        saved.dailyStepGoal = 12_000

        let prefs = OnboardingPlanEngine.trainingPreferences(
            over: saved, daysPerWeek: 4, preferredDays: [.monday, .thursday],
            timeOfDay: .morning, equipment: [.dumbbell]
        )

        XCTAssertEqual(prefs.daysPerWeek, 4)
        XCTAssertEqual(prefs.restTimerDefault, 150)
        XCTAssertEqual(prefs.plateInventoryKg, [20, 10])
        XCTAssertEqual(prefs.plateInventoryLb, [45, 25])
        XCTAssertEqual(prefs.barWeightsKg, ["barbell": 15])
        XCTAssertFalse(prefs.autoProgression)
        XCTAssertEqual(prefs.dailyStepGoal, 12_000)
        XCTAssertEqual(prefs.equipmentAccess, [.dumbbell, .plate])
    }

    // MARK: - Plan summary

    func test_programSummary_namesTheSplitTheGeneratorBuilds() {
        for days in [3, 4, 5] {
            let summary = OnboardingPlanEngine.programSummary(goal: .buildMuscle, daysPerWeek: days)
            XCTAssertEqual(summary?.hasPrefix(TrainingSplit.forDays(days).displayName), true, "\(days) days: \(summary ?? "nil")")
        }
        XCTAssertEqual(
            OnboardingPlanEngine.programSummary(goal: .getStronger, daysPerWeek: 3),
            "\(TrainingSplit.fullBody.displayName) · \(TrainingGoal.strength.displayName)"
        )
    }

    func test_programSummary_nonTrainingGoal_hidesTheRow() {
        XCTAssertNil(OnboardingPlanEngine.programSummary(goal: .betterSleep, daysPerWeek: 4))
    }
}
