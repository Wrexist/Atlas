import SwiftUI

/// Train-tab root. Hosts a segmented switcher between the three
/// surface modes — Overview (the muscle heatmap + recent workouts),
/// Exercises (the searchable library), and History (calendar + PRs).
/// The single `NavigationStack` lets every sub-screen push the same
/// destination types (`TrainNavigation`) without each tab re-creating
/// its own stack.
struct TrainContainerView: View {
    @State private var section: Section = .overview

    enum Section: String, CaseIterable, Identifiable {
        case overview, exercises, history
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .overview:  return "Overview"
            case .exercises: return "Exercises"
            case .history:   return "History"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker
                content
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: TrainNavigation.self) { destination in
                switch destination {
                case .exerciseDetail(let id):
                    ExerciseDetailView(exerciseID: id)
                }
            }
        }
    }

    private var sectionPicker: some View {
        // Using a raw HStack of buttons — `.segmented` Picker reads
        // visually too "system settings" and the Train tab wants a
        // softer chrome. Underline indicator matches the Lyfta
        // reference shots and reads cleanly on the dark background.
        HStack(spacing: Spacing.lg) {
            ForEach(Section.allCases) { item in
                SectionTab(
                    title: item.displayName,
                    isSelected: section == item
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        section = item
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            // Placeholder — the full overview surface (weekly muscle
            // heatmap, recent workouts, monthly calendar) lands in
            // the next commit. Keeping a friendly empty-state here
            // so the picker is wired end-to-end before the data
            // services exist.
            placeholderOverview
        case .exercises:
            ExerciseLibraryView()
        case .history:
            placeholderHistory
        }
    }

    private var placeholderOverview: some View {
        EmptyStateView(
            icon: "figure.strengthtraining.traditional",
            title: "Overview is coming",
            message: "Your weekly muscle heatmap and trained calendar will live here. Browse the Exercises tab to start."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderHistory: some View {
        EmptyStateView(
            icon: "calendar",
            title: "No workouts logged yet",
            message: "Once you finish your first session, it'll show up here with PRs and a monthly heat-calendar."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - SectionTab

    private struct SectionTab: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(
                            isSelected ? AppColor.textPrimary : AppColor.textSecondary
                        )
                    Capsule()
                        .fill(isSelected ? AppColor.accentPrimary : Color.clear)
                        .frame(height: 3)
                        .frame(width: 32)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

#Preview {
    TrainContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
