import SwiftUI

/// Modal exercise picker reused everywhere we need to add an
/// exercise — active workout, routine editor, program inspector.
/// Same search + filter affordances as `ExerciseLibraryView` but the
/// tap action becomes a callback so the caller can do whatever it
/// needs (append to session, append to routine slot, etc.).
///
/// Taps build a selection; "Add (n)" hands each pick to `onSelect` in
/// the order it was tapped, so callers that append one exercise per call
/// get a multi-add for free.
struct ExercisePickerSheet: View {
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var library = ExerciseLibrary.shared
    @State private var query: String = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: EquipmentKind?
    @State private var creatingCustomExercise: Bool = false
    @State private var selection: [Exercise] = []
    @State private var recentExercises: [Exercise] = []

    /// How many finished sessions feed the Recent section, and how many
    /// exercises it shows.
    static let recentSessionLimit = 10
    static let recentExerciseLimit = 8

    private var showsRecent: Bool {
        !recentExercises.isEmpty && query.isEmpty && muscleFilter == nil && equipmentFilter == nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterShelf
                list
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creatingCustomExercise = true
                    } label: {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(16, weight: .semibold))
                    }
                    .accessibilityLabel("Create custom exercise")
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search exercises")
            )
            .pinnedFooter {
                if !selection.isEmpty {
                    GlassButton(title: "Add (\(selection.count))", icon: "plus", isFullWidth: true) {
                        commit(selection)
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)
                }
            }
            .task {
                await library.load()
                loadRecent()
            }
            .sheet(isPresented: $creatingCustomExercise) {
                CustomExerciseEditorSheet { custom in
                    SwiftDataRepository.shared.upsertCustomExercise(custom)
                    // Reload picks up the new custom lift; await so
                    // the auto-select below sees the freshly-loaded
                    // library rather than racing the load.
                    Task { await library.load() }
                    // Add the newly created exercise (after anything
                    // already picked) so the user goes straight back
                    // into their workout with the new lift added.
                    commit(selection + [custom.asExercise()])
                }
            }
        }
    }

    private var filterShelf: some View {
        VStack(spacing: 0) {
            MuscleGroupChipRow(selection: $muscleFilter)
            EquipmentChipRow(selection: $equipmentFilter)
        }
        .padding(.bottom, Spacing.xs)
    }

    @ViewBuilder
    private var list: some View {
        let results = library.filter(
            query: query.isEmpty ? nil : query,
            muscleGroup: muscleFilter,
            equipment: equipmentFilter
        )
        if results.isEmpty {
            VStack(spacing: Spacing.md) {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "Don't see your lift? Create a custom exercise to add it to your routine."
                )
                Button {
                    creatingCustomExercise = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityHidden(true)
                        Text("Create custom exercise")
                    }
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(
                        Capsule().fill(AppColor.accentPrimary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if showsRecent {
                        sectionHeader("Recent")
                        rows(recentExercises, idPrefix: "recent")
                        sectionHeader("All exercises")
                    }
                    rows(results, idPrefix: "all")
                }
                .padding(.bottom, Spacing.xxxl)
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.eyebrow)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    /// `idPrefix` keeps a recent exercise's row distinct from its row in
    /// the full list — both can be on screen in the same lazy stack.
    private func rows(_ exercises: [Exercise], idPrefix: String) -> some View {
        ForEach(exercises, id: \.id) { exercise in
            row(exercise)
                .id("\(idPrefix)-\(exercise.id)")
            if exercise.id != exercises.last?.id {
                Divider()
                    .background(AppColor.glassBorder)
                    .padding(.leading, Spacing.screenPadding + 56 + Spacing.md)
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        let isSelected = selection.contains { $0.id == exercise.id }
        return Button {
            toggle(exercise)
        } label: {
            ExerciseRow(exercise: exercise, showsChevron: false)
                .overlay(alignment: .trailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(AppFont.scaled(20, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.screenPadding)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Selection

    private func toggle(_ exercise: Exercise) {
        Haptics.selection()
        if let index = selection.firstIndex(where: { $0.id == exercise.id }) {
            selection.remove(at: index)
        } else {
            selection.append(exercise)
        }
    }

    private func commit(_ exercises: [Exercise]) {
        for exercise in exercises {
            onSelect(exercise)
        }
        dismiss()
    }

    // MARK: - Recent

    /// Runs once per presentation, after the library is loaded, so the
    /// lookups resolve and the fetch stays out of `body`.
    private func loadRecent() {
        let sessions = SwiftDataRepository.shared.loadWorkoutSessions(limit: Self.recentSessionLimit + 1)
        recentExercises = Self.recentExerciseIDs(from: sessions).compactMap { library.lookup(id: $0) }
    }

    /// Exercise ids from the most recent finished sessions, newest session
    /// first and in logged order within it, each id once.
    static func recentExerciseIDs(
        from sessions: [WorkoutSession],
        sessionLimit: Int = ExercisePickerSheet.recentSessionLimit,
        limit: Int = ExercisePickerSheet.recentExerciseLimit
    ) -> [String] {
        let finished = sessions
            .compactMap { session in session.finishedAt.map { (session, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(sessionLimit)
            .map { $0.0 }
        var seen = Set<String>()
        var ids: [String] = []
        for session in finished {
            for entry in session.exercises.sorted(by: { $0.index < $1.index })
            where seen.insert(entry.exerciseID).inserted {
                ids.append(entry.exerciseID)
                if ids.count == limit { return ids }
            }
        }
        return ids
    }
}
