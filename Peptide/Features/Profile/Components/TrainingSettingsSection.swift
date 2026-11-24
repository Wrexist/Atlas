import SwiftUI

/// The settings a training-first user reaches for most — display units,
/// the daily step goal, the rest timer's fallback length and
/// auto-progression. The plates and bars the plate calculator loads are set
/// once per gym, so they sit one tap in under "Gym equipment".
/// `SettingsView` titles the card.
struct TrainingSettingsSection: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        @Bindable var store = dataStore

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                MeasurementUnitRow(selection: $store.profile.bodyMetrics.unit)
                    .onChange(of: dataStore.profile.bodyMetrics.unit) { _, _ in
                        dataStore.persistProfile()
                    }

                Divider().overlay(AppColor.glassBorder)

                StepGoalRow(goal: stepGoalBinding)

                Divider().overlay(AppColor.glassBorder)

                RestTimerRow(selection: restTimerBinding)

                Divider().overlay(AppColor.glassBorder)

                SettingsToggleRow(
                    icon: "arrow.up.right",
                    title: "Auto-progression",
                    subtitle: "Suggest the weight and reps to beat",
                    isOn: autoProgressionBinding
                )

                Divider().overlay(AppColor.glassBorder)

                GymEquipmentEntryRow()
            }
        }
    }

    /// `trainingPreferences` is nil until onboarding's training steps run,
    /// so reads fall back to the model default and the first write seeds a
    /// default preferences value rather than dropping the change.
    private var restTimerBinding: Binding<Int> {
        Binding(
            get: { preferences.restTimerDefault },
            set: { seconds in
                var updated = preferences
                updated.restTimerDefault = seconds
                dataStore.updateTrainingPreferences(updated)
            }
        )
    }

    private var stepGoalBinding: Binding<Int> {
        Binding(
            get: { preferences.stepGoal },
            set: { goal in
                var updated = preferences
                updated.dailyStepGoal = StepGoalEngine.clamped(goal)
                dataStore.updateTrainingPreferences(updated)
            }
        )
    }

    private var autoProgressionBinding: Binding<Bool> {
        Binding(
            get: { preferences.autoProgression },
            set: { enabled in
                var updated = preferences
                updated.autoProgression = enabled
                dataStore.updateTrainingPreferences(updated)
            }
        )
    }

    private var preferences: TrainingPreferences {
        dataStore.profile.trainingPreferences ?? TrainingPreferences()
    }
}

/// The drill-in to `GymEquipmentView`, laid out like the card's other rows.
private struct GymEquipmentEntryRow: View {
    var body: some View {
        NavigationLink {
            GymEquipmentView()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "dumbbell.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: settingsIconColumnWidth)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Gym equipment")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Plates and bar weights")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The plates and bars the plate calculator loads, pushed from Settings'
/// Training card. Set once per gym, so they don't crowd the everyday rows.
private struct GymEquipmentView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        ScrollView {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    PlateInventoryRow(unit: unit, available: platesBinding)

                    Divider().overlay(AppColor.glassBorder)

                    BarWeightsRow(unit: unit, weight: barWeightBinding)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxxl)
            .readableContentWidth()
        }
        .pageBackground()
        .navigationTitle("Gym equipment")
        .navigationBarTitleDisplayMode(.inline)
        .solidTopScrollEdge()
    }

    private var unit: MeasurementUnit { dataStore.profile.bodyMetrics.unit }

    private var platesBinding: Binding<[Double]> {
        Binding(
            get: { preferences.plates(for: unit) },
            set: { plates in
                var updated = preferences
                updated.setPlates(plates, for: unit)
                dataStore.updateTrainingPreferences(updated)
            }
        )
    }

    private func barWeightBinding(_ bar: BarKind) -> Binding<Double> {
        Binding(
            get: { preferences.barWeight(bar, unit: unit) },
            set: { weight in
                var updated = preferences
                updated.setBarWeight(weight, for: bar, unit: unit)
                dataStore.updateTrainingPreferences(updated)
            }
        )
    }

    private var preferences: TrainingPreferences {
        dataStore.profile.trainingPreferences ?? TrainingPreferences()
    }
}

/// Metric / Imperial for the body-metric and training surfaces (weight,
/// height, waist, temperature, loads). Peptide doses stay in mcg/mg
/// regardless — they're prescribed in metric everywhere.
private struct MeasurementUnitRow: View {
    @Binding var selection: MeasurementUnit

    var body: some View {
        SettingsPickerRow(
            icon: "ruler.fill",
            title: "Units",
            subtitle: selection == .metric ? "kg · cm · °C" : "lb · in · °F"
        ) {
            GlassSegmentedControl(
                options: [MeasurementUnit.metric, .imperial],
                selected: $selection,
                label: { $0 == .metric ? "Metric" : "Imperial" }
            )
        }
    }
}

