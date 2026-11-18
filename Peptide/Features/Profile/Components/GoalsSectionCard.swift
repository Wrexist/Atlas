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
    let onToggle: (String) -> Void

    struct GoalEntry: Identifiable, Hashable {
        let key: String
        let displayName: String
        var id: String { key }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Your goals", systemImage: "target")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                FlowLayout(spacing: Spacing.sm) {
                    ForEach(goalCatalog) { entry in
                        let isSelected = selectedKeys.contains(entry.key)

                        GlassChip(
                            LocalizedStringKey(entry.displayName),
                            icon: isSelected ? "checkmark" : nil,
                            isSelected: isSelected
                        ) {
                            onToggle(entry.key)
                        }
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
