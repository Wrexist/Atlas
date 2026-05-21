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
    @State private var library = ExerciseLibrary.shared
    @State private var query: String = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: EquipmentKind?
    @FocusState private var searchFocused: Bool

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
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Search exercises, muscles, equipment")
        )
        .task {
            await library.load()
        }
    }

    // MARK: - Filter shelf

    private var filterShelf: some View {
        VStack(spacing: Spacing.xxs) {
            MuscleGroupChipRow(selection: $muscleFilter)
            EquipmentChipRow(selection: $equipmentFilter)
        }
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let results = library.filter(
            query: query.isEmpty ? nil : query,
            muscleGroup: muscleFilter,
            equipment: equipmentFilter
        )

        if library.bundled.isEmpty {
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
                    NavigationLink(value: TrainNavigation.exerciseDetail(exercise.id)) {
                        ExerciseRow(exercise: exercise)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.screenPadding)

                    if exercise.id != results.last?.id {
                        Divider()
                            .background(AppColor.glassBorder)
                            .padding(.leading, Spacing.screenPadding + 56 + Spacing.md)
                    }
                }
            }
            .padding(.bottom, Spacing.xxxl)
        }
    }

    private func resultsCount(_ count: Int) -> some View {
        HStack {
            Text("\(count) \(count == 1 ? "exercise" : "exercises")")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            if muscleFilter != nil || equipmentFilter != nil || !query.isEmpty {
                Button("Clear filters") {
                    muscleFilter = nil
                    equipmentFilter = nil
                    query = ""
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
            message: "Try a different muscle group or clear the filters to widen your search."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibraryState: some View {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Library unavailable",
            message: "We couldn't load the exercise database. Pull down to refresh, or tap retry below.",
            action: .init(title: "Retry", icon: "arrow.clockwise") {
                library.reset()
                Task { await library.load() }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
            .navigationDestination(for: TrainNavigation.self) { dest in
                switch dest {
                case .exerciseDetail(let id): ExerciseDetailView(exerciseID: id)
                case .workoutDetail, .workoutHistory: WorkoutHistoryView()
                }
            }
    }
    .preferredColorScheme(.dark)
}
