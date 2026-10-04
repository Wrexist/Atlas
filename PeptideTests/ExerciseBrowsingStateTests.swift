import XCTest
@testable import Peptide

final class ExerciseBrowsingStateTests: XCTestCase {
    func test_queryChangeClearsOldPositionButIdenticalQueryPreservesIt() {
        let state = ExerciseBrowsingState()
        state.query = "press"
        state.visibleExerciseID = "Incline_Dumbbell_Press"
        state.query = "press"
        XCTAssertEqual(state.visibleExerciseID, "Incline_Dumbbell_Press")
        state.query = "row"
        XCTAssertNil(state.visibleExerciseID)
    }

    func test_clearResetsFiltersAndPositionTogether() {
        let state = ExerciseBrowsingState()
        state.query = "press"
        state.equipmentFilter = .dumbbell
        state.visibleExerciseID = "Incline_Dumbbell_Press"
        state.clear()
        XCTAssertTrue(state.query.isEmpty)
        XCTAssertNil(state.equipmentFilter)
        XCTAssertNil(state.muscleFilter)
        XCTAssertNil(state.visibleExerciseID)
    }
}
