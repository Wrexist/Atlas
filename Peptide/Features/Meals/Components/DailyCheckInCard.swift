import SwiftUI

/// Two-state card on the Lifestyle tab.
///
///   • **Empty** (no check-in for today yet) — a prompt with a
///     CTA button. Visually loud-ish so users notice the action;
///     a brief artwork entrance introduces the action.
///   • **Filled** (today already checked in) — compact summary of
///     today's five scores with an "Edit" affordance for users
///     who want to correct a number.
///
/// This is the front door for outcome tracking. Until users build
/// a habit of filling it in, the correlation engine has nothing to
/// chew on — so the card has to be visible without being noisy.
struct DailyCheckInCard: View {
    let todayEntry: OutcomeEntry?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionTrigger = 0

    var body: some View {
        Button(action: onTap) {
            if let todayEntry {
                filled(entry: todayEntry)
            } else {
                empty
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(todayEntry == nil ? "Opens the daily check-in sheet." : "Opens the check-in to edit today's values.")
        .animation(AppAnimation.motionAware(AppAnimation.fadeIn, reduceMotion: reduceMotion), value: todayEntry == nil)
        .onChange(of: todayEntry == nil) { wasEmpty, isEmpty in
            if wasEmpty && !isEmpty { completionTrigger &+= 1 }
        }
    }

    // MARK: - Empty (prompt) state

    private var empty: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            MilestoneArtwork(symbol: "heart.text.square.fill", size: 44, style: .symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily check-in")
                    .font(AppFont.eyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight)
                Text("How are you feeling today?")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("30 seconds. Helps Atlas spot what's working.")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius, tinted: true)
    }

    // MARK: - Filled (summary) state

    private func filled(entry: OutcomeEntry) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            MilestoneArtwork(size: 48, trigger: completionTrigger, isActive: completionTrigger > 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's check-in")
                    .font(AppFont.eyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight)
                scoreStrip(entry)
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.xxs) {
                Text("Edit")
                    .font(AppFont.scaled(11, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
            }
            .foregroundStyle(AppColor.accentLight)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func scoreStrip(_ entry: OutcomeEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            ForEach(OutcomeDimension.allCases) { dim in
                let value = dim.value(in: entry)
                VStack(spacing: 2) {
                    Image(systemName: dim.icon)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(dim.tint)
                    Text("\(value)")
                        .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dim.displayName) \(value) of 5")
            }
        }
    }

    private var accessibilityLabel: String {
        guard let todayEntry else {
            return String(localized: "Daily check-in not done yet today")
        }
        let parts = OutcomeDimension.allCases.map { "\($0.displayName) \($0.value(in: todayEntry))" }
        return "Today's check-in: \(parts.joined(separator: ", "))"
    }
}
