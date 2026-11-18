import Foundation

/// Pure computation behind the onboarding plan summary: the defaults a
/// value falls back to when its page was skipped or left untouched, and
/// the program the summary recommends.
enum OnboardingPlanEngine {
    /// Goal horizon used when the user never touches the date chips.
    static let defaultGoalWeeks = 12

    static func defaultGoalDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .weekOfYear, value: defaultGoalWeeks, to: now)
            ?? now.addingTimeInterval(TimeInterval(defaultGoalWeeks * 7 * 24 * 60 * 60))
    }

    /// Weeks from today to the goal date, counted in calendar days and
    /// rounded (truncating read "11 weeks" seconds after tapping
    /// "12 wks"), clamped to at least one.
    static func goalWeeks(until goalDate: Date, from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: goalDate)
        ).day ?? 0
        return max(1, Int((Double(days) / 7).rounded()))
    }

    /// Maps the lifting-experience answer to the closest TDEE activity
    /// bucket. Conservative — an unknown value reads as a beginner, and
    /// the user can tune it in Profile once their volume warrants.
    static func activityLevel(forExperience rawValue: String) -> ActivityLevel {
        switch OnboardingView.Experience(rawValue: rawValue) ?? .beginner {
        case .beginner:     return .light
        case .intermediate: return .moderate
        case .advanced:     return .active
        }
    }

    // MARK: - Goal selection

    /// The goal set and primary goal after tapping `goal`. The first pick
    /// becomes primary; removing the primary promotes the next selected
    /// goal in `allCases` order, so the projection and date tint never
    /// point at a deselected goal. With nothing left selected the primary
    /// is kept, and the page's Continue stays disabled.
    static func toggling(
        _ goal: OnboardingView.PrimaryGoal,
        in selected: Set<OnboardingView.PrimaryGoal>,
        primary: OnboardingView.PrimaryGoal
    ) -> (selected: Set<OnboardingView.PrimaryGoal>, primary: OnboardingView.PrimaryGoal) {
        var selected = selected
        var primary = primary
        if selected.remove(goal) != nil {
            if primary == goal {
                primary = OnboardingView.PrimaryGoal.allCases.first { selected.contains($0) } ?? primary
            }
        } else {
            if selected.isEmpty { primary = goal }
            selected.insert(goal)
        }
        return (selected, primary)
    }

    /// The goals to save from the goal step. Onboarding's own goals come
    /// from this run's selection, so one deselected after Back (or on a
    /// re-run over a synced profile) is removed; saved keys onboarding
    /// doesn't offer are kept.
    static func savedGoals(
        existing: [String],
        selected: Set<OnboardingView.PrimaryGoal>,
        primary: OnboardingView.PrimaryGoal
    ) -> Set<String> {
        let notOffered = existing.filter { OnboardingView.PrimaryGoal(rawValue: $0) == nil }
        return Set(notOffered)
            .union(selected.map(\.rawValue))
            .union([primary.rawValue])
    }

    // MARK: - Schedule

    /// The training step's answers written over the saved preferences, so
    /// a re-run (onboarding replays on every reinstall over the synced
    /// profile) keeps rest timer, plates, bar weights, auto-progression
    /// and step goal. Kinds the step has no card for stay in equipment.
    static func trainingPreferences(
        over saved: TrainingPreferences?,
        daysPerWeek: Int,
        preferredDays: Set<Weekday>,
        timeOfDay: PreferredTimeOfDay,
        equipment: Set<EquipmentKind>
    ) -> TrainingPreferences {
        var prefs = saved ?? TrainingPreferences()
        prefs.daysPerWeek = daysPerWeek
        prefs.preferredDays = preferredDays
        prefs.timeOfDay = timeOfDay
        prefs.equipmentAccess = equipment.union(prefs.equipmentAccess.subtracting(EquipmentKind.accessChoices))
        return prefs
    }

    /// Training days per week the schedule step offers.
    static let daysPerWeekRange = 2...6

    /// Preferred days trimmed to the weekly count, dropping the latest
    /// days of the week first.
    static func preferredDays(_ days: Set<Weekday>, cappedAt count: Int) -> Set<Weekday> {
        guard days.count > count else { return days }
        return Set(Weekday.allCases.filter(days.contains).prefix(count))
    }

    /// Preferred days and weekly count after tapping `day`. Picking more
    /// days than the weekly count raises the count; a pick past the
    /// range's top is refused, so the count never leaves the stepper.
    static func togglingPreferredDay(
        _ day: Weekday,
        in days: Set<Weekday>,
        daysPerWeek: Int
    ) -> (days: Set<Weekday>, daysPerWeek: Int) {
        var days = days
        if days.remove(day) != nil { return (days, daysPerWeek) }
        guard days.count < daysPerWeekRange.upperBound else { return (days, daysPerWeek) }
        days.insert(day)
        return (days, max(daysPerWeek, days.count))
    }

    // MARK: - Projection

    /// Lean mass gained over `weeks`, as a range from half the typical
    /// rate for the experience level up to it — a projection shown before
    /// the paywall shouldn't promise more than training delivers.
    static func projectedLeanGainKg(experience rawValue: String, weeks: Int) -> ClosedRange<Double> {
        let months = Double(weeks) * 12 / 52
        let upper = monthlyLeanGainKg(experience: rawValue) * months
        return (upper / 2)...upper
    }

    /// Typical lean-mass gain per month on a good program, which falls
    /// steeply with training age.
    static func monthlyLeanGainKg(experience rawValue: String) -> Double {
        switch OnboardingView.Experience(rawValue: rawValue) ?? .beginner {
        case .beginner:     return 0.75
        case .intermediate: return 0.4
        case .advanced:     return 0.2
        }
    }

    /// Top-lift increase over `weeks`, in whole percent: the twelve-week
    /// range falls steeply with training age and scales with the span,
    /// held between 1 and 40 so a long span never promises the moon.
    static func projectedStrengthGainPercent(experience rawValue: String, weeks: Int) -> ClosedRange<Int> {
        let perTwelveWeeks: ClosedRange<Double>
        switch OnboardingView.Experience(rawValue: rawValue) ?? .beginner {
        case .beginner:     perTwelveWeeks = 15...25
        case .intermediate: perTwelveWeeks = 8...12
        case .advanced:     perTwelveWeeks = 3...6
        }
        let scale = Double(weeks) / 12
        let lower = min(40, max(1, Int((perTwelveWeeks.lowerBound * scale).rounded())))
        let upper = min(40, max(lower, Int((perTwelveWeeks.upperBound * scale).rounded())))
        return lower...upper
    }

    /// Body weight lost over `weeks`: 5 % of body weight per twelve weeks
    /// (75 kg assumed when unknown), rounded to whole kilograms and held
    /// between 1 and 10.
    static func projectedFatLossKg(weightKg: Double?, weeks: Int) -> Double {
        let perTwelveWeeks = (weightKg ?? 75) * 0.05
        return min(10, max(1, (perTwelveWeeks * Double(weeks) / 12).rounded()))
    }

    /// The program the plan summary names: the split and focus the
    /// program generator actually builds for this goal and week, in the
    /// app's own localized names. Nil for goals that aren't about a
    /// training program, so the summary leaves the row out.
    static func programSummary(goal: OnboardingView.PrimaryGoal, daysPerWeek: Int) -> String? {
        switch goal {
        case .buildMuscle, .loseFat, .getStronger, .stayConsistent, .athletic, .recomp:
            let split = TrainingSplit.forDays(daysPerWeek).displayName
            let focus = TrainingGoal(goalRaw: goal.rawValue).displayName
            return "\(split) · \(focus)"
        case .betterSleep, .recovery, .antiAging, .skinHair, .energy:
            return nil
        }
    }
}
