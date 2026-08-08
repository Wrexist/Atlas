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
    @Namespace private var sectionIndicator

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
            // Auto-present when a new session begins. We do not act
            // on the `newID == nil` (session ended) branch — the
            // ActiveWorkoutView dismisses itself via `dismiss()`
            // after transitioning through WorkoutFinishView, so the
            // cover lifecycle is owned downstream.
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
                    .font(AppFont.scaled(20, weight: .semibold))
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

#Preview {
    TrainContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
