import SwiftUI

/// Sits under Today's day switcher while an earlier day is shown: names
/// the day, says the view is a read-only look back, and is the one-tap
/// way home. The switcher's own "Tap for today" title is easy to miss;
/// this is the affordance nobody has to discover.
struct PastDayBanner: View {
    let dayTitle: String
    let onBackToToday: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dayTitle)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Looking back — logging stays on today.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: Spacing.xs)

            Button {
                Haptics.selection()
                onBackToToday()
            } label: {
                Text("Back to today")
                    .font(AppFont.chipText)
                    .foregroundStyle(AppColor.onAccent)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule(style: .continuous).fill(AppColor.accentFill))
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle())
        }
        .padding(Spacing.md)
        .glassControl(
            .rect(cornerRadius: Spacing.controlCornerRadius),
            tint: AppColor.accentPrimary.opacity(0.08),
            border: AppColor.glassBorder
        )
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        PastDayBanner(dayTitle: "Yesterday", onBackToToday: {})
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
