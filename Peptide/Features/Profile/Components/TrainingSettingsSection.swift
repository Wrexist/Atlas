import SwiftUI

/// The settings a training-first user reaches for most — display units,
/// the rest timer's fallback length, auto-progression, and the plates and
/// bars the plate calculator loads — surfaced near the top of Profile
/// instead of at the bottom of the general Settings card.
struct TrainingSettingsSection: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        @Bindable var store = dataStore

        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Training", systemImage: "dumbbell.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                MeasurementUnitRow(selection: $store.profile.bodyMetrics.unit)
                    .onChange(of: dataStore.profile.bodyMetrics.unit) { _, _ in
                        dataStore.persistProfile()
                    }

                Divider().overlay(AppColor.glassBorder)

                RestTimerRow(selection: restTimerBinding)

                Divider().overlay(AppColor.glassBorder)

                SettingsToggleRow(
                    icon: "arrow.up.right",
                    title: "Auto-progression",
                    subtitle: "Start each exercise at the weight and reps to beat",
                    isOn: autoProgressionBinding
                )

                Divider().overlay(AppColor.glassBorder)

                PlateInventoryRow(unit: unit, available: platesBinding)

                Divider().overlay(AppColor.glassBorder)

                BarWeightsRow(unit: unit, weight: barWeightBinding)
            }
        }
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

/// Rest applied after a completed set when neither the routine nor the
/// exercise sets its own.
private struct RestTimerRow: View {
    @Binding var selection: Int

    private static let choices = [30, 60, 90, 120, 180, 240]

    var body: some View {
        SettingsPickerRow(
            icon: "timer",
            title: "Default rest timer",
            subtitle: "\(Self.label(for: selection)) between sets"
        ) {
            // Six segments fit a phone at default sizes; at large Dynamic
            // Type or on a narrow screen they'd truncate, so fall back to a menu.
            ViewThatFits(in: .horizontal) {
                GlassSegmentedControl(
                    options: Self.choices,
                    selected: $selection,
                    label: { LocalizedStringKey(Self.label(for: $0)) }
                )
                Picker("Default rest timer", selection: $selection) {
                    ForEach(Self.choices, id: \.self) { seconds in
                        Text(Self.label(for: seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    /// "0:30", "1:30", "4:00" — the same m:ss shape the rest timer counts
    /// down in, and short enough for six segments on a phone.
    private static func label(for seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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
            subtitle: "The plate calculator and barbell jumps use these"
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Spacing.xs)], alignment: .leading, spacing: Spacing.xs) {
                ForEach(PlateCalculatorEngine.defaultPlates(for: unit), id: \.self) { plate in
                    GlassChip(
                        "\(plate.formatted(.number.precision(.fractionLength(0...2)))) \(unit.weightSuffix)",
                        isSelected: available.contains(plate)
                    ) {
                        toggle(plate)
                    }
                }
            }
        }
    }

    private func toggle(_ plate: Double) {
        if available.contains(plate) {
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
            subtitle: "What each empty bar weighs at your gym"
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
