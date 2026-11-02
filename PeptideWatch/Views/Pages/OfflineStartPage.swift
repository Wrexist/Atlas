import SwiftUI

/// The Workout page while the phone is out of reach and runs no workout:
/// one of the user's routines, or a quick workout, started on the wrist.
/// What is logged here joins the phone's history once it is back in reach.
struct OfflineStartPage: View {
    @EnvironmentObject private var store: WatchStore

    private var catalog: WatchTrainingCatalog? {
        store.watchData.trainingCatalog.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                    .entrance(0)
                if let catalog {
                    ForEach(Array(catalog.routines.enumerated()), id: \.element.id) { index, routine in
                        RoutineButton(routine: routine)
                            .entrance(min(index + 1, 4))
                    }
                    Button {
                        store.startOfflineWorkout(nil)
                    } label: {
                        Label("Quick workout", systemImage: "bolt.fill")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchPalette.training)
                    .entrance(min(catalog.routines.count + 1, 5))
                } else {
                    Text("Open Atlas on your iPhone once to bring your routines here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .entrance(1)
                }
                if !store.offlineOutbox.isEmpty {
                    Label("Waiting to sync: \(store.offlineOutbox.count)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(WatchMotion.update, value: store.offlineOutbox.count)
                        .padding(.top, 2)
                }
            }
        }
        .navigationTitle("Workout")
        .pageBackground(WatchPalette.training)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundStyle(WatchPalette.training)
            Text("iPhone out of reach")
                .font(.system(.headline, design: .rounded))
            Text("Log here. It syncs when your iPhone is back.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One routine, started with a tap.
private struct RoutineButton: View {
    @EnvironmentObject private var store: WatchStore
    let routine: WatchRoutine

    var body: some View {
        Button {
            store.startOfflineWorkout(routine)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(routine.name)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("\(routine.lifts.count) exercises")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.training)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(routine.lifts.isEmpty)
        .accessibilityHint("Starts this routine on your watch")
    }
}

/// The lifts the Watch knows, for adding one to a workout it runs itself.
struct OfflineLiftPicker: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let unit = WatchWeightUnit(store.watchData.measurementUnit)
        List(store.watchData.trainingCatalog?.allLifts ?? [], id: \.exerciseID) { lift in
            Button {
                store.addOfflineLift(lift)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lift.name)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(2)
                    Text("\(lift.sets) × \(lift.reps) · \(unit.format(lift.weightKg)) \(unit.symbol)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add exercise")
    }
}
