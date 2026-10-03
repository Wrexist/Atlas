import XCTest
import UIKit
@testable import Peptide

@MainActor
final class ExerciseVisualAssetsTests: XCTestCase {
    func test_bodyMapAssetsCoverEveryRegionWithAlignedCanvas() throws {
        XCTAssertTrue(TrainingAnatomy.isAvailable)
        XCTAssertEqual(Set(TrainingAnatomy.regions.keys), Set(AnatomicalMuscle.allCases.map(\.rawValue)))
        let front = try XCTUnwrap(UIImage(named: TrainingAnatomy.front))
        let back = try XCTUnwrap(UIImage(named: TrainingAnatomy.back))
        XCTAssertEqual(front.size, back.size)
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 1536)
        for muscle in AnatomicalMuscle.allCases {
            let path = TrainingAnatomy.path(for: muscle, in: rect)
            XCTAssertFalse(path.isEmpty, muscle.rawValue)
            XCTAssertTrue(rect.contains(path.boundingRect), muscle.rawValue)
            XCTAssertEqual(path.boundingRect.midX, rect.midX, accuracy: 0.01)
        }
    }

    func test_manifestCoversEntireCatalogWithoutDuplicateIDs() async {
        await ExerciseLibrary.shared.load()
        let records = ExerciseVisualAssets.records
        XCTAssertFalse(records.isEmpty)
        XCTAssertEqual(Set(records.map(\.id)), Set(ExerciseLibrary.shared.bundled.map(\.id)))
        XCTAssertEqual(records.count, Set(records.map(\.id)).count)
    }

    func test_everyPublishedPosterExistsAndHasUniqueIdentity() {
        let illustrated = ExerciseVisualAssets.records.filter { $0.status == "illustrated" }
        XCTAssertFalse(illustrated.isEmpty)
        XCTAssertEqual(illustrated.count, Set(illustrated.compactMap(\.asset)).count)
        for record in illustrated {
            guard let name = record.asset else {
                XCTFail("Missing asset for \(record.id)")
                continue
            }
            XCTAssertNotNil(UIImage(named: name), "Unbundled art: \(record.id)")
            XCTAssertEqual(ExerciseVisualAssets.poster(for: record.id), name)
        }
    }

    func test_unillustratedAndCustomExercisesNeverBorrowAnotherPose() {
        for record in ExerciseVisualAssets.records where record.status == "muscleMap" {
            XCTAssertNil(record.asset)
            XCTAssertNil(ExerciseVisualAssets.poster(for: record.id))
        }
        XCTAssertNil(ExerciseVisualAssets.poster(for: "custom_Incline_Dumbbell_Press"))
        XCTAssertNil(ExerciseVisualAssets.poster(for: "Unknown_Exercise"))
    }
}
