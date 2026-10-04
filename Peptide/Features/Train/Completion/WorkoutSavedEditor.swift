import SwiftUI

/// Value-type draft: dismissing never mutates a saved session.
struct WorkoutSavedEditor: View {
    let unit: MeasurementUnit
    let onSave: (WorkoutSession) throws -> Void
    private let original: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutSession
    @State private var error: String?
    @State private var saving = false
    @State private var invalidFields: Set<String> = []
    @FocusState private var focusedField: String?

    init(session: WorkoutSession, unit: MeasurementUnit, onSave: @escaping (WorkoutSession) throws -> Void) {
        self.unit = unit
        self.onSave = onSave
        self.original = session
        _draft = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Workout name", text: Binding(get: { draft.name ?? "" }, set: { draft.name = $0 }))
                        .focused($focusedField, equals: "name")
                    TextField("Private notes", text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0 }), axis: .vertical)
                        .focused($focusedField, equals: "notes")
                }
                ForEach($draft.exercises) { $entry in
                    Section(ExerciseLibrary.shared.lookup(id: entry.exerciseID)?.name ?? entry.exerciseID) {
                        ForEach($entry.sets) { $set in
                            DisclosureGroup("Set \(set.index) · \(RecapFormat.set(set, unit: unit))") {
                                RecapSetEditor(set: $set, unit: unit, invalidFields: $invalidFields, focusedField: $focusedField)
                            }
                            .accessibilityIdentifier("recap-edit-set-\(set.id.uuidString)")
                        }
                    }
                }
                Section {
                    Text("Only completed working sets contribute to recap totals. Changing a load convention changes recorded volume; existing records keep their original meaning until you explicitly change it.")
                }
                if let error { Section { Text(error).foregroundStyle(AppColor.destructive).accessibilityIdentifier("workout-edit-error") } }
                if let validationIssue {
                    Section { Text(validationIssue).foregroundStyle(AppColor.destructive).accessibilityIdentifier("workout-edit-validation") }
                }
            }
            .disabled(saving)
            .navigationTitle("Edit workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving || validationIssue != nil)
                        .accessibilityIdentifier("save-workout-edits")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(saving)
        }.tint(AppColor.recapAction)
    }

    private var validationIssue: String? {
        if !invalidFields.isEmpty { return "Correct the highlighted number fields before saving." }
        return WorkoutEditValidation.issue(in: draft, original: original)
    }

    private func save() {
        guard !saving, validationIssue == nil else { return }
        focusedField = nil
        saving = true
        Task { @MainActor in
            await Task.yield()
            guard validationIssue == nil else { saving = false; return }
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
    @Binding var invalidFields: Set<String>
    let focusedField: FocusState<String?>.Binding
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
        .onChange(of: set.measurement?.kind) { _, _ in
            invalidFields = invalidFields.filter { !$0.hasPrefix(set.id.uuidString) }
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
                set: { set.weightKg = unit.kilograms(fromDisplayed: $0) }),
                range: 0...unit.weightForDisplay(SetEntryLimits.weightKg.upperBound))
            numberField("Reps", value: Binding(get: { Double(set.reps) }, set: { set.reps = Int($0) }),
                        range: 0...Double(SetEntryLimits.reps.upperBound), wholeNumber: true)
            Picker("Load convention", selection: measurement.load) {
                Text("As recorded (legacy)").tag(SetEntry.Measurement.Load.recorded)
                Text("Combined total").tag(SetEntry.Measurement.Load.total)
                Text("Each, both counted").tag(SetEntry.Measurement.Load.eachPair)
                Text("Per side, recorded reps only").tag(SetEntry.Measurement.Load.perSide)
            }
            Text("Per-side records count the entered reps once. Log the other side separately when needed. Assistance is not subtracted from an assumed body weight.")
                .font(AppFont.subheadline)
        }
    }
    private func numberField(_ title: String, value: Binding<Double>,
                             range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude,
                             wholeNumber: Bool = false) -> some View {
        RecapNumberField(title: title, fieldID: set.id.uuidString + title, value: value,
                         invalidFields: $invalidFields, focusedField: focusedField, range: range, wholeNumber: wholeNumber)
    }
}

/// Keep invalid text visible, rather than silently saving the last parsed value.
private struct RecapNumberField: View {
    let title: String
    let fieldID: String
    @Binding var value: Double
    @Binding var invalidFields: Set<String>
    let focusedField: FocusState<String?>.Binding
    let range: ClosedRange<Double>
    let wholeNumber: Bool
    @State private var text: String

    init(title: String, fieldID: String, value: Binding<Double>, invalidFields: Binding<Set<String>>,
         focusedField: FocusState<String?>.Binding, range: ClosedRange<Double>, wholeNumber: Bool) {
        self.title = title
        self.fieldID = fieldID
        self._value = value
        self._invalidFields = invalidFields
        self.focusedField = focusedField
        self.range = range
        self.wholeNumber = wholeNumber
        _text = State(initialValue: value.wrappedValue.formatted(.number.grouping(.never).precision(.fractionLength(0...2))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                TextField(title, text: $text)
                    .keyboardType(wholeNumber ? .numberPad : .decimalPad).multilineTextAlignment(.trailing)
                    .accessibilityLabel(title).focused(focusedField, equals: fieldID)
            }
            if invalidFields.contains(fieldID) {
                Text(wholeNumber ? "Enter a whole number within the allowed range." : "Enter a valid number within the allowed range.")
                    .font(AppFont.subheadline).foregroundStyle(AppColor.destructive)
            }
        }
        .onAppear {
            if parsed(text) == nil { invalidFields.insert(fieldID) }
            else { invalidFields.remove(fieldID) }
        }
        .onChange(of: text) { _, newText in
            guard let parsed = parsed(newText) else {
                invalidFields.insert(fieldID)
                return
            }
            invalidFields.remove(fieldID)
            value = parsed
        }
    }

    private func parsed(_ input: String) -> Double? {
        guard let number = WorkoutEditValidation.number(input), range.contains(number),
              !wholeNumber || number.rounded() == number else { return nil }
        return number
    }
}
