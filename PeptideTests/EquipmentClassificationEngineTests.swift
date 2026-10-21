import XCTest
@testable import Peptide

/// Equipment for every bundled exercise. The dataset's raw tags are coarse
/// (Smith work is "machine", pull-ups are "other"), so these pin the kinds
/// and extra needs the engine derives from the name as well.
@MainActor
final class EquipmentClassificationEngineTests: XCTestCase {

    private var exercises: [Exercise] { ExerciseLibrary.shared.bundled }

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
    }

    private func exercise(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Exercise {
        try XCTUnwrap(exercises.first { $0.id == id }, "missing \(id)", file: file, line: line)
    }

    private func assertKind(_ id: String, _ kind: EquipmentKind, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try exercise(id, file: file, line: line).equipmentKind, kind, id, file: file, line: line)
    }

    // MARK: - Whole dataset

    func test_everyExercise_getsAKind_andMostAreSpecific() {
        XCTAssertEqual(exercises.count, 873)
        let counts = Dictionary(grouping: exercises, by: \.equipmentKind).mapValues(\.count)
        XCTAssertEqual(counts.values.reduce(0, +), exercises.count)
        // What's left in "other" is strongman kit, sleds, rings and ropes.
        XCTAssertLessThanOrEqual(counts[.other] ?? 0, 50)
        for kind in EquipmentKind.allCases where kind != .other {
            XCTAssertGreaterThan(counts[kind] ?? 0, 0, "no exercise classified as \(kind)")
        }
    }

    func test_everySmithExercise_isSmith_notMachine() {
        let smith = exercises.filter { $0.name.localizedCaseInsensitiveContains("smith") }
        XCTAssertEqual(smith.count, 20)
        for exercise in smith { XCTAssertEqual(exercise.equipmentKind, .smith, exercise.name) }
    }

    func test_everySelfMyofascialRelease_isFoamRoller() {
        let smr = exercises.filter { $0.id.hasSuffix("-SMR") }
        XCTAssertFalse(smr.isEmpty)
        for exercise in smr { XCTAssertEqual(exercise.equipmentKind, .foamRoller, exercise.name) }
    }

    func test_everyRawEZBarTag_isEZBar() {
        for exercise in exercises where exercise.equipment == "e-z curl bar" {
            XCTAssertEqual(exercise.equipmentKind, .ezBar, exercise.name)
        }
    }

    func test_noStretchOrPlyometric_isLeftAsOther() {
        let loose = exercises.filter {
            ($0.category == .stretching || $0.category == .plyometrics) && $0.equipmentKind == .other
        }
        XCTAssertEqual(loose.map(\.id).sorted(), ["Heavy_Bag_Thrust", "Sledgehammer_Swings"])
    }

    // MARK: - Known exercises

    func test_knownBarExercises_mapToTheirBar() throws {
        try assertKind("Smith_Machine_Squat", .smith)
        try assertKind("Decline_Smith_Press", .smith)
        try assertKind("Smith_Incline_Shoulder_Raise", .smith)
        try assertKind("EZ-Bar_Curl", .ezBar)
        try assertKind("Close-Grip_EZ_Bar_Curl", .ezBar)
        try assertKind("Lying_Close-Grip_Barbell_Triceps_Press_To_Chin", .ezBar)
        try assertKind("Trap_Bar_Deadlift", .trapBar)
        try assertKind("Barbell_Squat", .barbell)
        try assertKind("Landmine_180s", .barbell)
    }

    func test_knownLooseKit_mapsToItsOwnKind() throws {
        try assertKind("Medicine_Ball_Chest_Pass", .medicineBall)
        try assertKind("Exercise_Ball_Crunch", .swissBall)
        try assertKind("Quadriceps-SMR", .foamRoller)
        try assertKind("Front_Plate_Raise", .plate)
        try assertKind("Band_Assisted_Pull-Up", .band)
        try assertKind("Leg_Press", .machine)
        try assertKind("Atlas_Stones", .other)
    }

    func test_untaggedHangsAndJumps_areBodyweight() throws {
        try assertKind("Mixed_Grip_Chin", .bodyweight)
        try assertKind("Weighted_Pull_Ups", .bodyweight)
        try assertKind("Box_Jump_Multiple_Response", .bodyweight)
        try assertKind("Hamstring_Stretch", .bodyweight)
    }

    // MARK: - Accessories

    func test_benchAndRackNeeds() throws {
        XCTAssertEqual(try exercise("Barbell_Bench_Press_-_Medium_Grip").equipmentAccessories, [.bench, .rack])
        XCTAssertEqual(try exercise("Barbell_Squat").equipmentAccessories, [.rack])
        XCTAssertEqual(try exercise("Incline_Dumbbell_Press").equipmentAccessories, [.bench])
        XCTAssertEqual(try exercise("Decline_Smith_Press").equipmentAccessories, [.bench])
        XCTAssertEqual(try exercise("Leg_Press").equipmentAccessories, [])
    }

    func test_pullUpBarAndBoxNeeds() throws {
        XCTAssertEqual(try exercise("Pullups").equipmentAccessories, [.pullUpBar])
        XCTAssertEqual(try exercise("Band_Assisted_Pull-Up").equipmentAccessories, [.pullUpBar])
        XCTAssertEqual(try exercise("Box_Jump_Multiple_Response").equipmentAccessories, [.box])
        // "Chin" in a stretch is the chin, not a chin-up.
        XCTAssertEqual(try exercise("Chin_To_Chest_Stretch").equipmentAccessories, [])
        // "Hanging" good morning hangs the bar, not the lifter.
        XCTAssertEqual(try exercise("Hanging_Bar_Good_Morning").equipmentAccessories, [.rack])
    }

    // MARK: - Rules without the dataset

    func test_rawTagWins_whenTheNameNamesNoKit() {
        let kind = EquipmentClassificationEngine.kind(
            id: "custom", name: "Curl", raw: "dumbbell", category: .strength
        )
        XCTAssertEqual(kind, .dumbbell)
    }

    func test_customExercise_storedRawValue_readsBack() {
        let kind = EquipmentClassificationEngine.kind(
            id: UUID().uuidString, name: "My trap bar shrug", raw: EquipmentKind.trapBar.rawValue, category: .strength
        )
        XCTAssertEqual(kind, .trapBar)
    }

    // MARK: - Access

    func test_access_barbellCoversEZBarAndPlates_butNotTrapBar() {
        XCTAssertTrue(EquipmentKind.ezBar.isAvailable(with: [.barbell]))
        XCTAssertTrue(EquipmentKind.plate.isAvailable(with: [.barbell]))
        XCTAssertFalse(EquipmentKind.trapBar.isAvailable(with: [.barbell]))
        XCTAssertTrue(EquipmentKind.smith.isAvailable(with: [.machine]))
        XCTAssertFalse(EquipmentKind.foamRoller.isAvailable(with: [.bodyweight]))
    }

    func test_accessChoices_leaveOutPlateAndOther() {
        XCTAssertFalse(EquipmentKind.accessChoices.contains(.plate))
        XCTAssertFalse(EquipmentKind.accessChoices.contains(.other))
        XCTAssertTrue(EquipmentKind.accessChoices.contains(.smith))
    }

    func test_onlyPlateLoadedKinds_haveABar() {
        let barred = EquipmentKind.allCases.filter { $0.bar != nil }
        XCTAssertEqual(barred, [.barbell, .smith, .ezBar, .trapBar])
    }
}
