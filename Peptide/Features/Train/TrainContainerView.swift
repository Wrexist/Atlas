import SwiftUI

/// Train-tab root. Hosts a segmented switcher between the three
/// surface modes — Overview (the muscle heatmap + recent workouts),
/// Exercises (the searchable library), and History (calendar + PRs).
/// The single `NavigationStack` lets every sub-screen push the same
/// destination types (`TrainNavigation`) without each tab re-creating
/// its own stack.
struct TrainContainerView: View {
    @State private var section: Section = .overview
    @State private var sessionService = WorkoutSessionService.shared
    @State private var showActiveWorkout = false

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
            .safeAreaInset(edge: .bottom) {
                if sessionService.activeSession != nil && !showActiveWorkout {
                    activeWorkoutBanner
                }
            }
        }
        .fullScreenCover(isPresented: $showActiveWorkout) {
            ActiveWorkoutView()
        }
        .onAppear {
            // If a workout was already in progress when this view
            // mounted (process re-launch, app re-entry), surface it
            // immediately so the user doesn't have to discover it
            // through the banner.
            if sessionService.activeSession != nil {
                showActiveWorkout = true
            }
        }
        .onChange(of: sessionService.activeSession?.id) { oldID, newID in
            // Auto-present when a new session begins; auto-dismiss
            // when one ends.
            if oldID == nil && newID != nil { showActiveWorkout = true }
        }
    }

    /// Sticky "Resume workout" pill shown when a session is in
    /// progress and the cover has been dismissed (the user backed
    /// out via Discard's "Keep going" cancel, etc.).
    private var activeWorkoutBanner: some View {
        Button {
            showActiveWorkout = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout in progress")
                        .font(AppFont.callout.weight(.semibold))
                    if let active = sessionService.activeSession {
                        Text("\(active.completedSetCount) sets logged")
                            .font(AppFont.caption)
                            .opacity(0.85)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(AppColor.background)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary)
            )
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xs)
        }
        .buttonStyle(.plain)
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
            TrainOverviewView()
        case .exercises:
            ExerciseLibraryView()
        case .history:
            placeholderHistory
        }
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
