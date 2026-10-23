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
