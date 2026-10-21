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
    }

    /// Abductors are the gluteus medius/minimus, so they collapse to `.glutes`
    /// rather than `.legs` — `AnatomicalMuscle.fromRaw` already maps them that
    /// way and the two have to agree (audit Train M5). This test still
    /// expected `.legs` from before that change.
    func test_muscleGroup_fromRaw_collapsesGluteMuscles() {
        XCTAssertEqual(MuscleGroup.fromRaw("glutes"),    .glutes)
        XCTAssertEqual(MuscleGroup.fromRaw("abductors"), .glutes)
    }

    func test_muscleGroup_fromRaw_isCaseInsensitive() {
        XCTAssertEqual(MuscleGroup.fromRaw("Chest"), .chest)
        XCTAssertEqual(MuscleGroup.fromRaw("LATS"),  .back)
    }

    func test_muscleGroup_fromRaw_unknownStringIsNil() {
        XCTAssertNil(MuscleGroup.fromRaw("widgets"))
    }

    // MARK: - Exercise.muscleGroup

    private func lift(
        primary: [String],
        secondary: [String],
        category: Exercise.Category = .strength
    ) -> Exercise {
        Exercise(
            id: "test_lift",
            name: "Lift",
            force: .pull,
            level: .intermediate,
            mechanic: .compound,
            equipment: "barbell",
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            instructions: [],
            category: category,
            images: []
        )
    }

    func test_exercise_muscleGroup_spanningFiveGroups_isFullBody() {
        // Clean and Press's tags.
        let exercise = lift(
            primary: ["shoulders"],
            secondary: ["abdominals", "calves", "glutes", "hamstrings", "lower back",
                        "middle back", "quadriceps", "traps", "triceps"]
        )
        XCTAssertEqual(exercise.muscleGroup, .fullBody)
    }

    func test_exercise_muscleGroup_squatWithManySecondaries_isLegs() {
        let squat = lift(primary: ["quadriceps"],
                         secondary: ["calves", "glutes", "hamstrings", "lower back"])
        XCTAssertEqual(squat.muscleGroup, .legs)
    }

    func test_exercise_muscleGroup_barbellRowWithManySecondaries_isBack() {
        let row = lift(primary: ["middle back"],
                       secondary: ["biceps", "lats", "shoulders"])
        XCTAssertEqual(row.muscleGroup, .back)
    }

    func test_exercise_muscleGroup_olympicLiftSpanningFiveGroups_isFullBody() {
        let clean = lift(
            primary: ["hamstrings"],
            secondary: ["abdominals", "calves", "forearms", "glutes", "lower back", "traps"],
            category: .olympicWeightlifting
        )
        XCTAssertEqual(clean.muscleGroup, .fullBody)
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

    func test_equipmentKind_fromRaw_mapsDatasetStrings() {
        XCTAssertEqual(EquipmentKind.fromRaw("barbell"),       .barbell)
        XCTAssertEqual(EquipmentKind.fromRaw("e-z curl bar"),  .ezBar)
        XCTAssertEqual(EquipmentKind.fromRaw("kettlebells"),   .kettlebell)
        XCTAssertEqual(EquipmentKind.fromRaw("foam roll"),     .foamRoller)
        XCTAssertEqual(EquipmentKind.fromRaw("medicine ball"), .medicineBall)
        XCTAssertEqual(EquipmentKind.fromRaw("exercise ball"), .swissBall)
    }

    func test_equipmentKind_fromRaw_roundTripsEveryRawValue() {
        // Custom exercises store `rawValue`; it has to read back as itself.
        for kind in EquipmentKind.allCases {
            XCTAssertEqual(EquipmentKind.fromRaw(kind.rawValue), kind, "\(kind)")
        }
    }

    func test_equipmentKind_rawValues_ofPersistedCasesAreStable() {
        let persisted: [EquipmentKind] = [.barbell, .dumbbell, .kettlebell, .cable, .machine, .smith, .band, .bodyweight, .other]
        XCTAssertEqual(persisted.map(\.rawValue),
                       ["barbell", "dumbbell", "kettlebell", "cable", "machine", "smith", "band", "bodyweight", "other"])
    }

    func test_equipmentKind_fromRaw_mapsBodyweightSynonyms() {
        XCTAssertEqual(EquipmentKind.fromRaw("body only"), .bodyweight)
        XCTAssertEqual(EquipmentKind.fromRaw("none"),      .bodyweight)
        XCTAssertEqual(EquipmentKind.fromRaw(nil),         .bodyweight)
        XCTAssertEqual(EquipmentKind.fromRaw(""),          .bodyweight)
    }

    func test_equipmentKind_fromRaw_unknownIsOther() {
        XCTAssertEqual(EquipmentKind.fromRaw("other"),     .other)
        XCTAssertEqual(EquipmentKind.fromRaw("tire"),      .other)
    }

    func test_equipmentKind_fromRaw_isCaseInsensitive() {
        XCTAssertEqual(EquipmentKind.fromRaw("BARBELL"),  .barbell)
        XCTAssertEqual(EquipmentKind.fromRaw("Dumbbell"), .dumbbell)
    }
}
