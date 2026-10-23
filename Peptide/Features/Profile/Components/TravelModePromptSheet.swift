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
                    // Closing keeps the origin times and acknowledges the
                    // zone — the detector won't refire until the user
                    // crosses into yet another one — so the label says
                    // that rather than promising to ask again later.
                    Button("Keep times", action: onKeep)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 68, height: 68)
                Image(systemName: "airplane.departure")
                    .font(AppFont.scaled(28, weight: .semibold, relativeTo: .title1))
                    .foregroundStyle(AppColor.accentLight)
            }
            .accessibilityHidden(true)

            Text("You crossed into a new timezone")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Shift your reminder times to local time? You can change it back any time by editing the protocol.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deltaCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // A Grid sizes the label column to its widest eyebrow, so
                // "From" and "To" line up without a fixed width that
                // clips them at large Dynamic Type.
                Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
                    row(
                        eyebrow: String(localized: "From"),
                        title: change.previousDisplayName,
                        tint: AppColor.textSecondary
                    )
                    GridRow {
                        Image(systemName: "arrow.down")
                            .font(AppFont.scaled(11, weight: .heavy))
                            .foregroundStyle(AppColor.textTertiary)
                            .padding(.leading, 6)
                    }
                    row(
                        eyebrow: String(localized: "To"),
                        title: change.currentDisplayName,
                        tint: AppColor.accentLight
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider().overlay(AppColor.glassBorder)
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
        GridRow(alignment: .firstTextBaseline) {
            Text(eyebrow)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(tint.opacity(0.85))
                .fixedSize()
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
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
                Text("One of your reminders, shifted to local time.")
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
            Text("Shifting moves every active protocol's reminder times immediately.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
