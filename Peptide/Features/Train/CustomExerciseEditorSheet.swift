import SwiftUI

/// Lightweight create / edit form for a `CustomExercise`. Surfaces
/// the niche-lift path (landmine row, kettlebell halo, anything not
/// in the bundled 800+ catalog) without dragging the user through a
/// full SwiftData routine builder. Submits via
/// `SwiftDataRepository.upsertCustomExercise` and reloads
/// `ExerciseLibrary.shared` so the new entry appears in the picker
/// on dismiss (audit Train H1).
struct CustomExerciseEditorSheet: View {
    let editing: CustomExercise?
    let onSave: (CustomExercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var primaryMuscle: MuscleGroup
    @State private var secondaryMuscles: Set<MuscleGroup>
    @State private var equipment: EquipmentKind
    @FocusState private var nameFocused: Bool

    init(editing: CustomExercise? = nil, onSave: @escaping (CustomExercise) -> Void) {
        self.editing = editing
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        let firstPrimary = editing?.primaryMuscles.first
            .flatMap { MuscleGroup.fromRaw($0) } ?? .chest
        _primaryMuscle = State(initialValue: firstPrimary)
        let secondaries = Set((editing?.secondaryMuscles ?? []).compactMap { MuscleGroup.fromRaw($0) })
        _secondaryMuscles = State(initialValue: secondaries)
        // EquipmentKind.fromRaw takes Optional<String> and returns a
        // non-optional value (with .bodyweight as the fallback for
        // unknown / nil raws).
        _equipment = State(initialValue: EquipmentKind.fromRaw(editing?.equipment))
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
                            Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
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
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear {
                if editing == nil { nameFocused = true }
            }
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let custom = CustomExercise(
            id: editing?.id ?? "custom_\(UUID().uuidString)",
            name: trimmed,
            primaryMuscles: [primaryMuscle.rawValue],
            secondaryMuscles: secondaryMuscles
                .filter { $0 != primaryMuscle }
                .map(\.rawValue),
            equipment: equipment.rawValue,
            instructions: editing?.instructions ?? [],
            createdAt: editing?.createdAt ?? Date()
        )
        onSave(custom)
        dismiss()
    }
}
