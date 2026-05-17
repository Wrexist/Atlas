import SwiftUI

/// Surfaces the user's committed goal date from onboarding's "By when?"
/// step. Renders the weeks remaining, the target date, and the primary
/// goal label. Hides itself when no goal date has been set so older
/// profiles (and users who skipped the goal-date step) don't see an
/// empty card.
struct GoalCountdownCard: View {
    let goalDate: Date?
    let primaryGoal: String?

    private var weeksRemaining: Int? {
        guard let goalDate else { return nil }
        let seconds = goalDate.timeIntervalSince(Date())
        guard seconds > 0 else { return 0 }
        return max(0, Int(seconds / (60 * 60 * 24 * 7)))
    }

    private var daysRemaining: Int? {
        guard let goalDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: goalDate)
        let comps = calendar.dateComponents([.day], from: start, to: end)
        return max(0, comps.day ?? 0)
    }

    private var primaryGoalLabel: String? {
        guard let primaryGoal, !primaryGoal.isEmpty else { return nil }
        // Translate the camelCase raw into the same display name the
        // onboarding flow renders. Keeps the home tile aligned with
        // the Ready summary row the user just saw.
        switch primaryGoal {
        case "buildMuscle":    return "Build muscle"
        case "loseFat":        return "Lose fat"
        case "getStronger":    return "Get stronger"
        case "stayConsistent": return "Stay consistent"
        case "athletic":       return "Athletic performance"
        case "recomp":         return "Recomp"
        case "betterSleep":    return "Better sleep"
        case "recovery":       return "Faster recovery"
        case "antiAging":      return "Anti-aging"
        case "skinHair":       return "Skin & hair"
        case "energy":         return "More energy"
        default:               return primaryGoal.capitalized
        }
    }

    var body: some View {
        if let goalDate, let weeks = weeksRemaining, let days = daysRemaining {
            GlassCard(tinted: true) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    countdown(weeks: weeks, days: days)
                    footer(targetDate: goalDate)
                }
            }
        } else {
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text("YOUR GOAL")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            if let label = primaryGoalLabel {
                Text(label)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
    }

    private func countdown(weeks: Int, days: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(weeks)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 0) {
                Text(weeks == 1 ? "week" : "weeks")
                    .font(AppFont.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                Text("\(days) day\(days == 1 ? "" : "s") remaining")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
        }
    }

    private func footer(targetDate: Date) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
            Text("Target — \(targetDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}

#Preview("Active goal") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        GoalCountdownCard(
            goalDate: Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()),
            primaryGoal: "buildMuscle"
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("Nil goal") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        GoalCountdownCard(goalDate: nil, primaryGoal: nil)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
