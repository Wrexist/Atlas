import XCTest
@testable import Peptide

final class MuscleGroupAndEquipmentTests: XCTestCase {

    // MARK: - MuscleGroup.fromRaw

    func test_muscleGroup_fromRaw_collapsesBackMuscles() {
        XCTAssertEqual(MuscleGroup.fromRaw("lats"),         .back)
        XCTAssertEqual(MuscleGroup.fromRaw("middle back"),  .back)
        XCTAssertEqual(MuscleGroup.fromRaw("lower back"),   .back)
        XCTAssertEqual(MuscleGroup.fromRaw("traps"),        .back)
    }

    func test_muscleGroup_fromRaw_collapsesArmMuscles() {
        XCTAssertEqual(MuscleGroup.fromRaw("biceps"),   .arms)
        XCTAssertEqual(MuscleGroup.fromRaw("triceps"),  .arms)
        XCTAssertEqual(MuscleGroup.fromRaw("forearms"), .arms)
    }

    func test_muscleGroup_fromRaw_collapsesLegMuscles() {
        XCTAssertEqual(MuscleGroup.fromRaw("quadriceps"), .legs)
        XCTAssertEqual(MuscleGroup.fromRaw("hamstrings"), .legs)
        XCTAssertEqual(MuscleGroup.fromRaw("calves"),     .legs)
        XCTAssertEqual(MuscleGroup.fromRaw("adductors"),  .legs)
        XCTAssertEqual(MuscleGroup.fromRaw("abductors"),  .legs)
    }

    func test_muscleGroup_fromRaw_isCaseInsensitive() {
        XCTAssertEqual(MuscleGroup.fromRaw("Chest"), .chest)
        XCTAssertEqual(MuscleGroup.fromRaw("LATS"),  .back)
    }

    func test_muscleGroup_fromRaw_unknownStringIsNil() {
        XCTAssertNil(MuscleGroup.fromRaw("widgets"))
    }

    // MARK: - Exercise.muscleGroup

    func test_exercise_muscleGroup_fourPlusMuscles_isFullBody_strength() {
        let exercise = Exercise(
            id: "test_compound",
            name: "Compound",
            force: .pull,
            level: .intermediate,
            mechanic: .compound,
            equipment: "barbell",
            primaryMuscles: ["lats", "lower back", "glutes", "hamstrings"],
            secondaryMuscles: ["traps"],
            instructions: [],
            category: .strength,
            images: []
        )
        XCTAssertEqual(exercise.muscleGroup, .fullBody)
    }

    func test_exercise_muscleGroup_stretching_isCardioMobility() {
        let exercise = Exercise(
            id: "test_stretch",
            name: "Forward Fold",
            force: nil,
            level: .beginner,
            mechanic: nil,
            equipment: nil,
            primaryMuscles: ["hamstrings"],
            secondaryMuscles: [],
            instructions: [],
            category: .stretching,
            images: []
        )
        XCTAssertEqual(exercise.muscleGroup, .cardioMobility,
                       "Stretching should fall under Cardio & Mobility chip")
    }

    func test_exercise_muscleGroup_cardio_isCardioMobility() {
        let exercise = Exercise(
            id: "test_cardio",
            name: "Box Skip",
            force: nil,
            level: .beginner,
            mechanic: nil,
            equipment: "other",
            primaryMuscles: ["quadriceps"],
            secondaryMuscles: [],
            instructions: [],
            category: .cardio,
            images: []
        )
        XCTAssertEqual(exercise.muscleGroup, .cardioMobility)
    }

    func test_exercise_muscleGroup_singleMuscle_resolvesToCollapsed() {
        let exercise = Exercise(
            id: "test_curl",
            name: "Bicep Curl",
            force: .pull,
            level: .beginner,
            mechanic: .isolation,
            equipment: "dumbbell",
            primaryMuscles: ["biceps"],
            secondaryMuscles: ["forearms"],
            instructions: [],
            category: .strength,
            images: []
        )
        XCTAssertEqual(exercise.muscleGroup, .arms)
    }

    // MARK: - EquipmentKind.fromRaw

    func test_equipmentKind_fromRaw_mapsBarbellSynonyms() {
        XCTAssertEqual(EquipmentKind.fromRaw("barbell"),     .barbell)
        XCTAssertEqual(EquipmentKind.fromRaw("e-z curl bar"), .barbell)
    }

    func test_equipmentKind_fromRaw_mapsBodyweightSynonyms() {
        XCTAssertEqual(EquipmentKind.fromRaw("body only"), .bodyweight)
        XCTAssertEqual(EquipmentKind.fromRaw("none"),      .bodyweight)
        XCTAssertEqual(EquipmentKind.fromRaw(nil),         .bodyweight)
        XCTAssertEqual(EquipmentKind.fromRaw(""),          .bodyweight)
    }

    func test_equipmentKind_fromRaw_unknownIsOther() {
        XCTAssertEqual(EquipmentKind.fromRaw("foam roll"),     .other)
        XCTAssertEqual(EquipmentKind.fromRaw("medicine ball"), .other)
    }

    func test_equipmentKind_fromRaw_isCaseInsensitive() {
        XCTAssertEqual(EquipmentKind.fromRaw("BARBELL"),  .barbell)
        XCTAssertEqual(EquipmentKind.fromRaw("Dumbbell"), .dumbbell)
    }
}
