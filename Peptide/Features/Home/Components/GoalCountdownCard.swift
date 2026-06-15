import SwiftUI

/// Surfaces the user's committed goal date from onboarding's "By when?"
/// step. Renders the weeks remaining, the target date, and the primary
/// goal label. Hides itself when no goal date has been set so older
/// profiles (and users who skipped the goal-date step) don't see an
/// empty card.
struct GoalCountdownCard: View {
    let goalDate: Date?
    let primaryGoal: String?
    /// Journey start (the user's `memberSince`, set at onboarding alongside
    /// the goal date) used to draw the progress ring. Nil hides the ring and
    /// keeps the plain countdown — so existing call sites / previews are
    /// unaffected.
    var startDate: Date? = nil

    /// 0…1 elapsed from `startDate` to `goalDate`. Nil when there's no start
    /// reference or a degenerate range.
    private var progressFraction: Double? {
        guard let goalDate, let startDate else { return nil }
        let total = goalDate.timeIntervalSince(startDate)
        guard total > 0 else { return nil }
        return min(1, max(0, Date().timeIntervalSince(startDate) / total))
    }

    /// True once the target date has arrived (or passed).
    private var isReached: Bool {
        guard let goalDate else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: goalDate) <= calendar.startOfDay(for: Date())
    }

    private var weeksRemaining: Int? {
        // Calendar-based so DST transitions don't shift the math by an
        // hour and produce off-by-one weeks (audit code-review #12).
        guard let daysRemaining else { return nil }
        return max(0, daysRemaining / 7)
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
        // Look up the canonical display name via OnboardingView's
        // PrimaryGoal enum so this surface stays in lock-step on
        // future expansions. Falls back to a capitalized version of
        // the stored key for legacy / unknown values.
        if let known = OnboardingView.PrimaryGoal(rawValue: primaryGoal) {
            return known.displayName
        }
        return primaryGoal.capitalized
    }

    var body: some View {
        // Re-evaluate at the start of every minute so a user who
        // leaves the app foregrounded across midnight sees the
        // countdown tick down without having to navigate away and
        // back (audit code-review #17). .everyMinute is conservative
        // enough that the cost is negligible.
        TimelineView(.everyMinute) { _ in
            if let goalDate, let weeks = weeksRemaining, let days = daysRemaining {
                GlassCard(tinted: true) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        header
                        if isReached {
                            reachedState
                        } else {
                            progressRow(weeks: weeks, days: days)
                        }
                        footer(targetDate: goalDate)
                    }
                }
            } else {
                EmptyView()
            }
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

    /// Progress ring (elapsed toward the goal) beside the weeks/days
    /// countdown. The ring is omitted when no `startDate` is supplied.
    @ViewBuilder
    private func progressRow(weeks: Int, days: Int) -> some View {
        HStack(spacing: Spacing.md) {
            if let fraction = progressFraction {
                MetricRing(
                    progress: fraction,
                    diameter: 56,
                    strokeWidth: 6,
                    gradient: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                    appearAnimated: true
                ) {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .accessibilityHidden(true)
            }
            countdown(weeks: weeks, days: days)
        }
    }

    private var reachedState: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal reached!")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Time to set your next one.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goal reached. Time to set your next one.")
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
