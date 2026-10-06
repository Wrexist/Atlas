import SwiftUI

/// Single-set row inside the active-workout exercise card. Renders
/// the set index, an editable weight in the user's unit, an editable
/// reps count,
/// optional RPE, the "previous session" hint when available, and a
/// completion checkbox.
///
/// Set logging optimises for taps-to-completion: prev values are
/// pre-filled by `WorkoutSessionService.addSet`, so the user often
/// just taps the checkmark.
struct SetEditorRow: View {
    @Binding var set: SetEntry
    let previousSet: SetEntry?
    /// The user's weight unit. `SetEntry.weightKg` is canonical
    /// kilograms, so this row converts on both read and write —
    /// without it an imperial user typing "225" stores 225 kg.
    let unit: MeasurementUnit
    let onDelete: () -> Void
    var focusStyle = false
    var isCurrent = false
    var isPaused = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var inputHeight: CGFloat = 48
    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool
    @State private var completionTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            let rowLayout = focusStyle && dynamicTypeSize.isAccessibilitySize
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
                previousReference
                    .padding(.leading, Spacing.xxxl)
            }
            if let load = set.measurement?.load, load != .recorded {
                Text(load == .eachPair ? "Load per hand · both counted" :
                    (load == .perSide ? "Load per side · entered reps counted once" : "Combined load"))
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onChange(of: set.completed) { _, completed in
            if completed { completionTrigger &+= 1 }
        }
        // Focus mode has an explicit index menu. A second menu on the whole
        // row competes with the TextField's long-press selection gesture.
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
                    Label(set.isWarmup ? "Mark as working set" : "Mark as warm-up", systemImage: "flame")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete set", systemImage: "trash")
                }
            } label: {
                indexLabel.minimumHitArea()
            }
            .accessibilityLabel(Text("Options for set \(set.index)"))
        } else {
            indexLabel
        }
    }

    private var indexLabel: some View {
        Text("\(set.index)")
            .font(AppFont.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isCurrent ? AppColor.trainingSelection : AppColor.textPrimary)
            .frame(minWidth: 24, minHeight: 24)
            .background(
                Circle()
                    .fill(isCurrent ? AppColor.trainingInput : AppColor.surfaceSecondary)
            )
            .overlay(
                Circle().stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var previousReference: some View {
        if set.isWarmup {
            Text("Warmup")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.streak)
        } else if let prev = previousSet {
            Button {
                fill(from: prev)
            } label: {
                Text("\(formatted(prev.weightKg)) × \(prev.reps)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Previous: \(formatted(prev.weightKg)) \(unit.weightSpokenUnit) for \(prev.reps) reps"))
            .accessibilityHint(Text("Fills this set with the same weight and reps"))
        } else {
            Text("—")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private var weightField: some View {
        HStack(spacing: Spacing.xs) {
            TextField(unit.weightSuffix,
                      value: Binding(
                        get: { unit.weightForDisplay(set.weightKg) },
                        set: { set.weightKg = SetEntryLimits.clampWeightKg(unit.kilograms(fromDisplayed: $0)) }
                      ),
                      format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .focused($weightFocused)
                .accessibilityIdentifier("workout-weight-\(set.index)")
            if focusStyle {
                Text(unit.weightSuffix).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
            .frame(width: focusStyle ? nil : 60, height: focusStyle ? inputHeight : 32)
            .frame(maxWidth: focusStyle ? .infinity : nil)
            .padding(.horizontal, focusStyle ? Spacing.sm : 0)
            .background(
                RoundedRectangle(cornerRadius: focusStyle ? Spacing.sheetCornerRadius : Spacing.chipCornerRadius, style: .continuous)
                    .fill(focusStyle ? AppColor.trainingInput : AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: focusStyle ? Spacing.sheetCornerRadius : Spacing.chipCornerRadius, style: .continuous)
                    .stroke(weightFocused ? AppColor.accentPrimary : AppColor.glassBorder,
                            lineWidth: weightFocused ? 1 : 0.5)
            )
            .accessibilityLabel(Text("Weight for set \(set.index)"))
            .accessibilityValue(Text("\(formatted(set.weightKg)) \(unit.weightSpokenUnit)"))
    }

    private var repsField: some View {
        TextField("reps",
                  value: Binding(
                    get: { set.reps },
                    set: { set.reps = SetEntryLimits.clampReps($0) }
                  ),
                  format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(AppColor.textPrimary)
            .monospacedDigit()
            .focused($repsFocused)
            .accessibilityIdentifier("workout-reps-\(set.index)")
            .frame(width: focusStyle ? nil : 48, height: focusStyle ? inputHeight : 32)
            .frame(maxWidth: focusStyle ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: focusStyle ? Spacing.sheetCornerRadius : Spacing.chipCornerRadius, style: .continuous)
                    .fill(focusStyle ? AppColor.trainingInput : AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: focusStyle ? Spacing.sheetCornerRadius : Spacing.chipCornerRadius, style: .continuous)
                    .stroke(repsFocused ? AppColor.accentPrimary : AppColor.glassBorder,
                            lineWidth: repsFocused ? 1 : 0.5)
            )
            .accessibilityLabel(Text("Reps for set \(set.index)"))
            .accessibilityValue(Text("\(set.reps) reps"))
    }

    private var completionToggle: some View {
        Button {
            weightFocused = false
            repsFocused = false
            if !set.completed { Haptics.impact(.light) }
            else { Haptics.selection() }
            set.completed.toggle()
        } label: {
            Image(systemName: set.completed ? "checkmark.circle.fill" : (focusStyle ? "checkmark.circle" : "circle"))
                .font(AppFont.scaled(24, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    set.completed ? AppColor.onAccent : AppColor.textTertiary,
                    set.completed ? (focusStyle ? AppColor.trainingComplete : AppColor.positive) : AppColor.textTertiary
                )
                .frame(width: 32, height: 32)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .completionPulse(trigger: completionTrigger, isActive: set.completed)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .disabled(isPaused)
        .accessibilityIdentifier("workout-complete-\(set.index)")
        .accessibilityLabel(set.completed ? "Set complete" : "Mark set complete")
        .accessibilityValue(isCurrent ? "Current set" : "")
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

    private func formatted(_ kg: Double) -> String {
        let value = unit.weightForDisplay(kg)
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
