import SwiftUI

/// One-shot prompt that fires when `TimezoneChangeDetector` returns
/// a non-nil `Change` on app launch. Asks the user whether to
/// translate their dose schedule to the new local clock or keep
/// the original times. Either choice acknowledges the new
/// timezone so the prompt won't re-fire until they cross into a
/// different zone.
struct TravelModePromptSheet: View {
    let change: TimezoneChangeDetector.Change
    /// Preview of what a representative dose time would shift to —
    /// the first preferred time on the user's first active
    /// protocol, mapped through `TravelModeLogic.shiftTime`. Caller
    /// supplies it so the sheet doesn't have to reach back into
    /// `DataStore`.
    let exampleShift: (original: String, shifted: String)?
    /// User picked "shift my schedule". Caller applies the shift
    /// then dismisses.
    let onShift: () -> Void
    /// User picked "keep origin times". Caller acknowledges the
    /// timezone without shifting, then dismisses.
    let onKeep: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    hero
                    deltaCard
                    if let exampleShift {
                        exampleCard(original: exampleShift.original, shifted: exampleShift.shifted)
                    }
                    actions
                    disclaimer
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle("Travel detected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Closing without choosing is treated as "keep
                    // origin" — same outcome but without committing
                    // to the user. The detector won't refire until
                    // they cross into yet another zone.
                    Button("Later", action: onKeep)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.55),
                                AppColor.accentLight.opacity(0.25),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                Image(systemName: "airplane.departure")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }

            Text("You crossed into a new timezone")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Pick how Atlas should handle your dose schedule. You can change it back any time by editing the protocol.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deltaCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                row(
                    eyebrow: String(localized: "From"),
                    title: change.previousDisplayName,
                    tint: AppColor.textSecondary
                )
                Image(systemName: "arrow.down")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.leading, 6)
                row(
                    eyebrow: String(localized: "To"),
                    title: change.currentDisplayName,
                    tint: AppColor.accentLight
                )
                Divider().background(AppColor.glassBorder)
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                    Text(change.deltaPhrase)
                        .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                }
            }
        }
    }

    private func row(eyebrow: String, title: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(eyebrow)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: 44, alignment: .leading)
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func exampleCard(original: String, shifted: String) -> some View {
        GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Preview")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                HStack(spacing: Spacing.sm) {
                    Text(original)
                        .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                    Text(shifted)
                        .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                }
                Text("One of your scheduled doses, shifted to local time.")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            GlassButton(
                title: "Shift to local time",
                icon: "clock.arrow.2.circlepath",
                style: .primary,
                isFullWidth: true,
                action: onShift
            )

            GlassButton(
                title: "Keep origin times",
                icon: "house.fill",
                style: .secondary,
                isFullWidth: true,
                action: onKeep
            )
        }
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 1)
            Text("Shifting moves every active protocol's preferred dose times immediately. Most peptides tolerate the change without issue — consult your provider for compounds that demand strict timing windows.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
