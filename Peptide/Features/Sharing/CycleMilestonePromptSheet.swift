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

            // The milestone family's sculpted object, not a glowing
            // gradient disc — the same artwork onboarding's heroes use.
            MilestoneArtwork(symbol: glyph, size: 96, style: .symbol, isActive: true)
                .accessibilityHidden(true)
                .staggeredAppear(index: 0)

            VStack(spacing: Spacing.sm) {
                Text(milestone.prompt)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .staggeredAppear(index: 1)

                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                    .staggeredAppear(index: 2)
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
            .staggeredAppear(index: 3)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.ignoresSafeArea())
        // A milestone is a moment — mark its arrival.
        .onAppear { Haptics.success() }
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
            return "30 days in on \(proto.name). Share your progress."
        case .completed:
            return "\(proto.name) is complete. Drop the wrap-up into a story."
        }
    }
}
