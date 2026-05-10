import SwiftUI

/// Modal nudge presented from `HomeView` when a protocol crosses a
/// milestone (Day 7, Day 30, cycle completion). Two paths out:
/// "Share now" pushes the user into the existing share preview with
/// the relevant protocol pre-selected; "Not now" dismisses without
/// opening anything. Either choice marks the milestone as shown so
/// the user isn't re-prompted on the next Home appearance.
struct CycleMilestonePromptSheet: View {
    let proto: PeptideProtocol
    let milestone: CycleMilestoneService.Milestone
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: AppColor.accentGlow, radius: 18, y: 6)
                Image(systemName: glyph)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: Spacing.sm) {
                Text(milestone.prompt)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            VStack(spacing: Spacing.sm) {
                GlassButton(
                    title: "Share now",
                    icon: "square.and.arrow.up",
                    style: .primary,
                    isFullWidth: true,
                    action: onShare
                )
                GlassButton(
                    title: "Not now",
                    style: .ghost,
                    isFullWidth: true,
                    action: onDismiss
                )
            }
            .padding(.horizontal, Spacing.screenPadding)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var glyph: String {
        switch milestone {
        case .day7:      "calendar"
        case .day30:     "calendar.badge.clock"
        case .completed: "checkmark.seal.fill"
        }
    }

    private var subtitle: String {
        switch milestone {
        case .day7:
            return "A week of consistency on \(proto.name) — show off the streak."
        case .day30:
            return "30 days in on \(proto.name). Your stats look great."
        case .completed:
            return "\(proto.name) is complete. Drop the wrap-up into a story."
        }
    }
}
