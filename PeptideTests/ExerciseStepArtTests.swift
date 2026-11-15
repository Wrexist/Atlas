import XCTest
@testable import Peptide

@MainActor
final class ExerciseStepArtTests: XCTestCase {

    func test_illustratedExercises_haveThreeStepsEach() async throws {
        await ExerciseLibrary.shared.load()
        let illustrated = [
            "Barbell_Squat", "Dumbbell_Bicep_Curl", "Barbell_Bench_Press_-_Medium_Grip", "Plank",
            "Cable_Crossover", "Dumbbell_Bench_Press", "Dumbbell_Flyes", "Front_Squat_Clean_Grip",
            "Goblet_Squat", "Incline_Dumbbell_Press", "Leg_Extensions", "Front_Dumbbell_Raise",
            "Hyperextensions_Back_Extensions", "Leg_Press", "Pushups", "Seated_Calf_Raise",
            "Side_Lateral_Raise", "Wide-Grip_Lat_Pulldown", "Hammer_Curls", "Preacher_Curl",
            "Pullups", "Seated_Cable_Rows", "Seated_Dumbbell_Press", "Sumo_Deadlift", "Barbell_Curl",
            "Barbell_Shrug", "Concentration_Curls", "Romanian_Deadlift", "Straight-Arm_Pulldown",
            "Triceps_Pushdown_-_Rope_Attachment", "Upright_Barbell_Row",
            "Alternate_Hammer_Curl", "Alternate_Heel_Touchers", "Barbell_Glute_Bridge", "Bench_Dips",
            "Close-Grip_Barbell_Bench_Press", "Machine_Shoulder_Military_Press", "Russian_Twist",
            "Triceps_Pushdown"
        ]
        for id in illustrated {
            XCTAssertNotNil(ExerciseLibrary.shared.lookup(id: id), "\(id) is not in the library")
            XCTAssertEqual(ExerciseStepArt.assetNames(for: id).count, 3, id)
        }
    }

    func test_fullSquat_borrowsTheBackSquatPictures() {
        XCTAssertEqual(
            ExerciseStepArt.assetNames(for: "Barbell_Full_Squat"),
            ExerciseStepArt.assetNames(for: "Barbell_Squat")
        )
    }

    func test_exerciseWithoutPictures_returnsNone() {
        XCTAssertTrue(ExerciseStepArt.assetNames(for: "Arm_Circles").isEmpty)
    }
}
