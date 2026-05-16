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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search exercises")
            )
            .task { await library.load() }
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
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Try a different muscle group or clear the filters."
            )
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
