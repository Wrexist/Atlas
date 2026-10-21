import XCTest
@testable import Peptide

@MainActor
final class ExerciseAnatomyEngineTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(ExerciseLibrary.shared.lookup(id: id))
    }

    /// Pixel aspect (width ÷ height) of a unit rect on the 1024 × 1536 artwork.
    private func pixelAspect(_ rect: CGRect) -> Double {
        (rect.width * 1024) / (rect.height * 1536)
    }

    private let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    // MARK: - Highlights

    func test_everyCatalogExercise_marksAtLeastOnePrimaryRegion() {
        let catalog = ExerciseLibrary.shared.bundled
        XCTAssertFalse(catalog.isEmpty)
        let unmarked = catalog.filter { !ExerciseAnatomyEngine.highlights(for: $0).values.contains(.primary) }
        XCTAssertEqual(unmarked.map(\.id), [])
    }

    func test_everyLitRegion_hasDrawableGeometry() {
        for exercise in ExerciseLibrary.shared.bundled {
            for muscle in ExerciseAnatomyEngine.highlights(for: exercise).keys {
                XCTAssertGreaterThanOrEqual(TrainingAnatomy.regions[muscle.rawValue]?.count ?? 0, 3,
                                            "\(exercise.id) → \(muscle)")
            }
        }
    }

    func test_curl_marksBicepsPrimaryAndForearmsSecondary() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Dumbbell_Bicep_Curl"))
        XCTAssertEqual(lit[.biceps], .primary)
        XCTAssertEqual(lit[.forearmFront], .secondary)
        XCTAssertEqual(lit[.forearmBack], .secondary)
    }

    func test_benchPress_marksChestPrimaryAndPressingHelpersSecondary() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Barbell_Bench_Press_-_Medium_Grip"))
        XCTAssertEqual(lit[.pecSternal], .primary)
        XCTAssertEqual(lit[.tricepsLateral], .secondary)
        XCTAssertEqual(lit[.deltAnterior], .secondary)
    }

    func test_shoulderTaggedPressWithoutCue_stillMarksAPrimeMover() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Seated_Dumbbell_Press"))
        XCTAssertEqual(lit[.deltAnterior], .primary)
    }

    func test_customExerciseGroups_lightTheirRegions() {
        for group in MuscleGroup.allCases where group != .cardioMobility {
            let custom = CustomExercise(name: "My lift", primaryMuscles: [group.rawValue]).asExercise()
            let lit = ExerciseAnatomyEngine.highlights(for: custom)
            XCTAssertTrue(lit.values.contains(.primary), group.rawValue)
        }
        let row = CustomExercise(name: "Cable row", primaryMuscles: ["back"], secondaryMuscles: ["arms"]).asExercise()
        let lit = ExerciseAnatomyEngine.highlights(for: row)
        XCTAssertEqual(lit[.lats], .primary)
        XCTAssertEqual(lit[.biceps], .secondary)
    }

    func test_names_deduplicateHeadsAndSplitByTier() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Barbell_Squat"))
        XCTAssertEqual(ExerciseAnatomyEngine.names(in: lit, tier: .primary), ["Quads"])
        let secondary = ExerciseAnatomyEngine.names(in: lit, tier: .secondary)
        XCTAssertEqual(secondary.count, Set(secondary).count)
        XCTAssertTrue(secondary.contains("Hamstrings"))
        XCTAssertFalse(secondary.contains("Quads"))
    }

    // MARK: - Side

    func test_preferredSide_followsWhereTheStimulusIs() throws {
        XCTAssertEqual(ExerciseAnatomyEngine.preferredSide(
            for: ExerciseAnatomyEngine.highlights(for: try exercise("Pullups"))), .back)
        XCTAssertEqual(ExerciseAnatomyEngine.preferredSide(
            for: ExerciseAnatomyEngine.highlights(for: try exercise("Dumbbell_Bicep_Curl"))), .front)
        XCTAssertEqual(ExerciseAnatomyEngine.preferredSide(for: [:]), .front)
    }

    func test_preferredSide_weighsPrimaryAboveSeveralSecondaries() {
        let lit: [AnatomicalMuscle: MuscleHighlight] = [
            .pecSternal: .primary, .tricepsLong: .secondary, .tricepsLateral: .secondary
        ]
        XCTAssertEqual(ExerciseAnatomyEngine.preferredSide(for: lit), .front)
    }

    // MARK: - Crop band

    func test_focusRect_curlZoomsToTheUpperBodyAndLeavesTheLegsOut() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Dumbbell_Bicep_Curl"))
        let rect = ExerciseAnatomyEngine.focusRect(for: lit, side: .front, aspect: 1)
        // Shoulders to hips: the knees (y ≈ 0.63) stay out of the tile.
        XCTAssertGreaterThan(rect.minY, 0.1)
        XCTAssertLessThan(rect.maxY, 0.6)
        XCTAssertEqual(pixelAspect(rect), 1, accuracy: 0.001)
        XCTAssertTrue(unit.contains(rect))
    }

    func test_focusRect_squatZoomsToTheThighs() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Barbell_Squat"))
        let rect = ExerciseAnatomyEngine.focusRect(for: lit, side: .front, aspect: 1)
        XCTAssertGreaterThan(rect.minY, 0.35)
        XCTAssertLessThanOrEqual(rect.minY, 700 / 1536)
        XCTAssertGreaterThanOrEqual(rect.maxY, 980 / 1536)
        XCTAssertTrue(unit.contains(rect))
    }

    func test_focusRect_coversEveryLitRegionOnTheSide() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Barbell_Deadlift"))
        let rect = ExerciseAnatomyEngine.focusRect(for: lit, side: .back, aspect: 0.84)
        for muscle in lit.keys where muscle.isBack {
            for point in TrainingAnatomy.regions[muscle.rawValue] ?? [] {
                XCTAssertTrue(rect.insetBy(dx: -0.001, dy: -0.001)
                    .contains(CGPoint(x: point[0] / 1024, y: point[1] / 1536)), "\(muscle)")
            }
        }
    }

    func test_focusRect_staysInsideTheArtworkForAnyTileShape() throws {
        let lit = ExerciseAnatomyEngine.highlights(for: try exercise("Barbell_Deadlift"))
        for aspect in [0.2, 0.5, 0.84, 1, 2, 5] {
            for side in [ExerciseAnatomyEngine.Side.front, .back] {
                let rect = ExerciseAnatomyEngine.focusRect(for: lit, side: side, aspect: aspect)
                XCTAssertTrue(unit.insetBy(dx: -1e-9, dy: -1e-9).contains(rect), "\(aspect) \(side)")
                XCTAssertGreaterThan(rect.width, 0)
                XCTAssertGreaterThan(rect.height, 0)
            }
        }
    }

    func test_focusRect_enforcesMinimumHeightForASmallRegion() {
        let rect = ExerciseAnatomyEngine.focusRect(for: [.neck: .primary], side: .front, aspect: 1)
        XCTAssertGreaterThanOrEqual(rect.height, 0.2 - 1e-9)
    }

    func test_focusRect_withNothingLitOnTheSide_framesTheTorso() {
        let rect = ExerciseAnatomyEngine.focusRect(for: [:], side: .back, aspect: 1)
        XCTAssertTrue(unit.contains(rect))
        XCTAssertTrue(rect.contains(CGPoint(x: 0.5, y: 0.4)))
    }
}
