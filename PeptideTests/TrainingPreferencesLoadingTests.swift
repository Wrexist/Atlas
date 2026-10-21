import XCTest
@testable import Peptide

/// The plate and bar settings on `TrainingPreferences`: per-unit, with
/// standard defaults, and readable from profiles saved before they existed.
final class TrainingPreferencesLoadingTests: XCTestCase {

    func test_defaults_areTheStandardSetsPerUnit() {
        let prefs = TrainingPreferences()
        XCTAssertEqual(prefs.plates(for: .metric), [25, 20, 15, 10, 5, 2.5, 1.25])
        XCTAssertEqual(prefs.plates(for: .imperial), [45, 35, 25, 10, 5, 2.5])
        XCTAssertEqual(prefs.barWeight(.olympic, unit: .metric), 20)
        XCTAssertEqual(prefs.barWeight(.olympic, unit: .imperial), 45)
        XCTAssertEqual(prefs.barWeight(.ezBar, unit: .metric), 10)
        XCTAssertEqual(prefs.barWeight(.trapBar, unit: .metric), 25)
        XCTAssertEqual(prefs.barWeight(.smith, unit: .metric), 15)
    }

    func test_setBarWeight_changesOnlyThatBarInThatUnit() {
        var prefs = TrainingPreferences()
        prefs.setBarWeight(7.5, for: .smith, unit: .metric)
        XCTAssertEqual(prefs.barWeight(.smith, unit: .metric), 7.5)
        XCTAssertEqual(prefs.barWeight(.smith, unit: .imperial), 35)
        XCTAssertEqual(prefs.barWeight(.olympic, unit: .metric), 20)
    }

    func test_setPlates_keepsTheOtherUnitsSet() {
        var prefs = TrainingPreferences()
        prefs.setPlates([45, 25, 5], for: .imperial)
        XCTAssertEqual(prefs.plates(for: .imperial), [45, 25, 5])
        XCTAssertEqual(prefs.plates(for: .metric), PlateCalculatorEngine.kilogramPlates)
    }

    func test_legacyJSON_withoutLoadingFields_decodesToDefaults() throws {
        let legacy = """
        {"daysPerWeek":4,"preferredDays":["monday"],"timeOfDay":"evening","restTimerDefault":120,
         "plateInventoryKg":[20,10],"autoProgression":true,"equipmentAccess":["barbell","smith"]}
        """
        let prefs = try JSONDecoder().decode(TrainingPreferences.self, from: Data(legacy.utf8))
        XCTAssertEqual(prefs.plates(for: .metric), [20, 10])
        XCTAssertEqual(prefs.plates(for: .imperial), PlateCalculatorEngine.poundPlates)
        XCTAssertEqual(prefs.barWeight(.trapBar, unit: .imperial), 55)
        XCTAssertEqual(prefs.equipmentAccess, [.barbell, .smith])
    }

    func test_loadingSettings_roundTripThroughCodable() throws {
        var prefs = TrainingPreferences()
        prefs.setPlates([45, 10], for: .imperial)
        prefs.setBarWeight(0, for: .smith, unit: .metric)
        let decoded = try JSONDecoder().decode(TrainingPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded, prefs)
        XCTAssertEqual(decoded.barWeight(.smith, unit: .metric), 0)
    }
}
