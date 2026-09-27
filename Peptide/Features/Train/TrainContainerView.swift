import SwiftUI

/// Train-tab root. Hosts a segmented switcher between the four
/// surface modes — Overview (the muscle heatmap + recent workouts),
/// Routines (saved templates, one tap to start), Exercises (the
/// searchable library), and History (calendar + PRs).
/// The single `NavigationStack` lets every sub-screen push the same
/// destination types (`TrainNavigation`) without each tab re-creating
/// its own stack.
struct TrainContainerView: View {
    @State private var section: Section = .overview
    /// Owned here rather than per-section so a screen can push
    /// programmatically — creating a routine goes straight into its
    /// builder instead of leaving the user to find the new empty row.
    @State private var path: [TrainNavigation] = []
    @State private var sessionService = WorkoutSessionService.shared
    @State private var showActiveWorkout = false
    /// The relaunch auto-present below happens once. `onAppear` fires on
    /// every return to this tab, and re-opening a workout the user just
    /// minimized would make minimizing pointless.
    @State private var restoredActiveWorkout = false
    @Namespace private var sectionIndicator

    enum Section: String, CaseIterable, Identifiable {
        case overview, routines, exercises, history
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .overview:  return "Overview"
            case .routines:  return "Routines"
            case .exercises: return "Exercises"
            case .history:   return "History"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                sectionPicker
                content
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .navigationDestination(for: TrainNavigation.self) { destination in
                switch destination {
                case .exerciseDetail(let id):
                    ExerciseDetailView(exerciseID: id)
                case .workoutDetail(let id):
                    // Resolve the session lazily so the destination
                    // works for deep-links from outside the History
                    // list (Spotlight, Live Activity, weekly recap)
                    // without forcing the caller to hold the value.
                    workoutDetailDestination(for: id)
                case .workoutHistory:
                    WorkoutHistoryView()
                case .routineBuilder(let id):
                    RoutineBuilderView(routineID: id)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if sessionService.activeSession != nil && !showActiveWorkout {
                    activeWorkoutBanner
                }
            }
        }
        .environment(\.resumeActiveWorkout, { showActiveWorkout = true })
        .fullScreenCover(isPresented: $showActiveWorkout) {
            ActiveWorkoutView()
        }
        .onAppear {
            // If a workout was already in progress when this view
            // mounted (process re-launch, app re-entry), surface it
            // immediately so the user doesn't have to discover it
            // through the banner.
            guard !restoredActiveWorkout else { return }
            restoredActiveWorkout = true
            if sessionService.activeSession != nil {
                showActiveWorkout = true
            }
        }
        .onChange(of: sessionService.activeSession?.id) { oldID, newID in
            // Auto-present whenever a different session begins —
            // including one that replaced a minimized workout, where
            // the id goes straight from the old session to the new one.
            // We do not act on the `newID == nil` (session ended)
            // branch — the ActiveWorkoutView dismisses itself via
            // `dismiss()` after transitioning through WorkoutFinishView,
            // so the cover lifecycle is owned downstream.
            if let newID, newID != oldID { showActiveWorkout = true }
        }
    }

    /// Sticky "Resume workout" pill shown when a session is in
    /// progress and the cover has been dismissed (the user minimized
    /// the workout from its toolbar).
    private var activeWorkoutBanner: some View {
        Button {
            showActiveWorkout = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "figure.run.circle.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
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
                    .font(AppFont.scaled(13, weight: .semibold))
                    .accessibilityHidden(true)
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
        // A filled capsule under the selected section rather than an
        // underline: Train's sections are peers you switch between, and a
        // filled pill says "you are here" at a glance where a 3pt rule
        // under one word does not. `.segmented` Picker still reads too
        // "system settings" for this surface.
        //
        // Horizontally scrollable because four pills at the largest
        // Dynamic Type sizes are wider than an iPhone — a fixed HStack
        // would clip the last section rather than let the user reach it.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Section.allCases) { item in
                    SectionTab(
                        title: item.displayName,
                        isSelected: section == item,
                        namespace: sectionIndicator
                    ) {
                        withAnimation(AppAnimation.springSnappy) {
                            section = item
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .scrollClipDisabled()
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            TrainOverviewView()
        case .routines:
            RoutinesView(path: $path)
        case .exercises:
            ExerciseLibraryView()
        case .history:
            WorkoutHistoryView()
        }
    }

    @ViewBuilder
    private func workoutDetailDestination(for id: UUID) -> some View {
        if let session = SwiftDataRepository.shared
            .loadWorkoutSessions()
            .first(where: { $0.id == id }) {
            WorkoutSessionDetailView(session: session)
        } else {
            // Session was deleted between deep-link generation and
            // open — fall through to an empty state rather than
            // crashing on a stale UUID.
            EmptyStateView(
                icon: "questionmark.circle",
                title: "Workout not found",
                message: "This session may have been deleted."
            )
            .navigationTitle("Workout")
        }
    }

    // MARK: - SectionTab

    private struct SectionTab: View {
        let title: String
        let isSelected: Bool
        let namespace: Namespace.ID
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textSecondary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        // Only the selected pill draws a surface, and it
                        // travels between sections rather than cross-fading
                        // — the movement is what tells the user the two are
                        // the same control.
                        if isSelected {
                            Capsule()
                                .fill(AppColor.accentFill)
                                .matchedGeometryEffect(id: "section", in: namespace)
                        }
                    }
                    .frame(minHeight: Spacing.minimumHitTarget)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

extension EnvironmentValues {
    /// Re-presents the in-progress workout's full-screen cover. Set by
    /// `TrainContainerView`, which owns that cover, so a screen deeper in
    /// the Train stack can offer "Resume" without holding the flag.
    @Entry var resumeActiveWorkout: () -> Void = {}
}

#Preview {
    TrainContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
