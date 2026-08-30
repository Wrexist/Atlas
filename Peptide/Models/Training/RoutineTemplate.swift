import Foundation

/// A ready-made routine the user can create in one tap from the empty
/// state, so their first workout is seconds away instead of a trip
/// through the builder with 873 exercises and no idea where to start.
///
/// Exercise ids are slugs from the bundled `exercises.json`
/// (yuhonas/free-exercise-db). `RoutineTemplateTests` asserts every one
/// resolves, so a dataset refresh that renames a slug fails CI rather
/// than shipping a routine with blank rows.
struct RoutineTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    /// One line on the chip's detail row — who the routine is for.
    let summary: String
    let symbolName: String
    let slots: [Slot]

    /// An exercise plus its set scheme. Flat on purpose: a template is a
    /// starting point the user edits, not a program with its own rules.
    struct Slot: Sendable {
        let exerciseID: String
        let sets: Int
        let reps: Int
    }

    func makeExercises() -> [RoutineExercise] {
        slots.enumerated().map { index, slot in
            RoutineExercise(
                exerciseID: slot.exerciseID,
                index: index,
                targetSets: slot.sets,
                targetReps: slot.reps
            )
        }
    }

    /// The six starters, ordered easiest-to-commit-to first: a full-body
    /// day works for someone training twice a week, the push/pull/legs
    /// split only pays off at four or more.
    static let starters: [RoutineTemplate] = [
        RoutineTemplate(
            id: "full-body",
            name: "Full body",
            summary: "One session, everything trained",
            symbolName: "figure.strengthtraining.traditional",
            slots: [
                Slot(exerciseID: "Barbell_Squat", sets: 3, reps: 8),
                Slot(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", sets: 3, reps: 8),
                Slot(exerciseID: "Bent_Over_Barbell_Row", sets: 3, reps: 8),
                Slot(exerciseID: "Standing_Military_Press", sets: 3, reps: 10),
                Slot(exerciseID: "Hanging_Leg_Raise", sets: 3, reps: 12),
            ]
        ),
        RoutineTemplate(
            id: "upper-body",
            name: "Upper body",
            summary: "Chest, back, shoulders, arms",
            symbolName: "figure.arms.open",
            slots: [
                Slot(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", sets: 4, reps: 8),
                Slot(exerciseID: "Bent_Over_Barbell_Row", sets: 4, reps: 8),
                Slot(exerciseID: "Standing_Military_Press", sets: 3, reps: 10),
                Slot(exerciseID: "Wide-Grip_Lat_Pulldown", sets: 3, reps: 10),
                Slot(exerciseID: "Barbell_Curl", sets: 3, reps: 12),
                Slot(exerciseID: "Triceps_Pushdown", sets: 3, reps: 12),
            ]
        ),
        RoutineTemplate(
            id: "lower-body",
            name: "Lower body",
            summary: "Quads, hamstrings, glutes, calves",
            symbolName: "figure.strengthtraining.functional",
            slots: [
                Slot(exerciseID: "Barbell_Squat", sets: 4, reps: 8),
                Slot(exerciseID: "Romanian_Deadlift", sets: 3, reps: 10),
                Slot(exerciseID: "Leg_Press", sets: 3, reps: 12),
                Slot(exerciseID: "Lying_Leg_Curls", sets: 3, reps: 12),
                Slot(exerciseID: "Standing_Calf_Raises", sets: 4, reps: 15),
            ]
        ),
        RoutineTemplate(
            id: "push-day",
            name: "Push day",
            summary: "Chest, shoulders, triceps",
            symbolName: "figure.mixed.cardio",
            slots: [
                Slot(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", sets: 4, reps: 8),
                Slot(exerciseID: "Standing_Military_Press", sets: 3, reps: 10),
                Slot(exerciseID: "Incline_Dumbbell_Press", sets: 3, reps: 10),
                Slot(exerciseID: "Side_Lateral_Raise", sets: 3, reps: 15),
                Slot(exerciseID: "Triceps_Pushdown", sets: 3, reps: 12),
            ]
        ),
        RoutineTemplate(
            id: "pull-day",
            name: "Pull day",
            summary: "Back and biceps",
            symbolName: "figure.archery",
            slots: [
                Slot(exerciseID: "Bent_Over_Barbell_Row", sets: 4, reps: 8),
                Slot(exerciseID: "Wide-Grip_Lat_Pulldown", sets: 3, reps: 10),
                Slot(exerciseID: "Seated_Cable_Rows", sets: 3, reps: 10),
                Slot(exerciseID: "Face_Pull", sets: 3, reps: 15),
                Slot(exerciseID: "Barbell_Curl", sets: 3, reps: 12),
            ]
        ),
        RoutineTemplate(
            id: "strong-5x5",
            name: "5×5 strength",
            summary: "Three compounds, heavy, low reps",
            symbolName: "dumbbell.fill",
            slots: [
                Slot(exerciseID: "Barbell_Squat", sets: 5, reps: 5),
                Slot(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", sets: 5, reps: 5),
                Slot(exerciseID: "Bent_Over_Barbell_Row", sets: 5, reps: 5),
            ]
        ),
    ]
}
