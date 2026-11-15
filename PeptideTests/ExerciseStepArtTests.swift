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
            "Pullups", "Seated_Cable_Rows", "Seated_Dumbbell_Press", "Sumo_Deadlift"
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
