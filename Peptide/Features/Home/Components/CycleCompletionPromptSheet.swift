import SwiftUI

/// Prompt surfaced when a user's active protocol has crossed its
/// cycle end date. Three explicit choices + a dismiss; the parent
/// (HomeView) wires each callback to the appropriate DataStore
/// mutation.
///
/// Modeled after `CycleMilestonePromptSheet` so the visual language
/// reads as part of the same family — same hero card, same button
/// stack — but the copy is action-oriented rather than celebratory.
struct CycleCompletionPromptSheet: View {
    let proto: PeptideProtocol
    let daysPastEnd: Int
    let onMarkComplete: () -> Void
    let onExtend: () -> Void
    let onStartNewCycle: () -> Void
    let onDismiss: () -> Void

    /// Scrolls so every choice is reachable at the medium detent and at
    /// large text sizes; "Decide later" and the auto-complete rule stay
    /// pinned below it.
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header
                actionStack
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            dismissButton
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.md)
                .frame(maxWidth: .infinity)
                .background(AppColor.background)
        }
        .background(AppColor.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(AppFont.scaled(44, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.top, Spacing.md)

            Text(daysPastEnd > 0 ? "Your cycle has ended" : "Your cycle just finished")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

            Text(headerSubtitle)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
    }

    private var headerSubtitle: String {
        if daysPastEnd <= 0 {
            return String(localized: "\(proto.name) reached the end of its \(proto.safeCycleLengthWeeks)-week cycle today. What's next?")
        }
        return String(localized: "\(proto.name) ended \(daysPastEnd) days ago. Pick what's next so doses don't keep showing on your calendar.")
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.sm) {
            CompletionAction(
                title: "Mark complete",
                detail: String(localized: "Stops doses for \(proto.name). History is kept."),
                icon: "checkmark.circle.fill",
                style: .primary,
                onTap: onMarkComplete
            )
            CompletionAction(
                title: "Extend by 2 weeks",
                detail: String(localized: "Keep dosing on the same schedule. You'll see this prompt again when the extended cycle ends."),
                icon: "calendar.badge.plus",
                style: .secondary,
                onTap: onExtend
            )
            CompletionAction(
                title: "Start a new cycle",
                detail: String(localized: "Resets the cycle to today. Same compounds, fresh week 1."),
                icon: "arrow.counterclockwise.circle",
                style: .secondary,
                onTap: onStartNewCycle
            )
        }
    }

    private var dismissButton: some View {
        VStack(spacing: Spacing.xxs) {
            Button("Decide later", action: onDismiss)
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .buttonStyle(ScalePressStyle())
                .minimumHitArea()
                .accessibilityHint("Dismisses the prompt")
            // Shown, not just spoken — sighted users need the rule too.
            Text("After 3 dismissals or 7 days, the protocol completes automatically.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.xs)
    }
}

private struct CompletionAction: View {
    enum Style { case primary, secondary }
    let title: LocalizedStringKey
    let detail: String
    let icon: String
    let style: Style
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(style == .primary ? AppColor.accentPrimary : AppColor.accentLight)
                    .frame(width: 32, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(detail)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(style == .primary
                          ? AppColor.accentPrimary.opacity(0.15)
                          : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(style == .primary
                                          ? AppColor.accentPrimary.opacity(0.4)
                                          : AppColor.glassBorder,
                                          lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }
}
