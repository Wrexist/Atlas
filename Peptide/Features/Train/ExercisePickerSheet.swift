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
    /// Exercises the caller already holds (the workout's or the routine's),
    /// tagged in the list so the same lift isn't added twice by accident.
    var existingIDs: Set<String> = []
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var library = ExerciseLibrary.shared
    @State private var query: String = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: EquipmentKind?
    @State private var creatingCustomExercise: Bool = false
    @State private var picks = ExercisePickerSelection()
    @State private var isLoading = true
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
                ZStack {
                    if !picks.exercises.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            selectionTray
                            GlassButton(title: "Add (\(picks.exercises.count))", icon: "plus", isFullWidth: true) {
                                commit()
                            }
                            .disabled(picks.committed)
                            .accessibilityIdentifier("exercise-picker-add")
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .appAnimation(AppAnimation.springSnappy, value: picks.exercises.isEmpty)
            }
            .task {
                await loadLibrary()
            }
            .sheet(isPresented: $creatingCustomExercise) {
                CustomExerciseEditorSheet { custom in
                    SwiftDataRepository.shared.upsertCustomExercise(custom)
                    // Attach before committing so the workout resolves the
                    // new lift's id instead of showing "Unknown exercise".
                    library.reloadCustomExercises()
                    // Add the newly created exercise (after anything
                    // already picked) so the user goes straight back
                    // into their workout with the new lift added.
                    commit(adding: custom.asExercise())
                }
            }
        }
    }

    private var selectionTray: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Selected · In workout order").font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: Spacing.sm)
                Button("Clear") { picks.clear() }
                    .font(AppFont.callout).minimumHitArea()
                    .accessibilityLabel("Clear selected exercises")
            }
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    ForEach(picks.exercises) { exercise in
                        Button {
                            picks.remove(id: exercise.id)
                            Haptics.selection()
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Text(exercise.name).font(AppFont.callout)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                Image(systemName: "xmark.circle.fill").accessibilityHidden(true)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: Spacing.minimumHitTarget)
                            .frame(maxWidth: 240)
                            .background(AppColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: Spacing.chipCornerRadius))
                        }
                        .buttonStyle(ScalePressStyle())
                        .accessibilityLabel("Remove \(exercise.name) from selection")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .appAnimation(AppAnimation.springSnappy, value: picks.exercises.map(\.id))
            }.scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("exercise-picker-selection")
    }

    private func loadLibrary() async {
        isLoading = true
        await library.load()
        loadRecent()
        isLoading = false
    }

    private func clearFilters() {
        query = ""
        muscleFilter = nil
        equipmentFilter = nil
    }

    private var filterShelf: some View {
        VStack(spacing: 0) {
            MuscleGroupChipRow(selection: $muscleFilter)
            EquipmentChipRow(selection: $equipmentFilter)
            if !query.isEmpty || muscleFilter != nil || equipmentFilter != nil {
                Button("Clear search and filters", action: clearFilters)
                    .font(AppFont.caption2).minimumHitArea()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Spacing.screenPadding)
            }
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
        if !library.isLoaded && isLoading {
            ExerciseRowSkeletonList()
        } else if !library.isLoaded {
            EmptyStateView(icon: "exclamationmark.triangle", title: "Library unavailable",
                           message: "Couldn't load exercises. Your selections are still here.",
                           action: .init(title: "Retry", icon: "arrow.clockwise") {
                Task { await loadLibrary() }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Don't see your lift? Create a custom exercise.",
                action: .init(title: "Create custom exercise", icon: "plus") {
                    creatingCustomExercise = true
                },
                secondary: .init(title: "Clear search and filters", perform: clearFilters)
            )
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
            .scrollDismissesKeyboard(.interactively)
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
                    .padding(.leading, Spacing.screenPadding + ExerciseRow.tileSize + Spacing.md)
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        let isSelected = picks.exercises.contains { $0.id == exercise.id }
        let isExisting = existingIDs.contains(exercise.id)
        return Button {
            toggle(exercise)
        } label: {
            HStack(spacing: Spacing.sm) {
                ExerciseRow(exercise: exercise, showsChevron: false)
                if isExisting && !isSelected {
                    Text("Already added")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.screenPadding)
        // The glyph alone is 20pt; a wash across the row makes the
        // selection readable while scrolling past.
        .background(isSelected ? AppColor.accentPrimary.opacity(0.08) : Color.clear)
        .appAnimation(AppAnimation.quick, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isExisting ? "Already added" : "")
        .accessibilityHint(isSelected ? "Removes from selection" : "Adds to selection")
    }

    // MARK: - Selection

    private func toggle(_ exercise: Exercise) {
        Haptics.selection()
        picks.toggle(exercise)
    }

    private func commit(adding custom: Exercise? = nil) {
        let exercises = picks.takeForCommit(adding: custom)
        guard !exercises.isEmpty else { return }
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
