import SwiftUI

/// Owned by Train so changing sections doesn't discard the user's place.
@Observable
final class ExerciseBrowsingState {
    var query = "" { didSet { if oldValue != query { visibleExerciseID = nil } } }
    var muscleFilter: MuscleGroup? { didSet { if oldValue != muscleFilter { visibleExerciseID = nil } } }
    var equipmentFilter: EquipmentKind? { didSet { if oldValue != equipmentFilter { visibleExerciseID = nil } } }
    var visibleExerciseID: String?

    func clear() {
        query = ""
        muscleFilter = nil
        equipmentFilter = nil
        visibleExerciseID = nil
    }
}

extension View {
    @ViewBuilder
    func exerciseTransitionSource(id: String, namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
