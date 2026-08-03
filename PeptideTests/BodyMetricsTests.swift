import XCTest
@testable import Peptide

final class BodyMetricsTests: XCTestCase {

    // MARK: - Defaults

    func test_unspecified_defaultsAreSafe() {
        let m = BodyMetrics.unspecified
        XCTAssertNil(m.weightKg)
        XCTAssertNil(m.heightCm)
        XCTAssertNil(m.age)
        XCTAssertEqual(m.sex, .unspecified)
        XCTAssertEqual(m.activityLevel, .moderate)
        XCTAssertFalse(m.isComplete)
        XCTAssertFalse(m.hasWeight)
        XCTAssertFalse(m.hasHeight)
    }

    func test_isComplete_requiresAllThreePrimaryFields() {
        var m = BodyMetrics.unspecified
        XCTAssertFalse(m.isComplete)

        m.weightKg = 80
        XCTAssertFalse(m.isComplete)

        m.heightCm = 180
        XCTAssertFalse(m.isComplete)

        m.age = 30
        XCTAssertTrue(m.isComplete)
    }

    // MARK: - Codable round-trip

    func test_bodyMetrics_codableRoundTrip() throws {
        let original = BodyMetrics(
            weightKg: 78.5,
            heightCm: 182,
            age: 34,
            sex: .female,
            activityLevel: .athlete,
            unit: .imperial
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BodyMetrics.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - UserProfile backward compatibility

    func test_userProfile_decodesLegacyJSON_withoutBodyMetrics() throws {
        // A user upgrading from a build that pre-dates BodyMetrics has no
        // `bodyMetrics` key in their persisted profile JSON. The decoder
        // must accept that and fall back to `.unspecified` rather than throw.
        let legacyJSON = """
        {
            "name": "Alex",
            "goals": ["Muscle Recovery"],
            "memberSince": "2025-01-01T00:00:00Z",
            "healthConnected": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(UserProfile.self, from: legacyJSON)

        XCTAssertEqual(profile.name, "Alex")
        XCTAssertEqual(profile.goals, ["Muscle Recovery"])
        XCTAssertEqual(profile.bodyMetrics.sex, .unspecified)
        XCTAssertNil(profile.bodyMetrics.weightKg)
    }

    func test_userProfile_codableRoundTrip_preservesBodyMetrics() throws {
        let original = UserProfile(
            name: "Sam",
            goals: ["Better Sleep"],
            memberSince: Date(timeIntervalSince1970: 1_700_000_000),
            healthConnected: true,
            hapticFeedbackEnabled: false,
            doseRemindersEnabled: true,
            biometricLockEnabled: true,
            bodyMetrics: BodyMetrics(
                weightKg: 75,
                heightCm: 175,
                age: 28,
                sex: .male,
                activityLevel: .active,
                unit: .metric
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UserProfile.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.goals, original.goals)
        XCTAssertEqual(decoded.bodyMetrics.weightKg, 75)
        XCTAssertEqual(decoded.bodyMetrics.sex, .male)
        XCTAssertEqual(decoded.bodyMetrics.activityLevel, .active)
        XCTAssertEqual(decoded.bodyMetrics.unit, .metric)
    }

    // MARK: - Locale default

    func test_unspecified_defaultUnit_isSensible() {
        // The locale default is environment-dependent; just make sure it
        // produced one of the valid cases (no crash, no garbage).
        let unit = BodyMetrics.unspecified.unit
        XCTAssertTrue([MeasurementUnit.metric, .imperial].contains(unit))
    }

    // MARK: - Display labels

    func test_biologicalSex_shortLabelFitsCompactChips() {
        // "Skip" must not regress to the long "Prefer not to say" — that's
        // what overflowed the 3-column layout on narrow screens.
        XCTAssertEqual(BiologicalSex.unspecified.shortLabel, "Skip")
        XCTAssertEqual(BiologicalSex.male.shortLabel, "Male")
        XCTAssertEqual(BiologicalSex.female.shortLabel, "Female")
    }

    // MARK: - Weight unit conversion

    func test_metricWeight_passesThroughUnchanged() {
        XCTAssertEqual(MeasurementUnit.metric.weightForDisplay(100), 100, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.metric.kilograms(fromDisplayed: 100), 100, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.metric.weightSuffix, "kg")
    }

    func test_imperialWeight_convertsBothDirections() {
        XCTAssertEqual(MeasurementUnit.imperial.weightForDisplay(100), 220.462, accuracy: 0.001)
        XCTAssertEqual(MeasurementUnit.imperial.kilograms(fromDisplayed: 220.462), 100, accuracy: 0.001)
        XCTAssertEqual(MeasurementUnit.imperial.weightSuffix, "lb")
    }

    func test_weightRoundTrip_survivesTheUnitToggle() {
        // The whole reason weight is persisted in kilograms: a user who
        // logs 225 lb, switches to metric and back must still see 225.
        for unit in [MeasurementUnit.metric, .imperial] {
            for entered in [45.0, 102.5, 225.0, 405.0] {
                let stored = unit.kilograms(fromDisplayed: entered)
                XCTAssertEqual(unit.weightForDisplay(stored), entered, accuracy: 0.0001,
                               "\(entered) did not round-trip through \(unit)")
            }
        }
    }

    func test_weightLabel_roundsAndSuffixesForTheUsersUnit() {
        XCTAssertEqual(MeasurementUnit.metric.weightLabel(1234.6), "1235 kg")
        XCTAssertEqual(MeasurementUnit.imperial.weightLabel(100), "220 lb")
        XCTAssertEqual(MeasurementUnit.metric.weightLabel(60.25, fractionDigits: 1), "60.2 kg")
    }

    // MARK: - Volume (water is stored in fluid ounces)

    func test_imperialVolume_passesOuncesThrough() {
        XCTAssertEqual(MeasurementUnit.imperial.volumeLabel(8), "8 oz")
        XCTAssertEqual(MeasurementUnit.imperial.volumeLabel(100), "100 oz")
        XCTAssertEqual(MeasurementUnit.imperial.volumeValue(32), 32)
        XCTAssertEqual(MeasurementUnit.imperial.volumeSuffix, "oz")
    }

    func test_metricVolume_convertsAndPromotesToLitres() {
        XCTAssertEqual(MeasurementUnit.metric.volumeLabel(8), "237 mL")
        XCTAssertEqual(MeasurementUnit.metric.volumeLabel(17), "503 mL")
        XCTAssertEqual(MeasurementUnit.metric.volumeValue(8), 237)
        XCTAssertEqual(MeasurementUnit.metric.volumeSuffix, "mL")
    }

    func test_metricVolume_promotesPastOneLitre() {
        // The daily target is 100 oz — "2957 mL" is not a number anyone
        // reads, which is the whole reason for the promotion.
        XCTAssertEqual(MeasurementUnit.metric.volumeLabel(34), "1.0 L")
        XCTAssertEqual(MeasurementUnit.metric.volumeLabel(100), "3.0 L")
    }
}
