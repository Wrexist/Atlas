import SwiftUI

/// The choices for what an Apple Health workout is shown as: common types
/// first, the rest one level down, and a way back to Health's own type
/// once the user has picked one. Used as a `Menu` or `contextMenu` body.
struct WorkoutTypeMenuItems: View {
    let current: CardioActivity
    let isOverridden: Bool
    let onPick: (CardioActivity?) -> Void

    private var selection: Binding<CardioActivity> {
        Binding(get: { current }, set: { onPick($0) })
    }

    var body: some View {
        Picker("Workout type", selection: selection) {
            ForEach(CardioWorkoutEngine.suggestedTypes, id: \.self) { option($0) }
        }
        Menu("More types") {
            Picker("Workout type", selection: selection) {
                ForEach(CardioWorkoutEngine.moreTypes(), id: \.self) { option($0) }
            }
        }
        if isOverridden {
            Button("Use Apple Health's type", systemImage: "arrow.uturn.backward") {
                onPick(nil)
            }
        }
    }

    private func option(_ activity: CardioActivity) -> some View {
        Label(activity.name, systemImage: activity.symbol).tag(activity)
    }
}
