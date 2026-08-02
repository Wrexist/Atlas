import SwiftUI

/// Two-state card on the Lifestyle tab.
///
///   • **Empty** (no check-in for today yet) — a prompt with a
///     CTA button. Visually loud-ish so users notice the action;
///     the pulse animation draws the eye on first open of the day.
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
    @State private var promptPulse: Bool = false

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
        .onAppear {
            guard !reduceMotion, todayEntry == nil else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                promptPulse = true
            }
        }
    }

    // MARK: - Empty (prompt) state

    private var empty: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.45),
                                AppColor.accentLight.opacity(0.20),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .scaleEffect(promptPulse ? 1.06 : 1.0)
                Image(systemName: "heart.text.square.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily check-in")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Text("How are you feeling today?")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("30 seconds. Powers your correlation insights.")
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
        .background(cardBackground(tinted: true))
    }

    // MARK: - Filled (summary) state

    private func filled(entry: OutcomeEntry) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentLight.opacity(0.22))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.seal.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's check-in")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                scoreStrip(entry)
            }

            Spacer(minLength: 0)

            Text("Edit")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
        }
        .padding(Spacing.md)
        .background(cardBackground(tinted: false))
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

    private func cardBackground(tinted: Bool) -> some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary.opacity(0.55))
            .overlay {
                if tinted {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.14),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
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
