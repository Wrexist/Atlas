import SwiftUI

/// Profile-tab goal picker. Each entry is a (storage-key, display-name)
/// pair so the underlying profile.goals array stores stable rawValues
/// (camelCase, matching OnboardingView.PrimaryGoal) while the chips
/// render the human-readable display names. Without this split, the
/// Profile picker stored Title Case strings that never intersected
/// with the camelCase rawValues onboarding wrote — picking a goal in
/// onboarding then opening Profile left every chip unselected.
struct GoalsSectionCard: View {
    /// (storage key, display label) pairs. Toggle is keyed on the
    /// storage key; the display label is rendered on the chip.
    let goalCatalog: [GoalEntry]
    let selectedKeys: Set<String>
    var hapticEnabled: Bool = true
    let onToggle: (String) -> Void

    struct GoalEntry: Identifiable, Hashable {
        let key: String
        let displayName: String
        var id: String { key }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Your Goals", systemImage: "target")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                FlowLayout(spacing: Spacing.sm) {
                    ForEach(goalCatalog) { entry in
                        let isSelected = selectedKeys.contains(entry.key)

                        Button {
                            if hapticEnabled {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            }
                            withAnimation(AppAnimation.springSnappy) {
                                onToggle(entry.key)
                            }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .transition(.scale.combined(with: .opacity))
                                }
                                Text(entry.displayName)
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
                        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
                        .accessibilityLabel(entry.displayName)
                        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
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
            goalCatalog: [
                .init(key: "buildMuscle",    displayName: "Build muscle"),
                .init(key: "betterSleep",    displayName: "Better sleep"),
                .init(key: "loseFat",        displayName: "Lose fat"),
                .init(key: "antiAging",      displayName: "Anti-aging"),
            ],
            selectedKeys: ["buildMuscle", "betterSleep"]
        ) { _ in }
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
