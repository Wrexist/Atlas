import SwiftUI

/// One exercise's worth of sets inside the active-workout screen.
/// Header shows the exercise thumbnail + name + a context menu;
/// table of `SetEditorRow`s; "Add set" CTA at the bottom.
struct WorkoutExerciseCard: View {
    let entry: WorkoutExerciseEntry
    let exercise: Exercise?
    let unit: MeasurementUnit
    /// The completed sets from the last session that logged this
    /// exercise. Each row's "60 × 8" cue is paired to one of them by
    /// `PreviousSetEngine`; empty means no history and the cue reads "—".
    let previousSetsLookup: () -> [SetEntry]
    /// Today's target from `ProgressionEngine`; nil without history.
    let progression: ProgressionEngine.Suggestion?
    /// The user's training-preferences rest, used when the entry has no
    /// override of its own.
    let defaultRestSeconds: Int
    /// "A", "B"… when this exercise is in a superset.
    let supersetLetter: String?
    /// False for the last exercise, or when it's already in the superset below.
    let canSupersetWithNext: Bool
    /// The live copy of a set, so a row's writes never start from the
    /// render-time snapshot (see `WorkoutSessionService.currentSet`).
    let currentSet: (UUID) -> SetEntry?
    let onSetUpdate: (SetEntry) -> Void
    let onAddSet: () -> Void
    let onRemoveSet: (UUID) -> Void
    let onRemoveExercise: () -> Void
    let onSetRestSeconds: (Int?) -> Void
    let onApplyProgression: () -> Void
    let onSupersetWithNext: () -> Void
    let onRemoveFromSuperset: () -> Void

    @State private var confirmingRemoval = false
    @State private var showingPlateCalculator = false

    private var completedSetCount: Int { entry.sets.filter(\.completed).count }

    private var displayName: String { exercise?.name ?? String(localized: "Unknown exercise") }

    /// The bar to show plates for. Only when a set's weight is the whole
    /// bar — a per-side or per-hand entry isn't what goes on the scale.
    private var plateLoadedBar: BarKind? {
        guard entry.setToLoad?.isWholeBarLoad ?? false else { return nil }
        return exercise?.equipmentKind.bar
    }

    /// The next set's weight in the display unit, to open the calculator on.
    private var calculatorTarget: Double? {
        guard plateLoadedBar != nil, let weightKg = entry.setToLoad?.weightKg, weightKg > 0 else { return nil }
        return (unit.weightForDisplay(weightKg) * 100).rounded() / 100
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                Divider().background(AppColor.glassBorder)
                if let progression {
                    ProgressionHint(
                        suggestion: progression, unit: unit,
                        canApply: ProgressionEngine.isPending(progression, in: entry.sets),
                        onApply: onApplyProgression
                    )
                }
                setsList
                if let bar = plateLoadedBar, let set = entry.setToLoad {
                    PlateLoadStrip(weightKg: set.weightKg, unit: unit, bar: bar)
                }
                addSetButton
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            ExerciseImageView(
                exercise: exercise
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let supersetLetter {
                    Label("Superset \(supersetLetter)", systemImage: "link")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                } else if let exercise {
                    Text(exercise.muscleGroup.displayName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer()

            Menu {
                restMenu
                if canSupersetWithNext {
                    Button(action: onSupersetWithNext) {
                        Label("Superset with next exercise", systemImage: "link")
                    }
                }
                if supersetLetter != nil {
                    Button(action: onRemoveFromSuperset) {
                        Label("Remove from superset", systemImage: "xmark.circle")
                    }
                }
                if exercise?.equipmentKind.bar != nil {
                    Button {
                        showingPlateCalculator = true
                    } label: {
                        Label("Plate calculator", systemImage: "scalemass")
                    }
                }
                Button(role: .destructive, action: requestRemoval) {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(Spacing.xs)
                    .minimumHitArea()
            }
            .accessibilityLabel("Exercise options")
        }
        .sheet(isPresented: $showingPlateCalculator) {
            PlateCalculatorSheet(
                initialTarget: calculatorTarget,
                bar: exercise?.equipmentKind.bar ?? .olympic
            )
        }
        .confirmationDialog(
            "Remove \(displayName)?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive, action: onRemoveExercise)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    private var removalMessage: String {
        completedSetCount == 1
            ? String(localized: "Your completed set will be deleted.")
            : String(localized: "Your \(completedSetCount) completed sets will be deleted.")
    }

    private var restMenu: some View {
        RestTimeMenu(overrideSeconds: entry.restSeconds, defaultSeconds: defaultRestSeconds, onSelect: onSetRestSeconds)
    }

    /// Logged work is only lost behind a confirmation; an exercise with
    /// nothing checked off goes straight away.
    private func requestRemoval() {
        if completedSetCount > 0 {
            confirmingRemoval = true
        } else {
            onRemoveExercise()
        }
    }

    private var setsList: some View {
        // Resolved once per render, not per row.
        let hints = PreviousSetEngine.hints(for: entry.sets, previous: previousSetsLookup())
        return VStack(spacing: 0) {
            ForEach(entry.sets) { setSnapshot in
                SetEditorRow(
                    set: Binding(
                        get: { currentSet(setSnapshot.id) ?? setSnapshot },
                        set: { onSetUpdate($0) }
                    ),
                    previousSet: hints[setSnapshot.id],
                    unit: unit,
                    onDelete: { onRemoveSet(setSnapshot.id) }
                )
                if setSnapshot.id != entry.sets.last?.id {
                    Divider()
                        .background(AppColor.glassBorder.opacity(0.5))
                        .padding(.leading, Spacing.xl + Spacing.sm)
                }
            }
        }
    }

    private var addSetButton: some View {
        Button(action: onAddSet) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                Text("Add set")
            }
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(AppColor.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}

/// The one rest-time picker for an exercise in a workout — the overview
/// card and the focus screen both use it, so both show the current value
/// and tick the same haptic. "Default" clears the override so the exercise
/// follows the training-preferences rest again.
struct RestTimeMenu: View {
    let overrideSeconds: Int?
    let defaultSeconds: Int
    let onSelect: (Int?) -> Void

    private var current: Int { overrideSeconds ?? defaultSeconds }

    var body: some View {
        Menu {
            option(String(localized: "Default (\(RestTimeOptions.label(for: defaultSeconds)))"), seconds: nil)
            ForEach(RestTimeOptions.choices(including: overrideSeconds), id: \.self) { seconds in
                option(RestTimeOptions.label(for: seconds), seconds: seconds)
            }
        } label: {
            Label("Rest time · \(RestTimeOptions.label(for: current))", systemImage: "timer")
        }
    }

    private func option(_ title: String, seconds: Int?) -> some View {
        Button {
            Haptics.selection()
            onSelect(seconds)
        } label: {
            if seconds == overrideSeconds {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
