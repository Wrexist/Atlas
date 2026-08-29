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

    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            indexBadge

            previousReference
                .frame(maxWidth: .infinity, alignment: .leading)

            weightField
            repsField

            completionToggle
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        // .swipeActions is a no-op outside List/Form (audit Train
        // M1 — sets live in a VStack), so a long-press contextMenu
        // is the only way to expose the delete affordance without
        // restructuring the parent container.
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete set", systemImage: "trash")
            }
        }
    }

    private var indexBadge: some View {
        Text("\(set.index)")
            .font(AppFont.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(set.completed ? AppColor.background : AppColor.textPrimary)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(set.completed
                          ? AppColor.accentPrimary
                          : AppColor.surfaceSecondary.opacity(0.6))
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
            Text("\(formatted(prev.weightKg)) × \(prev.reps)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        } else {
            Text("—")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private var weightField: some View {
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
            .frame(width: 60, height: 32)
            .background(
                RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
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
            .frame(width: 48, height: 32)
            .background(
                RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                    .stroke(repsFocused ? AppColor.accentPrimary : AppColor.glassBorder,
                            lineWidth: repsFocused ? 1 : 0.5)
            )
            .accessibilityLabel(Text("Reps for set \(set.index)"))
            .accessibilityValue(Text("\(set.reps) reps"))
    }

    private var completionToggle: some View {
        Button {
            set.completed.toggle()
        } label: {
            Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(24, weight: .semibold))
                .foregroundStyle(set.completed
                                 ? AppColor.positive
                                 : AppColor.textTertiary)
                .frame(width: 32, height: 32)
                .contentTransition(.symbolEffect(.replace))
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set.completed ? "Set complete" : "Mark set complete")
    }

    private func formatted(_ kg: Double) -> String {
        let value = unit.weightForDisplay(kg)
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
