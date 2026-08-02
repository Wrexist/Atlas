import SwiftUI

/// Bevel-style single-line coaching message under the hero metric
/// trio. Turns the trio's three numbers into a recommendation —
/// "Excellent recovery — push today", "Short sleep, cap intensity",
/// "Catch up on \(N) doses" — so the user gets an action, not just
/// a dashboard read.
struct CoachingCard: View {
    let message: CoachingMessageEngine.CoachingMessage

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(message.eyebrow)
                    .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(toneColor.opacity(0.85))

                Text(message.title)
                    .font(AppFont.scaled(17, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let body = message.body {
                    Text(body)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .combine)
    }

    private var iconBadge: some View {
        Image(systemName: message.icon)
            .font(AppFont.scaled(18, weight: .semibold))
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
                body: "Recovery is up — good day to nail your BPC-157 dose at 8:00 PM.",
                tone: .positive
            ))
            CoachingCard(message: .init(
                icon: "moon.zzz.fill",
                eyebrow: "COACHING",
                title: "Lower recovery — 32%",
                body: "Consider an easier day. Hydrate, prioritize sleep, and don't skip rest doses.",
                tone: .cautionary
            ))
            CoachingCard(message: .init(
                icon: "sparkles",
                eyebrow: "WELCOME",
                title: "Set up your first protocol",
                body: "Atlas builds your schedule, tracks every dose, and learns your patterns.",
                tone: .welcome
            ))
        }
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
