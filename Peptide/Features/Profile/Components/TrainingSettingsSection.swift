import SwiftUI

/// The settings a training-first user reaches for most — display units and
/// the rest timer's fallback length — surfaced near the top of Profile
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

                Divider().foregroundStyle(AppColor.glassBorder)

                RestTimerRow(selection: restTimerBinding)
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
            Picker("Units", selection: $selection) {
                Text("Metric").tag(MeasurementUnit.metric)
                Text("Imperial").tag(MeasurementUnit.imperial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
            Picker("Default rest timer", selection: $selection) {
                ForEach(Self.choices, id: \.self) { seconds in
                    Text(Self.label(for: seconds)).tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// "0:30", "1:30", "4:00" — the same m:ss shape the rest timer counts
    /// down in, and short enough for six segments on a phone.
    private static func label(for seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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
