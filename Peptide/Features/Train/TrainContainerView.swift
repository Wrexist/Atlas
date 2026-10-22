import SwiftUI

/// Train-tab root. Hosts a segmented switcher between the four
/// surface modes — Overview (the muscle heatmap + recent workouts),
/// Routines (saved templates, one tap to start), Exercises (the
/// searchable library), and History (finished workouts by month).
/// The single `path` lets every sub-screen push the same destination
/// types (`TrainNavigation`) without each tab re-creating its own stack.
struct TrainContainerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var exerciseBrowsing = ExerciseBrowsingState()
    @State private var overviewScroll = ScrollPosition(edge: .top)
    @Namespace private var exerciseTransition
    @State private var section: Section = .overview
    /// Owned here rather than per-section so a screen can push
    /// programmatically — creating a routine goes straight into its
    /// builder instead of leaving the user to find the new empty row.
    @State private var path: [TrainNavigation] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sessionService = WorkoutSessionService.shared
    @State private var showActiveWorkout = false
    /// The relaunch auto-present below happens once. `onAppear` fires on
    /// every return to this tab, and re-opening a workout the user just
    /// minimized would make minimizing pointless.
    @State private var restoredActiveWorkout = false
    @State private var isVisible = false
    @State private var showStaleNotice = false
    @State private var staleNoticeMessage: LocalizedStringKey = ""

    enum Section: String, CaseIterable, Identifiable {
        case overview, routines, exercises, history
        var id: String { rawValue }

        var displayName: LocalizedStringKey {
            switch self {
            case .overview:  "Overview"
            case .routines:  "Routines"
            case .exercises: "Exercises"
            case .history:   "History"
            }
        }
    }

    var body: some View {
        // Same split as the Library: iPad regular gets the sections in a
        // sidebar column with pushes landing in the detail column, while
        // compact keeps the single stack (a collapsed split view swallows
        // value pushes from the sidebar).
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .environment(\.resumeActiveWorkout, { showActiveWorkout = true })
        .fullScreenCover(isPresented: $showActiveWorkout) {
            ActiveWorkoutView()
        }
        .onAppear {
            isVisible = true
            // Before the restore below: a workout forgotten overnight is
            // closed, not re-opened.
            sessionService.closeIfStale()
            surfaceStaleClosure()
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
        .onDisappear { isVisible = false }
        .onChange(of: sessionService.staleClosure) { _, closure in
            guard closure != nil else { return }
            // Left open overnight, the workout screen would come back
            // to an empty "no workout" state.
            showActiveWorkout = false
            // Off-screen, the notice waits for the next `onAppear`.
            if isVisible { surfaceStaleClosure() }
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

    private var stackLayout: some View {
        NavigationStack(path: $path) {
            trainRoot
                .navigationDestination(for: TrainNavigation.self) { trainDestination(for: $0) }
                .safeAreaInset(edge: .bottom) { workoutBannerSlot }
        }
    }

    /// A sidebar link replaces the detail stack's root and a link inside
    /// the detail pushes onto it, so `path` drives the right column the
    /// same way it drives the phone stack.
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            trainRoot
                .safeAreaInset(edge: .bottom) { workoutBannerSlot }
        } detail: {
            NavigationStack(path: $path) {
                EmptyStateView(
                    icon: "dumbbell",
                    title: "Pick a workout",
                    message: "Select a routine, exercise, or past session to see it here."
                )
                .padding(Spacing.screenPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.background)
                .navigationDestination(for: TrainNavigation.self) { trainDestination(for: $0) }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var trainRoot: some View {
        VStack(spacing: 0) {
            sectionPicker
            // Keyed on the section so the body moves with the pill
            // instead of swapping under it.
            content
                .id(section)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .background(AppColor.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            SyncToast(
                isShowing: $showStaleNotice,
                message: staleNoticeMessage,
                autoDismissAfter: .seconds(4)
            )
            .padding(.top, Spacing.sm)
        }
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
        }
    }

    @ViewBuilder
    private func trainDestination(for destination: TrainNavigation) -> some View {
        switch destination {
        case .exerciseDetail(let id):
            if zoomsIntoExercises {
                ExerciseDetailView(exerciseID: id)
                    .navigationTransition(.zoom(sourceID: id, in: exerciseTransition))
            } else {
                ExerciseDetailView(exerciseID: id)
            }
        case .workoutDetail(let id):
            // Resolve the session lazily so the destination
            // works for deep-links from outside the History
            // list (Spotlight, Live Activity, weekly recap)
            // without forcing the caller to hold the value.
            workoutDetailDestination(for: id)
        case .workoutHistory:
            // Pushed from "View all"; as a section it sits under "Train".
            WorkoutHistoryView()
                .navigationTitle("History")
        case .routineBuilder(let id):
            RoutineBuilderView(routineID: id)
        }
    }

    /// The zoom grows the detail out of the tapped row, which only reads
    /// as a push within one column. In the split view the row stays put
    /// in the sidebar while the detail swaps in beside it.
    private var zoomsIntoExercises: Bool {
        !reduceMotion && sizeClass != .regular
    }

    private var workoutBannerSlot: some View {
        ZStack {
            if showsWorkoutBanner {
                activeWorkoutBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: showsWorkoutBanner)
    }

    private func surfaceStaleClosure() {
        guard let closure = sessionService.staleClosure else { return }
        sessionService.acknowledgeStaleClosure()
        staleNoticeMessage = closure == .finished
            ? "Saved your unfinished workout to History"
            : "Cleared an empty workout left open"
        showStaleNotice = true
    }

    private var showsWorkoutBanner: Bool {
        sessionService.activeSession != nil && !showActiveWorkout
    }

    /// Sticky "Resume workout" pill shown when a session is in
    /// progress and the cover has been dismissed (the user minimized
    /// the workout from its toolbar).
    private var activeWorkoutBanner: some View {
        Button {
            showActiveWorkout = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "dumbbell.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Workout in progress")
                        .font(AppFont.callout.weight(.semibold))
                    if let active = sessionService.activeSession {
                        HStack(spacing: Spacing.xs) {
                            // Active time, not wall clock: frozen while
                            // paused, and pauses don't count.
                            TimelineView(.animation(minimumInterval: 1, paused: active.isPaused)) { context in
                                Text(WorkoutClock.label(active.elapsedSeconds(now: context.date)))
                                    .accessibilityLabel(WorkoutClock.spoken(active.elapsedSeconds(now: context.date)))
                            }
                            Text("·")
                                .accessibilityHidden(true)
                            Text("^[\(active.completedSetCount) set](inflect: true) logged")
                                .contentTransition(.numericText())
                        }
                        .font(AppFont.caption)
                        .monospacedDigit()
                    }
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AppColor.onAccent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.accentFill)
            )
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xs)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityHint("Opens your workout")
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
            GlassSegmentedControl(
                options: Section.allCases,
                selected: $section,
                style: .prominent,
                label: { $0.displayName }
            )
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
            TrainOverviewView(scrollPosition: $overviewScroll)
        case .routines:
            RoutinesView(path: $path)
        case .exercises:
            ExerciseLibraryView(browsing: exerciseBrowsing, transitionNamespace: zoomsIntoExercises ? exerciseTransition : nil)
        case .history:
            WorkoutHistoryView()
        }
    }

    @ViewBuilder
    private func workoutDetailDestination(for id: UUID) -> some View {
        if let session = SwiftDataRepository.shared.loadWorkoutSession(id: id) {
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