/// The Health step count Today's checklist and Steps card count toward.
private struct StepGoalRow: View {
    @Binding var goal: Int

    var body: some View {
        SettingsPickerRow(
            icon: "figure.walk",
            title: "Daily step goal",
            subtitle: "Today checks off steps once you reach it"
        ) {
            Stepper(value: $goal, in: StepGoalEngine.goalRange, step: StepGoalEngine.goalIncrement) {
                Text("\(goal.formatted()) steps")
                    .font(AppFont.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textSecondary)
            }
            .onChange(of: goal) { _, _ in Haptics.selection() }
        }
    }
}

/// Rest applied after a completed set when neither the routine nor the
/// exercise sets its own.
private struct RestTimerRow: View {
    @Binding var selection: Int

    private static let presets = [30, 60, 90, 120, 180, 240]

    /// A stored value outside the presets (an older build, a restored
    /// backup) still gets a segment, so the picker never shows no selection.
    private var choices: [Int] {
        Self.presets.contains(selection) ? Self.presets : (Self.presets + [selection]).sorted()
    }

    var body: some View {
        SettingsPickerRow(
            icon: "timer",
            title: "Default rest timer",
            subtitle: "\(WorkoutClock.label(selection)) between sets"
        ) {
            // Six segments fit a phone at default sizes; at large Dynamic
            // Type or on a narrow screen they'd truncate, so fall back to a menu.
            ViewThatFits(in: .horizontal) {
                GlassSegmentedControl(
                    options: choices,
                    selected: $selection,
                    label: { LocalizedStringKey(WorkoutClock.label($0)) }
                )
                Picker("Default rest timer", selection: $selection) {
                    ForEach(choices, id: \.self) { seconds in
                        Text(WorkoutClock.label(seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}

/// Which standard plates the user's gym stocks, in the display unit. The
/// plate calculator only loads these, and a barbell's progression jump is
/// a pair of the lightest one.
private struct PlateInventoryRow: View {
    let unit: MeasurementUnit
    @Binding var available: [Double]

    var body: some View {
        SettingsPickerRow(
            icon: "circle.circle.fill",
            title: "Plates",
            subtitle: "The plate calculator loads only these"
        ) {
            // Neutral ink, not the accent: a stocked plate is a fact about
            // the gym, not a highlighted choice.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: Spacing.chipSpacing)],
                alignment: .leading,
                spacing: Spacing.chipSpacing
            ) {
                ForEach(PlateCalculatorEngine.defaultPlates(for: unit), id: \.self) { plate in
                    GlassChip(
                        "\(plate.formatted(.number.precision(.fractionLength(0...2)))) \(unit.weightSuffix)",
                        tint: AppColor.textPrimary,
                        isSelected: available.contains(plate)
                    ) {
                        toggle(plate)
                    }
                }
            }
        }
    }

    /// The last plate can't be removed: with none left the calculator
    /// can't load the bar and there's no barbell jump to progress by.
    private func toggle(_ plate: Double) {
        if available.contains(plate) {
            guard available.count > 1 else {
                Haptics.error()
                return
            }
            available.removeAll { $0 == plate }
        } else {
            available = (available + [plate]).sorted(by: >)
        }
    }
}

/// Empty weight of each bar the plate calculator knows, in the display
/// unit. Zero is allowed: some Smith machines are counterbalanced.
private struct BarWeightsRow: View {
    let unit: MeasurementUnit
    let weight: (BarKind) -> Binding<Double>

    private var step: Double { unit == .metric ? 0.5 : 1 }
    private var range: ClosedRange<Double> { unit == .metric ? 0...40 : 0...90 }

    var body: some View {
        SettingsPickerRow(
            icon: "scalemass.fill",
            title: "Bar weights",
            subtitle: "Empty weight of each bar"
        ) {
            VStack(spacing: Spacing.xs) {
                ForEach(BarKind.allCases) { bar in
                    Stepper(value: weight(bar), in: range, step: step) {
                        HStack(spacing: Spacing.sm) {
                            Text(bar.displayName)
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer(minLength: Spacing.xs)
                            Text("\(weight(bar).wrappedValue.formatted(.number.precision(.fractionLength(0...1)))) \(unit.weightSuffix)")
                                .font(AppFont.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize()
                        }
                    }
                    .onChange(of: weight(bar).wrappedValue) { _, _ in Haptics.selection() }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TrainingSettingsSection()
            .padding(Spacing.screenPadding)
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
