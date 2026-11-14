import XCTest
@testable import Peptide

@MainActor
final class ExerciseStepArtTests: XCTestCase {

    func test_illustratedExercises_haveThreeStepsEach() async throws {
        await ExerciseLibrary.shared.load()
        for id in ["Barbell_Squat", "Dumbbell_Bicep_Curl", "Barbell_Bench_Press_-_Medium_Grip", "Plank"] {
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
