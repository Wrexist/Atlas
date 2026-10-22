import SwiftUI

/// Lightweight create form for a `CustomExercise`. Surfaces
/// the niche-lift path (landmine row, kettlebell halo, anything not
/// in the bundled 800+ catalog) without dragging the user through a
/// full SwiftData routine builder. Submits via
/// `SwiftDataRepository.upsertCustomExercise` and reloads
/// `ExerciseLibrary.shared` so the new entry appears in the picker
/// on dismiss (audit Train H1).
struct CustomExerciseEditorSheet: View {
    let onSave: (CustomExercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var primaryMuscle = MuscleGroup.chest
    @State private var secondaryMuscles: Set<MuscleGroup> = []
    @State private var equipment = EquipmentKind.bodyweight
    @FocusState private var nameFocused: Bool

    init(onSave: @escaping (CustomExercise) -> Void) {
        self.onSave = onSave
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onChange(of: name) { _, new in
                            // 64-char cap at the input boundary so a
                            // paste flood can't balloon the field.
                            if new.count > 64 { name = String(new.prefix(64)) }
                        }
                }

                Section("Primary muscle") {
                    Picker("Primary muscle", selection: $primaryMuscle) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Equipment") {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(EquipmentKind.allCases.filter { $0 != .other }) { kind in
                            Label { Text(kind.displayName) } icon: { kind.glyph.image }
                                .tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Secondary muscles (optional)") {
                    ForEach(MuscleGroup.allCases) { group in
                        Toggle(group.displayName,
                               isOn: Binding(
                                get: { secondaryMuscles.contains(group) },
                                set: { isOn in
                                    if isOn { secondaryMuscles.insert(group) }
                                    else { secondaryMuscles.remove(group) }
                                }
                               ))
                    }
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let custom = CustomExercise(
            id: "\(CustomExercise.idPrefix)\(UUID().uuidString)",
            name: trimmed,
            primaryMuscles: [primaryMuscle.rawValue],
            secondaryMuscles: secondaryMuscles
                .filter { $0 != primaryMuscle }
                .map(\.rawValue),
            equipment: equipment.rawValue,
            instructions: [],
            createdAt: Date()
        )
        onSave(custom)
        dismiss()
    }
}
