import SwiftUI

/// Browse-and-filter view over the bundled exercise dataset. The
/// search bar matches against name, primary/secondary muscles, and
/// raw equipment string; the chip rows above the list filter by
/// collapsed muscle group and equipment kind. Single-select to keep
/// the UX legible — multi-select can come back when the dataset
/// surfaces enough categorical signal (e.g. tagged movement
/// patterns) to justify it.
///
/// The library service load is idempotent and runs in `.task` so the
/// initial render shows the SwiftUI search-bar skeleton immediately
/// instead of blocking on the JSON parse.
struct ExerciseLibraryView: View {
    @Bindable var browsing: ExerciseBrowsingState
    var transitionNamespace: Namespace.ID?
    @State private var library = ExerciseLibrary.shared
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            filterShelf
                .background(AppColor.background)

            content
        }
        .background(AppColor.background)
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $browsing.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search exercises, muscles, equipment")
        )
        .task { await loadLibrary() }
    }

    private func loadLibrary() async {
        isLoading = true
        await library.load()
        isLoading = false
    }

    // MARK: - Filter shelf

    private var filterShelf: some View {
        VStack(spacing: Spacing.xxs) {
            MuscleGroupChipRow(selection: $browsing.muscleFilter)
            EquipmentChipRow(selection: $browsing.equipmentFilter)
        }
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let results = library.filter(
            query: browsing.query.isEmpty ? nil : browsing.query,
            muscleGroup: browsing.muscleFilter,
            equipment: browsing.equipmentFilter
        )

        if !library.isLoaded && isLoading {
            ProgressView("Loading exercises…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.bundled.isEmpty {
            emptyLibraryState
        } else if results.isEmpty {
            noResultsState
        } else {
            list(for: results)
        }
    }

    private func list(for results: [Exercise]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                resultsCount(results.count)

                ForEach(results) { exercise in
                    VStack(spacing: 0) {
                        NavigationLink(value: TrainNavigation.exerciseDetail(exercise.id)) {
                            ExerciseRow(exercise: exercise)
                                .exerciseTransitionSource(id: exercise.id, namespace: transitionNamespace)
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.99))
                        .padding(.horizontal, Spacing.screenPadding)

                        if exercise.id != results.last?.id {
                            Divider()
                                .background(AppColor.glassBorder)
                                .padding(.leading, Spacing.screenPadding + 56 + Spacing.md)
                        }
                    }
                    .id(exercise.id)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollPosition(id: $browsing.visibleExerciseID, anchor: .top)
        .scrollDismissesKeyboard(.interactively)
    }

    private func resultsCount(_ count: Int) -> some View {
        HStack {
            Text("\(count) \(count == 1 ? "exercise" : "exercises")")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            if browsing.muscleFilter != nil || browsing.equipmentFilter != nil || !browsing.query.isEmpty {
                Button("Clear filters") {
                    browsing.clear()
                }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.accentPrimary)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No matches",
            message: "Try a different muscle group or clear the filters to widen your search.",
            // "Clear the filters" also lives in the filter shelf, which by
            // this point has usually scrolled out of reach.
            action: .init(title: "Clear filters", icon: "xmark.circle.fill") {
                browsing.clear()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibraryState: some View {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Library unavailable",
            message: "We couldn't load the exercise database. Tap Retry to try again.",
            action: .init(title: "Retry", icon: "arrow.clockwise") {
                library.reset()
                Task { await loadLibrary() }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView(browsing: ExerciseBrowsingState())
            .navigationDestination(for: TrainNavigation.self) { dest in
                switch dest {
                case .exerciseDetail(let id): ExerciseDetailView(exerciseID: id)
                case .routineBuilder(let id): RoutineBuilderView(routineID: id)
                case .workoutDetail, .workoutHistory: WorkoutHistoryView()
                }
            }
    }
    .preferredColorScheme(.dark)
}
