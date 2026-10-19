import XCTest
@testable import Peptide

@MainActor
final class MuscleInvolvementEngineTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(ExerciseLibrary.shared.lookup(id: id))
    }

    func test_benchPress_listsPrimeMoverFirstThenSupportingByShare() throws {
        let rows = MuscleInvolvementEngine.rows(for: try exercise("Barbell_Bench_Press_-_Medium_Grip"))

        XCTAssertEqual(rows.first?.name, "Chest")
        XCTAssertEqual(rows.first?.role, .primary)
        XCTAssertEqual(rows.first?.share, 1.0)
        let supporting = rows.dropFirst()
        XCTAssertTrue(supporting.allSatisfy { $0.role == .supporting })
        XCTAssertEqual(supporting.map(\.share), supporting.map(\.share).sorted(by: >))
        XCTAssertTrue(supporting.contains { $0.name == "Triceps" })
    }

    func test_supportingMuscle_getsHalfTheStimulusOfAPrimeMover() throws {
        let rows = MuscleInvolvementEngine.rows(for: try exercise("Dumbbell_Bicep_Curl"))

        XCTAssertEqual(rows.map(\.name), ["Biceps", "Forearms"])
        XCTAssertEqual(rows.last?.share, MuscleInvolvementEngine.supportingWeight)
        XCTAssertEqual(rows.last?.muscles, [.forearmFront, .forearmBack])
    }

    func test_rows_onlyNameMusclesTheMapLights() throws {
        let squat = try exercise("Barbell_Full_Squat")
        let lit = Set(MuscleMapView.highlights(for: squat).keys)
        let listed = Set(MuscleInvolvementEngine.rows(for: squat).flatMap(\.muscles))
        XCTAssertEqual(listed, lit)
    }

    func test_revealStages_lightPrimariesBeforeTheFullPicture() {
        let full: [AnatomicalMuscle: MuscleHighlight] = [.pecSternal: .primary, .tricepsLong: .secondary]
        XCTAssertEqual(MuscleInvolvementEngine.revealStages(for: full),
                       [[.pecSternal: .primary], full])
    }

    func test_revealStages_collapseToOneFrameWhenNothingToStage() {
        let primariesOnly: [AnatomicalMuscle: MuscleHighlight] = [.biceps: .primary]
        let supportingOnly: [AnatomicalMuscle: MuscleHighlight] = [.biceps: .secondary]
        XCTAssertEqual(MuscleInvolvementEngine.revealStages(for: primariesOnly), [primariesOnly])
        XCTAssertEqual(MuscleInvolvementEngine.revealStages(for: supportingOnly), [supportingOnly])
        XCTAssertEqual(MuscleInvolvementEngine.revealStages(for: [:]), [[:]])
    }

    func test_focus_keepsOnlyTheRegionAndItsTiers() {
        let full: [AnatomicalMuscle: MuscleHighlight] = [
            .tricepsLong: .secondary, .tricepsLateral: .primary, .pecSternal: .primary
        ]
        let row = MuscleInvolvementEngine.Row(name: "Triceps", role: .primary, share: 1,
                                              muscles: [.tricepsLong, .tricepsLateral])
        XCTAssertEqual(MuscleInvolvementEngine.focus(full, on: row),
                       [.tricepsLong: .secondary, .tricepsLateral: .primary])
    }

    func test_bodyPickerGroup_agreesWithLibraryFilterForEveryRawMuscle() {
        let raws = ["chest", "shoulders", "triceps", "biceps", "forearms", "abdominals", "neck",
                    "lats", "middle back", "lower back", "traps", "quadriceps", "hamstrings",
                    "calves", "adductors", "glutes", "abductors"]
        for raw in raws {
            guard let expected = MuscleGroup.fromRaw(raw) else { continue }
            for head in AnatomicalMuscle.regions(forRawMuscle: raw) {
                XCTAssertEqual(MuscleInvolvementEngine.group(for: head), expected, "\(raw) → \(head)")
            }
        }
    }

    func test_everyPickableGroup_lightsAtLeastOneMuscle() {
        for group in [MuscleGroup.chest, .back, .shoulders, .arms, .legs, .glutes, .core] {
            XCTAssertFalse(MuscleInvolvementEngine.muscles(in: group).isEmpty, group.displayName)
        }
    }
}
