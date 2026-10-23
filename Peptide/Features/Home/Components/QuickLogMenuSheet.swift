import SwiftUI

/// Today's quick-log menu, opened from the jump bar's "+ Log" control.
/// Replaces a system confirmation dialog with the same actions, but each
/// row says what it does so the choice reads at a glance. The sheet only
/// reports the pick — the presenter dismisses it and mounts the follow-up
/// sheet, since SwiftUI can't present that one from in here.
struct QuickLogMenuSheet: View {
    /// `nil` hides the dose row, keeping the old dialog's gate.
    let nextDose: ProtocolEntry?
    let onSnapMeal: () -> Void
    let onLogNextDose: () -> Void

    /// Seeded near the two-row height so the first frame isn't a sliver;
    /// the measured value takes over before the slide-up settles.
    @State private var contentHeight: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
                .staggeredAppear(index: 0)

            VStack(spacing: Spacing.sm) {
                row(
                    title: "Snap a meal photo",
                    subtitle: Text("Snap or pick a photo, then fine-tune portions"),
                    systemImage: "camera.fill",
                    tint: AppColor.macroCarbs,
                    index: 1,
                    action: onSnapMeal
                )
                if let nextDose {
                    row(
                        title: "Log next dose",
                        subtitle: Text("\(nextDose.peptide.abbreviation) at \(nextDose.date, format: .dateTime.hour().minute())"),
                        systemImage: "syringe.fill",
                        tint: AppColor.accentPrimary,
                        index: 2,
                        action: onLogNextDose
                    )
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.lg)
        // Measure the ideal height, not whatever the current detent allows,
        // or a too-short seed would shrink the content and lock itself in.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .liquidGlassPresentation(detents: [.height(contentHeight)])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Quick log")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            Text("Log a meal or your next dose.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(
        title: LocalizedStringKey,
        subtitle: Text,
        systemImage: String,
        tint: Color,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(tint.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    subtitle
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: Spacing.cardCornerRadius))
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityLabel(Text(title))
        .accessibilityHint(subtitle)
        .staggeredAppear(index: index)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            QuickLogMenuSheet(nextDose: nil, onSnapMeal: {}, onLogNextDose: {})
        }
}
