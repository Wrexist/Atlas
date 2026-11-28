import SwiftUI

/// Single-set row inside the active-workout exercise card. Renders
/// the set index, the weight in the user's unit and the reps — a tap on
/// either opens `SetValuePickerSheet`'s wheels — the "previous session"
/// hint when available, and a completion checkbox.
///
/// Set logging optimises for taps-to-completion: prev values are
/// pre-filled by `WorkoutSessionService.addSet`, so the user often
/// just taps the checkmark.
struct SetEditorRow: View {
    @Binding var set: SetEntry
    let previousSet: SetEntry?
    /// The set's position among the working sets, as the focus header
    /// counts them; nil for a warm-up, which is badged "W".
    let displayNumber: Int?
    /// The user's weight unit. `SetEntry.weightKg` is canonical
    /// kilograms, so this row converts on both read and write —
    /// without it an imperial user typing "225" stores 225 kg.
    let unit: MeasurementUnit
    let onDelete: () -> Void
    var focusStyle = false
    var isCurrent = false
    var isPaused = false
    /// The equipment's smallest jump in kilograms, for the picker's
    /// minus and plus buttons; nil where none applies.
    var stepKg: Double?
    /// The exercise's bar, so the picker shows the plates as weight turns.
    var bar: BarKind?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var inputHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .callout) private var compactWeightWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .callout) private var compactRepsWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .callout) private var compactInputHeight: CGFloat = Spacing.minimumHitTarget
    @State private var pickerField: SetValuePickerSheet.Field?
    @State private var completionTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            let rowLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Spacing.sm))
            rowLayout {
                indexBadge
                if !focusStyle {
                    previousReference.frame(maxWidth: .infinity, alignment: .leading)
                }
                weightField
                repsField
                completionToggle
            }
            if focusStyle && (previousSet != nil || set.isWarmup) {
                // Under the weight field's leading edge: the index menu's
                // 44pt target plus the row's gap.
                previousReference
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : Spacing.minimumHitTarget + Spacing.sm)
            }
            if let load = set.measurement?.load, load != .recorded {
                Text(load == .eachPair ? String(localized: "Load per hand · both counted") :
                    (load == .perSide ? String(localized: "Load per side · entered reps counted once") : String(localized: "Combined load")))
                    .font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        // A logged set reads as done at a glance, not only through its glyph.
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.success.opacity(set.completed ? 0.10 : 0))
                .padding(.horizontal, -Spacing.xs)
        }
        .appAnimation(AppAnimation.springSnappy, value: set.completed)
        .contentShape(Rectangle())
        .onChange(of: set.completed) { _, completed in
            if completed { completionTrigger &+= 1 }
        }
        .sheet(item: $pickerField) { field in
            SetValuePickerSheet(set: $set, title: pickerTitle, unit: unit, stepKg: stepKg,
                                bar: bar, previousSet: previousSet, initialField: field)
        }
        // Focus mode has an explicit index menu; the compact row keeps
        // its options on a long press.
        .contextMenu {
            if !focusStyle {
                Button(action: toggleWarmup) {
                    Label(set.isWarmup ? "Mark as working set" : "Mark as warm-up",
                          systemImage: set.isWarmup ? "dumbbell" : "flame")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete set", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var indexBadge: some View {
        if focusStyle {
            Menu {
                Button(action: toggleWarmup) {
                    Label(set.isWarmup ? "Mark as working set" : "Mark as warm-up",
                          systemImage: set.isWarmup ? "dumbbell" : "flame")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete set", systemImage: "trash")
                }
            } label: {
                indexLabel.minimumHitArea()
            }
            .accessibilityLabel(displayNumber.map { Text("Options for set \($0)") } ?? Text("Options for warm-up set"))
        } else {
            indexLabel
        }
    }

    private var indexLabel: some View {
        Group {
            if let displayNumber {
                Text("\(displayNumber)")
            } else {
                Text(String(localized: "set.warmupBadge", defaultValue: "W", comment: "Badge on a warm-up set row"))
            }
        }
            .font(AppFont.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isCurrent ? AppColor.accentPrimary : AppColor.textPrimary)
            .frame(minWidth: 24, minHeight: 24)
            .background(
                Circle()
                    .fill(AppColor.surfaceSecondary)
            )
            .overlay(
                Circle().stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var previousReference: some View {
        if set.isWarmup {
            Text("Warm-up")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.streak)
        } else if let prev = previousSet {
            Button {
                fill(from: prev)
            } label: {
                // A previous set with no load reads as reps alone, not "0 × 8".
                Group {
                    if prev.weightKg > 0 {
                        Text("\(unit.weightValue(prev.weightKg, fractionDigits: 0...2)) × \(prev.reps)")
                    } else {
                        Text("\(prev.reps) reps")
                    }
                }
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prev.weightKg > 0
                ? Text("Previous: \(unit.weightValue(prev.weightKg, fractionDigits: 0...2)) \(unit.weightSpokenUnit) for ^[\(prev.reps) rep](inflect: true)")
                : Text("Previous: \(prev.reps) reps"))
            .accessibilityHint(Text("Fills this set with the same weight and reps"))
        } else {
            Text("—")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    /// A logged set's numbers step back so the sets still to do lead.
    private var fieldInk: Color {
        self.set.completed ? AppColor.textSecondary : AppColor.textPrimary
    }

    private var weightField: some View {
        Button { openPicker(.weight) } label: {
            HStack(spacing: Spacing.xs) {
                Text(verbatim: unit.weightValue(set.weightKg, fractionDigits: 0...2))
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(fieldInk)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if focusStyle {
                    Text(unit.weightSuffix).font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: focusStyle ? nil : compactWeightWidth, height: focusStyle ? inputHeight : compactInputHeight)
            .frame(maxWidth: focusStyle ? .infinity : nil)
            .padding(.horizontal, focusStyle ? Spacing.sm : 0)
            .background(fieldShape.fill(fieldFill))
            .overlay(fieldOutline(isEditing: pickerField == .weight))
            .contentShape(fieldShape)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityIdentifier("workout-weight-\(set.index)")
        .accessibilityLabel(displayNumber.map { Text("Weight for set \($0)") } ?? Text("Weight for warm-up set"))
        .accessibilityValue(Text("\(unit.weightValue(set.weightKg, fractionDigits: 0...2)) \(unit.weightSpokenUnit)"))
        .accessibilityHint(Text("Opens wheels to drag the weight and reps up or down"))
    }

    private var repsField: some View {
        Button { openPicker(.reps) } label: {
            Text(verbatim: "\(set.reps)")
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(fieldInk)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: focusStyle ? nil : compactRepsWidth, height: focusStyle ? inputHeight : compactInputHeight)
                .frame(maxWidth: focusStyle ? .infinity : nil)
                .background(fieldShape.fill(fieldFill))
                .overlay(fieldOutline(isEditing: pickerField == .reps))
                .contentShape(fieldShape)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityIdentifier("workout-reps-\(set.index)")
        .accessibilityLabel(displayNumber.map { Text("Reps for set \($0)") } ?? Text("Reps for warm-up set"))
        .accessibilityValue(Text("^[\(set.reps) rep](inflect: true)"))
        .accessibilityHint(Text("Opens wheels to drag the weight and reps up or down"))
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: focusStyle ? Spacing.sheetCornerRadius : Spacing.chipCornerRadius, style: .continuous)
    }

    private var fieldFill: Color {
        focusStyle ? AppColor.surfaceSecondary : AppColor.surfaceSecondary.opacity(0.6)
    }

    /// The accent ring marks which value the open picker was opened from.
    private func fieldOutline(isEditing: Bool) -> some View {
        fieldShape.stroke(isEditing ? AppColor.accentPrimary : AppColor.glassBorder, lineWidth: isEditing ? 1 : 0.5)
    }

    private func openPicker(_ field: SetValuePickerSheet.Field) {
        Haptics.selection()
        pickerField = field
    }

    private var pickerTitle: Text {
        displayNumber.map { Text("Set \($0)") } ?? Text("Warm-up set")
    }

    private var completionToggle: some View {
        Button {
            if !set.completed { Haptics.impact(.medium) }
            else { Haptics.selection() }
            set.completed.toggle()
        } label: {
            Image(systemName: set.completed ? "checkmark.circle.fill" : (focusStyle ? "checkmark.circle" : "circle"))
                .font(AppFont.scaled(24, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    set.completed ? AppColor.onAccent : AppColor.textTertiary,
                    // The same green as the row's done wash behind it.
                    set.completed ? AppColor.success : AppColor.textTertiary
                )
                .frame(width: 32, height: 32)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .completionPulse(trigger: completionTrigger, isActive: set.completed)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .disabled(isPaused)
        .accessibilityIdentifier("workout-complete-\(set.index)")
        .accessibilityLabel(completionLabel)
        .accessibilityValue(isCurrent ? "Current set" : "")
    }

    private var completionLabel: Text {
        switch (displayNumber, set.completed) {
        case let (number?, true): Text("Set \(number) complete")
        case let (number?, false): Text("Mark set \(number) complete")
        case (nil, true): Text("Warm-up set complete")
        case (nil, false): Text("Mark warm-up set complete")
        }
    }

    /// One write, not two: the parent's binding re-reads a snapshot that
    /// doesn't update until the next render, so a second property write
    /// would overwrite the first.
    private func fill(from previous: SetEntry) {
        guard previous.supportsRepLogging else { return }
        var filled = set
        filled.weightKg = previous.weightKg
        filled.reps = previous.reps
        filled.measurement = previous.measurement
        set = filled
        Haptics.selection()
    }

    private func toggleWarmup() {
        var toggled = set
        toggled.isWarmup.toggle()
        set = toggled
    }
}
