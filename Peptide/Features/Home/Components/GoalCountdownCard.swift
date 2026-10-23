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

    /// Days the "Goal reached" state stays on Today before the card
    /// retires. Nothing on Today can set a new goal date, so a passed
    /// goal would otherwise hold the Momentum section indefinitely.
    static let reachedGraceDays = 7

    /// Whether Today should show the card for `goalDate` at `now`:
    /// through the countdown and for `reachedGraceDays` after it.
    static func isShown(goalDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let goalDate else { return false }
        let goalDay = calendar.startOfDay(for: goalDate)
        guard let retireDay = calendar.date(byAdding: .day, value: reachedGraceDays, to: goalDay) else {
            return true
        }
        return calendar.startOfDay(for: now) < retireDay
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
        TimelineView(.everyMinute) { context in
            if let goalDate, Self.isShown(goalDate: goalDate, now: context.date),
               let weeks = weeksRemaining, let days = daysRemaining {
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

    /// The section header above already says "Your goal", so the card
    /// only names which goal — and shows nothing when there isn't one.
    @ViewBuilder
    private var header: some View {
        if let label = primaryGoalLabel {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "flag.checkered")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
                Text(label)
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
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
                        .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        // The ring is a fixed 56pt; shrink rather than
                        // overflow it at accessibility text sizes.
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, Spacing.sm)
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
                    .font(AppFont.scaled(20, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal reached!")
                    .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Time to set your next one.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goal reached. Time to set your next one.")
    }

    /// Counts down in weeks, switching to days in the final week so the
    /// hero number never reads "0 weeks".
    private func countdown(weeks: Int, days: Int) -> some View {
        let inFinalWeek = weeks == 0
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(inFinalWeek ? days : weeks)")
                .font(AppFont.scaled(44, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 0) {
                Text(heroUnit(weeks: weeks, days: days))
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                Text(inFinalWeek ? "remaining" : "\(days) days remaining")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
        }
        // One stop: "8, weeks, 56 days remaining" instead of three.
        .accessibilityElement(children: .combine)
    }

    private func heroUnit(weeks: Int, days: Int) -> LocalizedStringKey {
        if weeks == 0 { return days == 1 ? "day" : "days" }
        return weeks == 1 ? "week" : "weeks"
    }

    private func footer(targetDate: Date) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "calendar")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
            Text("Target — \(targetDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                .font(AppFont.caption2)
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
