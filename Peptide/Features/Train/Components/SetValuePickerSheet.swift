import SwiftUI

/// Opened from a set row's weight or reps. Wheels replace the number pad:
/// drag weight (whole units and a fraction) and reps up or down, or nudge
/// the weight one equipment step with the minus and plus buttons — the
/// step comes from the user's lightest plates for a loaded bar, as the
/// progression suggestions use. Every turn writes straight to the set, so
/// Done only closes. The keyboard stays one tap away for an exact entry.
struct SetValuePickerSheet: View {
    enum Field: Hashable, Identifiable {
        case weight, reps

        var id: Self { self }
    }

    @Binding var set: SetEntry
    let title: Text
    let unit: MeasurementUnit
    /// The equipment's smallest jump in kilograms, nil when none applies.
    let stepKg: Double?
    /// The exercise's bar, to show the plates for the weight on the wheels.
    let bar: BarKind?
    let previousSet: SetEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var fieldHeight: CGFloat = NumberWheelMetrics.rowHeight
    @ScaledMetric(relativeTo: .title2) private var wholeWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .title2) private var fractionWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .title2) private var repsWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var timesWidth: CGFloat = 24
    @State private var weight: SetValueWheelEngine.Weight
    @State private var reps: Int
    @State private var typing: Bool
    @State private var weightText: String
    @State private var repsText: String
    @FocusState private var typingFocus: Field?
    private let initialField: Field

    init(set: Binding<SetEntry>, title: Text, unit: MeasurementUnit, stepKg: Double?,
         bar: BarKind?, previousSet: SetEntry?, initialField: Field) {
        self._set = set
        self.title = title
        self.unit = unit
        self.stepKg = stepKg
        self.bar = bar
        self.previousSet = previousSet
        self.initialField = initialField
        let entry = set.wrappedValue
        let display = unit.weightForDisplay(entry.weightKg)
        _weight = State(initialValue: SetValueWheelEngine.split(display, unit: unit))
        _reps = State(initialValue: entry.reps)
        _typing = State(initialValue: false)
        _weightText = State(initialValue: display.formatted(.number.grouping(.never).precision(.fractionLength(0...2))))
        _repsText = State(initialValue: "\(entry.reps)")
    }

    private var step: Double { SetValueWheelEngine.displayStep(incrementKg: stepKg, unit: unit) }

    private var wholeValues: [Int] {
        Array(SetValueWheelEngine.wholeRange(for: unit, holding: weight.value))
    }

    private var repsValues: [Int] { Array(SetValueWheelEngine.repsRange(holding: reps)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                if typing {
                    keyboardEntry
                } else {
                    wheels
                    stepButtons
                }
                if let bar, set.isWholeBarLoad, set.weightKg > 0 {
                    PlateLoadStrip(weightKg: set.weightKg, unit: unit, bar: bar)
                }
                if let previousSet, !set.isWarmup, previousSet.supportsRepLogging,
                   previousSet.weightKg != set.weightKg || previousSet.reps != set.reps {
                    previousButton(previousSet)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleTyping()
                    } label: {
                        Image(systemName: typing ? "arrow.up.arrow.down" : "keyboard")
                            .font(AppFont.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("set-picker-type")
                    .accessibilityLabel(typing ? Text("Use wheels") : Text("Type a number"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { finish() }
                        .accessibilityIdentifier("set-picker-done")
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .onChange(of: weight) { _, newWeight in writeWeight(newWeight.value) }
        .onChange(of: reps) { _, newReps in writeReps(newReps) }
        .onAppear { if dynamicTypeSize.isAccessibilitySize { typing = true } }
        .onDisappear { if typing { commitTyped() } }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Wheels

    /// Weight and reps each own half the width, so each pair of step
    /// buttons sits straight under the wheel it moves.
    private var wheels: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.xxs) {
                NumberWheel(values: wholeValues, selection: $weight.whole, alignment: .trailing,
                            accessibilityLabel: Text("Weight, whole \(unit.weightSpokenUnit)")) { "\($0)" }
                    .frame(width: wholeWidth)
                    .accessibilityIdentifier("set-picker-weight-wheel")
                NumberWheel(values: SetValueWheelEngine.fractions(for: unit), selection: $weight.fraction,
                            alignment: .leading, quietNeighbours: true,
                            accessibilityLabel: Text("Weight, fraction")) { fractionLabel($0) }
                    .frame(width: fractionWidth)
                unitLabel(Text(unit.weightSuffix))
            }
            .frame(maxWidth: .infinity)
            Text(verbatim: "×")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: timesWidth)
                .accessibilityHidden(true)
            HStack(spacing: Spacing.xs) {
                NumberWheel(values: repsValues, selection: $reps,
                            accessibilityLabel: Text("Reps")) { "\($0)" }
                    .frame(width: repsWidth)
                    .accessibilityIdentifier("set-picker-reps-wheel")
                unitLabel(Text("reps"))
            }
            .frame(maxWidth: .infinity)
        }
        .background { NumberWheelBand() }
        // Three wheels side by side only fit up to this size; larger
        // sizes open on the keyboard instead (see `body`).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func unitLabel(_ text: Text) -> some View {
        text
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
            .accessibilityHidden(true)
    }

    private func fractionLabel(_ fraction: Double) -> String {
        let digits = fraction.formatted(.number.precision(.fractionLength(1...2)))
        // ".25", not "0.25": the whole wheel to its left holds the units.
        return String(digits.drop { $0 == "0" })
    }

    // MARK: - Step buttons

    private var stepButtons: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                stepButton(up: false)
                stepButton(up: true)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: timesWidth, height: 1)
            HStack(spacing: Spacing.sm) {
                repsButton(by: -1)
                repsButton(by: 1)
            }
            .frame(maxWidth: .infinity)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var stepLabel: String {
        step.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func stepButton(up: Bool) -> some View {
        nudgeButton(symbol: up ? "plus" : "minus",
                    text: "\(stepLabel)",
                    accessibility: up ? Text("Add \(stepLabel) \(unit.weightSpokenUnit)")
                                      : Text("Remove \(stepLabel) \(unit.weightSpokenUnit)"),
                    identifier: up ? "set-picker-weight-up" : "set-picker-weight-down") {
            let upper = Double(SetValueWheelEngine.wholeRange(for: unit, holding: weight.value).upperBound)
            let next = min(upper, SetValueWheelEngine.stepped(weight.value, by: step, up: up))
            weight = SetValueWheelEngine.split(next, unit: unit)
        }
    }

    private func repsButton(by delta: Int) -> some View {
        nudgeButton(symbol: delta > 0 ? "plus" : "minus",
                    text: "1",
                    accessibility: delta > 0 ? Text("One more rep") : Text("One rep fewer"),
                    identifier: delta > 0 ? "set-picker-reps-up" : "set-picker-reps-down") {
            reps = min(SetEntryLimits.reps.upperBound, max(0, reps + delta))
        }
    }

    private func nudgeButton(symbol: String, text: String, accessibility: Text, identifier: String,
                             action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(AppFont.caption2.weight(.bold))
                Text(verbatim: text)
                    .font(AppFont.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .frame(minWidth: Spacing.minimumHitTarget, minHeight: Spacing.minimumHitTarget)
            .background(AppColor.surfaceSecondary, in: Capsule())
            .overlay(Capsule().stroke(AppColor.glassBorder, lineWidth: 0.5))
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(accessibility)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Previous

    private func previousButton(_ previous: SetEntry) -> some View {
        Button {
            Haptics.selection()
            var filled = set
            filled.weightKg = previous.weightKg
            filled.reps = previous.reps
            filled.measurement = previous.measurement
            set = filled
            weight = SetValueWheelEngine.split(unit.weightForDisplay(previous.weightKg), unit: unit)
            reps = previous.reps
            weightText = unit.weightForDisplay(previous.weightKg).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
            repsText = "\(previous.reps)"
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.uturn.backward")
                    .font(AppFont.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Group {
                    if previous.weightKg > 0 {
                        Text("Same as last time: \(unit.weightValue(previous.weightKg, fractionDigits: 0...2)) × \(previous.reps)")
                    } else {
                        Text("Same as last time: \(previous.reps) reps")
                    }
                }
                .font(AppFont.subheadline)
            }
            .foregroundStyle(AppColor.textSecondary)
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set-picker-previous")
    }

    // MARK: - Keyboard

    private var keyboardEntry: some View {
        HStack(spacing: Spacing.md) {
            typedField(Text("Weight (\(unit.weightSuffix))"), text: $weightText, field: .weight,
                       keyboard: .decimalPad, identifier: "set-picker-weight-field")
            typedField(Text("Reps"), text: $repsText, field: .reps,
                       keyboard: .numberPad, identifier: "set-picker-reps-field")
        }
        .onAppear { typingFocus = initialField }
    }

    private func typedField(_ label: Text, text: Binding<String>, field: Field,
                            keyboard: UIKeyboardType, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            TextField(text: text) { label }
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .font(AppFont.title2)
                .monospacedDigit()
                .focused($typingFocus, equals: field)
                .frame(minHeight: fieldHeight)
                .background(AppColor.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .stroke(typingFocus == field ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: typingFocus == field ? 1 : 0.5)
                )
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Writes

    private func toggleTyping() {
        if typing {
            commitTyped()
            weight = SetValueWheelEngine.split(unit.weightForDisplay(set.weightKg), unit: unit)
            reps = set.reps
        } else {
            weightText = unit.weightForDisplay(set.weightKg).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
            repsText = "\(set.reps)"
        }
        AppAnimation.with(AppAnimation.springSnappy) { typing.toggle() }
    }

    private func finish() {
        if typing { commitTyped() }
        dismiss()
    }

    /// Text that doesn't parse leaves the set as it was rather than zeroing it.
    private func commitTyped() {
        var updated = set
        if let typed = WorkoutEditValidation.number(weightText), typed >= 0 {
            updated.weightKg = SetEntryLimits.clampWeightKg(unit.kilograms(fromDisplayed: typed))
        }
        if let typed = WorkoutEditValidation.number(repsText), typed >= 0 {
            // Clamped as a Double first: Int() traps past Int.max.
            updated.reps = Int(min(typed, Double(SetEntryLimits.reps.upperBound)).rounded())
        }
        if updated != set { set = updated }
    }

    private func writeWeight(_ displayValue: Double) {
        // The wheels show the nearest quarter; a typed 72.3 stays 72.3
        // until the weight wheel itself turns.
        guard SetValueWheelEngine.split(unit.weightForDisplay(set.weightKg), unit: unit).value != displayValue
        else { return }
        var updated = set
        updated.weightKg = SetEntryLimits.clampWeightKg(unit.kilograms(fromDisplayed: displayValue))
        set = updated
    }

    private func writeReps(_ newReps: Int) {
        guard newReps != set.reps else { return }
        var updated = set
        updated.reps = SetEntryLimits.clampReps(newReps)
        set = updated
    }
}
