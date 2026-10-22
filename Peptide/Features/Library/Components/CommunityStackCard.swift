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
                                .font(AppFont.caption2)
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
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Spacing.xs) {
                    statChip(icon: "flask.fill", value: Text("^[\(stack.peptideAbbreviations.count) peptide](inflect: true)"))
                    statChip(icon: "calendar", value: Text("^[\(stack.cycleLengthWeeks) week](inflect: true)"))
                    if let goal = stack.goalTags.first {
                        statChip(icon: "target", value: Text(LocalizedStringKey(goal)))
                    }
                    Spacer()
                }
            }
        }
        // One VoiceOver stop with a spoken summary instead of five fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let peptides = stack.peptideAbbreviations.count
        var parts = [
            stack.name,
            "by \(stack.authorName)",
            peptides == 1 ? "1 peptide" : "\(peptides) peptides",
            stack.cycleLengthWeeks == 1 ? "1 week" : "\(stack.cycleLengthWeeks) weeks"
        ]
        if let goal = stack.goalTags.first { parts.append(goal) }
        if stack.featured { parts.append("featured") }
        return parts.joined(separator: ", ")
    }

    private func statChip(icon: String, value: Text) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(11))
            value
                .font(AppFont.scaled(11, weight: .semibold))
        }
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
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
