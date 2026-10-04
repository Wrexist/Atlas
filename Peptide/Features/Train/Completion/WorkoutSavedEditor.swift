import SwiftUI

/// Value-type draft: dismissing never mutates a saved session.
struct WorkoutSavedEditor: View {
    let unit: MeasurementUnit
    let onSave: (WorkoutSession) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutSession
    @State private var error: String?
    @State private var saving = false

    init(session: WorkoutSession, unit: MeasurementUnit, onSave: @escaping (WorkoutSession) throws -> Void) {
        self.unit = unit
        self.onSave = onSave
        _draft = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Workout name", text: Binding(get: { draft.name ?? "" }, set: { draft.name = $0 }))
                    TextField("Private notes", text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0 }), axis: .vertical)
                }
                ForEach($draft.exercises) { $entry in
                    Section(ExerciseLibrary.shared.lookup(id: entry.exerciseID)?.name ?? entry.exerciseID) {
                        ForEach($entry.sets) { $set in
                            DisclosureGroup("Set \(set.index) · \(RecapFormat.set(set, unit: unit))") {
                                RecapSetEditor(set: $set, unit: unit)
                            }
                        }
                    }
                }
                Section {
                    Text("Only completed working sets contribute to recap totals. Changing a load convention changes recorded volume; existing records keep their original meaning until you explicitly change it.")
                }
                if let error { Section { Text(error).foregroundStyle(AppColor.destructive).accessibilityIdentifier("workout-edit-error") } }
            }
            .navigationTitle("Edit workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving || !valid)
                        .accessibilityIdentifier("save-workout-edits")
                }
            }
            .interactiveDismissDisabled(saving)
        }.tint(AppColor.recapAction)
    }

    private var valid: Bool {
        draft.completedSetCount > 0 && draft.exercises.flatMap(\.sets).allSatisfy {
            $0.weightKg.isFinite && SetEntryLimits.weightKg.contains($0.weightKg) && SetEntryLimits.reps.contains($0.reps)
                && (($0.measurement?.seconds).map { $0.isFinite && $0 >= 0 } ?? true)
                && (($0.measurement?.meters).map { $0.isFinite && $0 >= 0 } ?? true)
        }
    }

    private func save() {
        guard !saving, valid else { return }
        saving = true
        Task { @MainActor in
            await Task.yield()
            do {
                try onSave(draft)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                AccessibilityNotification.Announcement("Could not save changes").post()
            }
            saving = false
        }
    }
}

private struct RecapSetEditor: View {
    @Binding var set: SetEntry
    let unit: MeasurementUnit
    private var measurement: Binding<SetEntry.Measurement> {
        Binding(get: { set.measurement ?? .init() }, set: { set.measurement = $0 })
    }
    var body: some View {
        Toggle("Completed", isOn: $set.completed)
            .onChange(of: set.completed) { _, completed in set.completedAt = completed ? (set.completedAt ?? Date()) : nil }
        Toggle("Warm-up", isOn: $set.isWarmup)
        Picker("Measurement", selection: measurement.kind) {
            Text("Repetitions").tag(SetEntry.Measurement.Kind.repetitions)
            Text("Bodyweight / added load").tag(SetEntry.Measurement.Kind.bodyweight)
            Text("Timed").tag(SetEntry.Measurement.Kind.timed)
            Text("Distance").tag(SetEntry.Measurement.Kind.distance)
            Text("Assisted").tag(SetEntry.Measurement.Kind.assisted)
        }
        if set.measurement?.kind == .timed {
            numberField("Seconds", value: Binding(get: { set.measurement?.seconds ?? 0 }, set: {
                var m = set.measurement ?? .init(); m.seconds = $0; set.measurement = m
            }))
        } else if set.measurement?.kind == .distance {
            numberField("Meters", value: Binding(get: { set.measurement?.meters ?? 0 }, set: {
                var m = set.measurement ?? .init(); m.meters = $0; set.measurement = m
            }))
        } else {
            numberField("Load (\(unit.weightSuffix))", value: Binding(
                get: { unit.weightForDisplay(set.weightKg) },
                set: { set.weightKg = unit.kilograms(fromDisplayed: $0) }))
            HStack {
                Text("Reps")
                TextField("Reps", value: $set.reps, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .accessibilityLabel("Repetitions")
            }
            Picker("Load convention", selection: measurement.load) {
                Text("As recorded (legacy)").tag(SetEntry.Measurement.Load.recorded)
                Text("Combined total").tag(SetEntry.Measurement.Load.total)
                Text("Each, both counted").tag(SetEntry.Measurement.Load.eachPair)
                Text("Per side, recorded reps only").tag(SetEntry.Measurement.Load.perSide)
            }
            Text("Per-side records count the entered reps once. Log the other side separately when needed. Assistance is not subtracted from an assumed body weight.")
                .font(AppFont.caption)
        }
    }
    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }
}
