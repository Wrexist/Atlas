import Foundation

/// One presentation's ordered picks, independent of search and filters.
struct ExercisePickerSelection {
    private(set) var exercises: [Exercise] = []
    private(set) var committed = false

    mutating func toggle(_ exercise: Exercise) {
        guard !committed else { return }
        if exercises.contains(where: { $0.id == exercise.id }) {
            remove(id: exercise.id)
        } else {
            exercises.append(exercise)
        }
    }

    mutating func remove(id: String) {
        guard !committed else { return }
        exercises.removeAll { $0.id == id }
    }

    mutating func clear() {
        guard !committed else { return }
        exercises = []
    }

    /// Prevents repeated Add taps from invoking the parent's callbacks twice.
    mutating func takeForCommit(adding custom: Exercise? = nil) -> [Exercise] {
        guard !committed else { return [] }
        var result = exercises
        if let custom, !result.contains(where: { $0.id == custom.id }) { result.append(custom) }
        guard !result.isEmpty else { return [] }
        committed = true
        return result
    }
}
