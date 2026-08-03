import SwiftUI

struct CommunityStackCard: View {
    let stack: CommunityStack

    var body: some View {
        GlassCard(tinted: stack.featured) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(stack.name)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(AppFont.scaled(11))
                                .foregroundStyle(AppColor.textTertiary)
                            Text(stack.authorHandle ?? stack.authorName)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Spacing.sm)

                    if stack.featured {
                        Label("Featured", systemImage: "star.fill")
                            .labelStyle(.iconOnly)
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(AppColor.accentLight)
                    }
                }

                Text(stack.description)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Spacing.xs) {
                    statChip(icon: "flask.fill", value: "\(stack.peptideAbbreviations.count) peptides")
                    statChip(icon: "calendar", value: "\(stack.cycleLengthWeeks)w")
                    if !stack.goalTags.isEmpty {
                        statChip(icon: "target", value: stack.goalTags.first ?? "")
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(AppFont.scaled(11))
                        Text("\(stack.popularityScore)")
                            .font(AppFont.scaled(11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppColor.accentLight)
                }
            }
        }
    }

    private func statChip(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.scaled(11))
            Text(value)
                .font(AppFont.scaled(11, weight: .semibold))
        }
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(AppColor.cardOverlay)
        )
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        CommunityStackCard(stack: CommunityStack(
            id: UUID(),
            name: "Wolverine Stack",
            authorName: "Dr. M. Reyes",
            authorHandle: "@reyes.recovery",
            authorTitle: "MD",
            description: "Tissue repair and recovery with two complementary mechanisms.",
            goalTags: ["Recovery"],
            peptideAbbreviations: ["BPC-157", "TB-500"],
            cycleLengthWeeks: 8,
            scheduleDaysOfWeek: [1, 2, 3, 4, 5],
            scheduleTimesPerDay: 1,
            popularityScore: 96,
            featured: true
        ))
        .padding()
    }
    .preferredColorScheme(.dark)
}
