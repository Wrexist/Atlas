import SwiftUI

struct GoalsSectionCard: View {
    let availableGoals: [String]
    let selectedGoals: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Your Goals", systemImage: "target")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                FlowLayout(spacing: Spacing.sm) {
                    ForEach(availableGoals, id: \.self) { goal in
                        let isSelected = selectedGoals.contains(goal)

                        Button { onToggle(goal) } label: {
                            HStack(spacing: Spacing.xs) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(goal)
                                    .font(AppFont.footnote)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background {
                                Capsule()
                                    .fill(isSelected ? AppColor.accentPrimary.opacity(0.2) : AppColor.surfaceElevated)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                                lineWidth: 0.5
                                            )
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        GoalsSectionCard(
            availableGoals: ["Muscle Recovery", "Better Sleep", "Cognitive Enhancement", "Anti-Aging", "Fat Loss"],
            selectedGoals: ["Muscle Recovery", "Better Sleep"]
        ) { _ in }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
