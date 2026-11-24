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

    @State private var isEditing = false

    private var selectedEntries: [GoalEntry] {
        goalCatalog.filter { selectedKeys.contains($0.key) }
    }

    /// Only the chosen goals show on the card; the full set is one tap in,
    /// so the card reads as a statement rather than a form.
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Your goals", systemImage: "target")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    Spacer()

                    Button("Edit") { isEditing = true }
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                        .accessibilityLabel("Edit goals")
                        .minimumHitArea()
                }

                if selectedEntries.isEmpty {
                    Text("Pick what you're working toward.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    FlowLayout(spacing: Spacing.chipSpacing) {
                        ForEach(selectedEntries) { entry in
                            GlassChip(LocalizedStringKey(entry.displayName), isSelected: true) {
                                isEditing = true
                            }
                        }
                    }
                }
            }
            // FlowLayout reports the width its chips use, not the width
            // offered, so without this the card shrank and centred inside
            // the gutter the cards around it fill.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $isEditing) {
            GoalsEditorSheet(goalCatalog: goalCatalog, selectedKeys: selectedKeys, onToggle: onToggle)
                .liquidGlassPresentation(detents: [.medium, .large])
        }
    }
}

/// The full goal catalog, every chip toggleable. Selection reads from the
/// caller's live set so a toggle shows the moment it lands.
private struct GoalsEditorSheet: View {
    let goalCatalog: [GoalsSectionCard.GoalEntry]
    let selectedKeys: Set<String>
    let onToggle: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                FlowLayout(spacing: Spacing.chipSpacing) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.screenPadding)
            }
            .navigationTitle("Your goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
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
