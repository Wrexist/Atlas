import XCTest
@testable import Peptide

final class ProgressionAdjustmentTests: XCTestCase {

    private func adjusted(
        _ kg: Double, reps: Int, _ adjustment: ProgressionEngine.Adjustment, step: Double = 2.5
    ) -> ProgressionEngine.Suggestion {
        ProgressionEngine.adjusted(
            .init(weightKg: kg, reps: reps, reason: .addWeight), for: adjustment, incrementKg: step
        )
    }

    // MARK: - Low recovery

    func test_lowRecovery_dropsLoadTenPercentAndKeepsReps() {
        XCTAssertEqual(adjusted(100, reps: 8, .lowRecovery),
                       .init(weightKg: 90, reps: 8, reason: .addWeight, adjustment: .lowRecovery))
    }

    func test_lowRecovery_roundsToTheNearestStep() {
        XCTAssertEqual(adjusted(80, reps: 8, .lowRecovery).weightKg, 72.5, accuracy: 0.001)   // 72 → 72.5
    }

    func test_lowRecovery_imperialLandsOnFivePoundSteps() {
        let step = MeasurementUnit.imperial.kilograms(fromDisplayed: 5)
        let weight = adjusted(MeasurementUnit.imperial.kilograms(fromDisplayed: 135), reps: 5, .lowRecovery, step: step).weightKg
        XCTAssertEqual(weight, MeasurementUnit.imperial.kilograms(fromDisplayed: 120), accuracy: 0.001)
    }

    func test_lightLoad_stepsDownAtLeastOneIncrement() {
        XCTAssertEqual(adjusted(4, reps: 12, .lowRecovery, step: 2).weightKg, 2)
    }

    func test_lightestLoad_neverDropsToZero() {
        XCTAssertEqual(adjusted(2, reps: 12, .lowRecovery, step: 2).weightKg, 2)
    }

    func test_bodyweight_keepsItsLoadAndReps() {
        XCTAssertEqual(adjusted(0, reps: 10, .lowRecovery, step: 0),
                       .init(weightKg: 0, reps: 10, reason: .addWeight, adjustment: .lowRecovery))
    }

    // MARK: - Deload

    func test_deload_cutsVolumeToAboutSixtyPercent() {
        let suggestion = adjusted(100, reps: 9, .deload)
        XCTAssertEqual(suggestion.weightKg, 90)
        XCTAssertEqual(suggestion.reps, 6)
        let ratio = suggestion.weightKg * Double(suggestion.reps) / (100 * 9)
        XCTAssertEqual(ratio, 0.6, accuracy: 0.05)
    }

    func test_deload_keepsAtLeastOneRep() {
        XCTAssertEqual(adjusted(100, reps: 1, .deload).reps, 1)
    }

    func test_adjustedSuggestion_fillsOnlyPendingSets() {
        let logged = SetEntry(index: 1, weightKg: 100, reps: 8, completed: true)
        let pending = SetEntry(index: 2, weightKg: 100, reps: 8)
        let applied = ProgressionEngine.apply(adjusted(100, reps: 8, .lowRecovery), to: [logged, pending])
        XCTAssertEqual(applied[0], logged, "Logged sets keep what was lifted")
        XCTAssertEqual(applied[1].weightKg, 90)
    }
}
