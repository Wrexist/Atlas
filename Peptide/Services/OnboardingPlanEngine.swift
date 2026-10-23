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

    // MARK: - Schedule

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

    /// Body weight lost over `weeks`: 5 % of body weight per twelve weeks
    /// (75 kg assumed when unknown), rounded to whole kilograms and held
    /// between 1 and 10.
    static func projectedFatLossKg(weightKg: Double?, weeks: Int) -> Double {
        let perTwelveWeeks = (weightKg ?? 75) * 0.05
        return min(10, max(1, (perTwelveWeeks * Double(weeks) / 12).rounded()))
    }

    /// Program named on the plan summary. Every goal is covered so the
    /// summary never falls through to a blank row.
    static func programName(goal: OnboardingView.PrimaryGoal, daysPerWeek: Int) -> String {
        switch goal {
        case .getStronger:    return "5/3/1 Strength"
        case .buildMuscle:    return daysPerWeek >= 5 ? "Push Pull Legs" : "Upper / Lower"
        case .loseFat:        return "Full Body Hypertrophy"
        case .athletic:       return "Athletic Conditioning"
        case .recomp:         return "Hybrid Recomp"
        case .stayConsistent: return "Consistency Builder"
        case .betterSleep:    return "Recovery & Sleep Hygiene"
        case .recovery:       return "Active Recovery Plan"
        case .antiAging:      return "Healthy Aging Plan"
        case .skinHair:       return "Look & Feel Plan"
        case .energy:         return "Energy & Vitality Plan"
        }
    }
}
