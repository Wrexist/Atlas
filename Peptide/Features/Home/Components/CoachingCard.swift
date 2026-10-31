import SwiftUI

/// Bevel-style single-line coaching message under the hero metric
/// trio. Turns the trio's three numbers into a recommendation —
/// "Excellent recovery — push today", "Short sleep, cap intensity",
/// "Catch up on \(N) doses" — so the user gets an action, not just
/// a dashboard read.
struct CoachingCard: View {
    let message: CoachingMessageEngine.CoachingMessage
    /// The on-device model's rephrasing of `message.body`, when one landed.
    var rephrasedBody: String?
    /// Runs `message.action`; the card is only a button when it has one.
    var onAction: ((CoachingMessageEngine.CoachingMessage.Action) -> Void)?

    var body: some View {
        if let action = message.action, let onAction {
            Button {
                onAction(action)
            } label: {
                card(showsChevron: true)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityHint(hint(for: action))
        } else {
            card(showsChevron: false)
        }
    }

    private func hint(for action: CoachingMessageEngine.CoachingMessage.Action) -> Text {
        switch action {
        case .connectHealth: Text("Asks to connect Apple Health")
        case .scrollToHabits: Text("Scrolls to today's habits")
        case .scrollToDoses: Text("Scrolls to today's doses")
        }
    }

    private func card(showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(message.eyebrow)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(toneColor.opacity(0.85))

                Text(message.title)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let body = rephrasedBody ?? message.body {
                    Text(body)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .appAnimation(AppAnimation.fadeIn, value: body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(toneColor.opacity(0.25), lineWidth: 0.8)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        Image(systemName: message.icon)
            .font(AppFont.scaled(16, weight: .semibold))
            .foregroundStyle(toneColor)
            .frame(width: 38, height: 38)
            .background {
                Circle().fill(toneColor.opacity(0.18))
            }
    }

    private var toneColor: Color {
        switch message.tone {
        case .positive:   AppColor.success
        case .cautionary: AppColor.warning
        case .neutral:    AppColor.accentLight
        case .welcome:    AppColor.accentPrimary
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.md) {
            CoachingCard(message: .init(
                icon: "bolt.heart.fill",
                eyebrow: "COACHING",
                title: "Excellent recovery — 85%",
                body: "Recovery is up. Your BPC-157 dose is scheduled for 8:00 PM.",
                tone: .positive,
                kind: .strongRecovery
            ))
            CoachingCard(message: .init(
                icon: "moon.zzz.fill",
                eyebrow: "COACHING",
                title: "Lower recovery — 32%",
                body: "Consider an easier day. Hydrate and prioritize sleep.",
                tone: .cautionary,
                kind: .weakRecovery
            ))
            CoachingCard(message: .init(
                icon: "heart.text.square.fill",
                eyebrow: "GET STARTED",
                title: "Connect Apple Health",
                body: "Unlock Recovery and Sleep scores plus per-protocol HRV correlations.",
                tone: .neutral,
                kind: .connectHealth
            ), onAction: { _ in })
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
