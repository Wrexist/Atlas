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
        .accessibilityIdentifier("daily-check-in-card")
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

    /// The header on one row and the five scores on a full-width row of
    /// their own, so each score has room for its name. Squeezed between
    /// the artwork and "Edit" the strip had only icons, which nobody could
    /// read without guessing, and at accessibility sizes it pushed the
    /// Today stack past both screen edges.
    private func filled(entry: OutcomeEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.md) {
                filledArtwork
                filledEyebrow
                Spacer(minLength: 0)
                editAffordance
            }
            scoreStrip(entry)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private var filledArtwork: some View {
        MilestoneArtwork(size: 36, trigger: completionTrigger, isActive: completionTrigger > 0)
    }

    private var filledEyebrow: some View {
        Text("Today's check-in")
            .font(AppFont.eyebrow)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.accentLight)
    }

    private var editAffordance: some View {
        HStack(spacing: Spacing.xxs) {
            Text("Edit")
                .font(AppFont.scaled(11, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
        }
        .foregroundStyle(AppColor.accentLight)
    }

    private func scoreStrip(_ entry: OutcomeEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            ForEach(OutcomeDimension.allCases) { dim in
                let value = dim.value(in: entry)
                VStack(spacing: 2) {
                    // One accent on Today: the icon names the dimension,
                    // the number carries the value.
                    Image(systemName: dim.icon)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("\(value)")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text(dim.displayName)
                        .font(AppFont.scaled(11, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        let parts = OutcomeDimension.allCases.map { String(localized: "\($0.displayName) \($0.value(in: todayEntry)) of 5") }
        return String(localized: "Today's check-in: \(parts.joined(separator: ", "))")
    }
}
