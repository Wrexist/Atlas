import SwiftUI

/// Compact, low-key streak indicator for the Lifestyle tab's meal
/// section. Mirrors the peptide-side `StreakCounterView` semantics
/// (flame color escalating with streak length, milestone pulse on
/// crossing a threshold) so habit feedback feels consistent across
/// the two pillars of the app, but stays visually contained so it
/// doesn't compete with the macro rings for attention.
///
/// Hidden entirely when both the active and best streak are zero —
/// a fresh-install Lifestyle tab shouldn't be cluttered with "0 day
/// streak" pessimism. Surfaces once the user has logged at least
/// one meal historically.
struct MealStreakBadge: View {
    let currentStreak: Int
    let bestStreak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseTrigger: Int = 0
    @State private var milestoneScale: CGFloat = 1.0

    /// Streak lengths that warrant the bigger celebration — first
    /// week, two weeks, monthly cadence, half-year, year. Tuned to
    /// avoid celebrating every increment so the milestone moments
    /// stay meaningful.
    private static let milestones: Set<Int> = [3, 7, 14, 30, 60, 90, 180, 365]

    private var flameTint: Color {
        switch currentStreak {
        case 0:        return AppColor.textTertiary
        case 1...2:    return AppColor.accentPrimary
        case 3...6:    return AppColor.accentLight
        case 7...29:   return AppColor.warning
        default:       return AppColor.streak
        }
    }

    private var shouldShowGlow: Bool { currentStreak >= 7 }
    private var isNewBest: Bool { currentStreak > 0 && currentStreak >= bestStreak }
    private var isHidden: Bool { currentStreak == 0 && bestStreak == 0 }

    var body: some View {
        if isHidden {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Spacing.sm) {
            flameIcon
            VStack(alignment: .leading, spacing: 2) {
                headlineRow
                subtitleRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(flameTint.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(flameTint.opacity(0.30), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .onChange(of: currentStreak) { oldValue, newValue in
            pulseTrigger &+= 1
            guard !reduceMotion,
                  newValue > oldValue,
                  Self.milestones.contains(newValue)
            else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) {
                milestoneScale = 1.20
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                    milestoneScale = 1.0
                }
            }
        }
    }

    private var flameIcon: some View {
        Image(systemName: "flame.fill")
            .font(AppFont.scaled(18, weight: .semibold))
            .foregroundStyle(flameTint)
            .symbolEffect(.bounce, value: pulseTrigger)
            .scaleEffect(milestoneScale)
            .shadow(
                color: shouldShowGlow ? flameTint.opacity(0.55) : .clear,
                radius: 8,
                y: 2
            )
            .frame(width: 24)
    }

    @ViewBuilder
    private var headlineRow: some View {
        if currentStreak > 0 {
            HStack(spacing: 4) {
                Text("\(currentStreak)")
                    .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
                Text(currentStreak == 1 ? "day streak" : "day meal streak")
                    .font(AppFont.scaled(12, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
            }
        } else {
            Text("Streak paused")
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    @ViewBuilder
    private var subtitleRow: some View {
        if currentStreak == 0 && bestStreak > 0 {
            Text("Best: \(bestStreak) days. Log a meal to restart.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
        } else if isNewBest && currentStreak > 1 {
            Text("New personal best — keep going.")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(flameTint)
        } else if bestStreak > currentStreak {
            Text("Best: \(bestStreak) days")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
        } else if currentStreak >= 7 {
            Text("On fire 🔥")
                .font(AppFont.scaled(11, weight: .medium))
                .foregroundStyle(flameTint)
        }
    }

    private var voiceOverLabel: String {
        if currentStreak == 0 && bestStreak > 0 {
            return String(
                localized: "Meal-logging streak paused. Best streak \(bestStreak) days.",
                comment: "VoiceOver readout when the streak has lapsed but a personal best exists."
            )
        }
        if currentStreak == 0 {
            return String(localized: "No meal-logging streak yet.")
        }
        if isNewBest && currentStreak > 1 {
            return String(
                localized: "\(currentStreak) day meal-logging streak. New personal best.",
                comment: "VoiceOver readout when the current streak ties or beats the previous best."
            )
        }
        return String(
            localized: "\(currentStreak) day meal-logging streak. Best \(bestStreak) days.",
            comment: "VoiceOver readout for an active streak below the personal best."
        )
    }
}
