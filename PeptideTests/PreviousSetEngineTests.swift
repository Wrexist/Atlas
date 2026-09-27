import XCTest
@testable import Peptide

final class PreviousSetEngineTests: XCTestCase {

    private func set(_ index: Int, _ weightKg: Double, _ reps: Int, warmup: Bool = false) -> SetEntry {
        SetEntry(index: index, weightKg: weightKg, reps: reps, completed: true, isWarmup: warmup)
    }

    func test_hints_pairEachRowWithTheSameSetLastTime() {
        let previous = [set(1, 60, 10), set(2, 70, 8), set(3, 80, 6)]
        let current = [set(1, 0, 0), set(2, 0, 0), set(3, 0, 0)]

        let hints = PreviousSetEngine.hints(for: current, previous: previous)

        XCTAssertEqual(current.map { hints[$0.id]?.weightKg }, [60, 70, 80])
        XCTAssertEqual(current.map { hints[$0.id]?.reps }, [10, 8, 6])
    }

    func test_hints_extraRows_fallBackToTheLastPreviousSet() {
        let previous = [set(1, 60, 10), set(2, 70, 8)]
        let current = [set(1, 0, 0), set(2, 0, 0), set(3, 0, 0), set(4, 0, 0)]

        let hints = PreviousSetEngine.hints(for: current, previous: previous)

        XCTAssertEqual(current.map { hints[$0.id]?.weightKg }, [60, 70, 70, 70])
    }

    func test_hints_warmups_neitherGetAHintNorShiftTheWorkingSets() {
        let previous = [set(1, 20, 10, warmup: true), set(2, 60, 10), set(3, 70, 8)]
        let current = [set(1, 0, 0, warmup: true), set(2, 0, 0, warmup: true), set(3, 0, 0), set(4, 0, 0)]

        let hints = PreviousSetEngine.hints(for: current, previous: previous)

        XCTAssertNil(hints[current[0].id])
        XCTAssertNil(hints[current[1].id])
        XCTAssertEqual(hints[current[2].id]?.weightKg, 60)
        XCTAssertEqual(hints[current[3].id]?.weightKg, 70)
    }

    func test_hints_previousAllWarmups_stillPairsByPosition() {
        let previous = [set(1, 20, 10, warmup: true), set(2, 40, 8, warmup: true)]
        let current = [set(1, 0, 0), set(2, 0, 0)]

        let hints = PreviousSetEngine.hints(for: current, previous: previous)

        XCTAssertEqual(current.map { hints[$0.id]?.weightKg }, [20, 40])
    }

    func test_hints_orderByIndexNotArrayPosition() {
        let previous = [set(2, 70, 8), set(1, 60, 10)]
        let current = [set(2, 0, 0), set(1, 0, 0)]

        let hints = PreviousSetEngine.hints(for: current, previous: previous)

        XCTAssertEqual(hints[current[1].id]?.weightKg, 60, "Set 1 pairs with last time's set 1")
        XCTAssertEqual(hints[current[0].id]?.weightKg, 70)
    }

    func test_hints_noHistory_isEmpty() {
        XCTAssertTrue(PreviousSetEngine.hints(for: [set(1, 0, 0)], previous: []).isEmpty)
    }

    // MARK: - Rest options

    func test_restLabel_readsAsSecondsOrMinutes() {
        XCTAssertEqual(RestTimeOptions.label(for: 30), "30 sec")
        XCTAssertEqual(RestTimeOptions.label(for: 60), "1 min")
        XCTAssertEqual(RestTimeOptions.label(for: 90), "1:30 min")
        XCTAssertEqual(RestTimeOptions.label(for: 240), "4 min")
    }

    func test_restChoices_includeAnOffListCurrentValueInOrder() {
        XCTAssertEqual(RestTimeOptions.choices(including: 75), [30, 60, 75, 90, 120, 180, 240])
        XCTAssertEqual(RestTimeOptions.choices(including: 90), RestTimeOptions.seconds)
        XCTAssertEqual(RestTimeOptions.choices(including: nil), RestTimeOptions.seconds)
    }
}
