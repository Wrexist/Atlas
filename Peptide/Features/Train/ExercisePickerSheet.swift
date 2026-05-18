import SwiftUI

/// Modal exercise picker reused everywhere we need to add an
/// exercise — active workout, routine editor, program inspector.
/// Same search + filter affordances as `ExerciseLibraryView` but the
/// tap action becomes a callback so the caller can do whatever it
/// needs (append to session, append to routine slot, etc.).
struct ExercisePickerSheet: View {
    let onSelect: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var library = ExerciseLibrary.shared
    @State private var query: String = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: EquipmentKind?
    @State private var creatingCustomExercise: Bool = false

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
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Create custom exercise")
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search exercises")
            )
            .task { await library.load() }
            .sheet(isPresented: $creatingCustomExercise) {
                CustomExerciseEditorSheet { custom in
                    SwiftDataRepository.shared.upsertCustomExercise(custom)
                    // Reload picks up the new custom lift; await so
                    // the auto-select below sees the freshly-loaded
                    // library rather than racing the load.
                    Task { await library.load() }
                    // Auto-select the newly created exercise so the
                    // user goes straight back into their workout with
                    // the new lift added — matches the picker's
                    // standard tap → onSelect → dismiss flow.
                    onSelect(custom.asExercise())
                    dismiss()
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
                    ForEach(results) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            ExerciseRow(exercise: exercise, showsChevron: false)
                                .overlay(alignment: .trailing) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(AppColor.accentPrimary)
                                }
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
    }
}
