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

    @Environment(\.dismiss) private var dismissEnv

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header
            actionStack
            dismissButton
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.top, Spacing.md)

            Text("Your cycle just finished")
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
            return "\(proto.name) reached the end of its \(proto.safeCycleLengthWeeks)-week cycle today. What's next?"
        }
        let dayWord = daysPastEnd == 1 ? "day" : "days"
        return "\(proto.name) ended \(daysPastEnd) \(dayWord) ago. Pick what's next so doses don't keep showing on your calendar."
    }

    private var actionStack: some View {
        VStack(spacing: Spacing.sm) {
            CompletionAction(
                title: "Mark complete",
                detail: "Stops doses for \(proto.name). History is kept.",
                icon: "checkmark.circle.fill",
                style: .primary,
                onTap: onMarkComplete
            )
            CompletionAction(
                title: "Extend by 2 weeks",
                detail: "Keep dosing on the same schedule. You'll see this prompt again when the extended cycle ends.",
                icon: "calendar.badge.plus",
                style: .secondary,
                onTap: onExtend
            )
            CompletionAction(
                title: "Start a new cycle",
                detail: "Resets the cycle to today. Same compounds, fresh week 1.",
                icon: "arrow.counterclockwise.circle",
                style: .secondary,
                onTap: onStartNewCycle
            )
        }
    }

    private var dismissButton: some View {
        Button("Decide later", action: onDismiss)
            .font(AppFont.footnote.weight(.semibold))
            .foregroundStyle(AppColor.textTertiary)
            .padding(.top, Spacing.xs)
            .accessibilityHint("Dismiss the prompt. After 3 dismissals or 7 days, the protocol auto-completes.")
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
                        .font(AppFont.caption)
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
        .buttonStyle(.plain)
    }
}
