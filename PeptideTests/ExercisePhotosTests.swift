import XCTest
@testable import Peptide

final class ExercisePhotosTests: XCTestCase {
    func test_everyCatalogExercise_hasStartAndFinishPhotos() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "exercises", withExtension: "json"))
        let ids = try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url)).map(\.id)
        let missing = ids.filter { ExercisePhotos.pair(for: $0) == nil }
        XCTAssertFalse(ids.isEmpty)
        XCTAssertTrue(missing.isEmpty, "Missing photos for \(missing.count) exercises, e.g. \(missing.prefix(5))")
    }

    func test_customExercise_fallsBackToNoPhotos() {
        XCTAssertNil(ExercisePhotos.pair(for: "custom-\(UUID().uuidString)"))
    }

    private struct CatalogEntry: Decodable {
        let id: String
    }
}
