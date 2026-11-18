import XCTest
@testable import Peptide

/// Profile and Customize profile must show the same body metrics and a
/// membership length in the reader's language.
@MainActor
final class ProfileDisplayFormattingTests: XCTestCase {

    private func calendar(locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    private func metrics(heightCm: Double?, weightKg: Double? = nil, unit: MeasurementUnit = .metric) -> BodyMetrics {
        BodyMetrics(weightKg: weightKg, heightCm: heightCm, age: nil, sex: .male, activityLevel: .moderate, unit: unit)
    }

    func test_heightLabel_metricHalfCentimetre_keepsTheDecimal() {
        XCTAssertEqual(metrics(heightCm: 180.5).heightLabel?.hasPrefix("180"), true)
        XCTAssertNotEqual(metrics(heightCm: 180.5).heightLabel, "181 cm")
    }

    func test_heightLabel_imperial_neverReadsTwelveInches() {
        // 182.8 cm = 71.97 in, which rounds to 6'0" rather than 5'12".
        XCTAssertEqual(metrics(heightCm: 182.8, unit: .imperial).heightLabel, "6'0\"")
    }

    func test_heightLabel_missingHeight_isNil() {
        XCTAssertNil(metrics(heightCm: nil).heightLabel)
    }

    func test_memberDurationLabel_swedish_isNotTheEnglishAbbreviation() throws {
        let sv = calendar(locale: "sv_SE")
        let start = try XCTUnwrap(sv.date(from: DateComponents(year: 2026, month: 1, day: 10)))
        let now = try XCTUnwrap(sv.date(from: DateComponents(year: 2026, month: 4, day: 12)))

        let label = ProfileCustomizationSheet.memberDurationLabel(since: start, now: now, calendar: sv)

        XCTAssertTrue(label.hasPrefix("3"), label)
        XCTAssertFalse(label.hasSuffix("mo"), label)
    }

    func test_memberDurationLabel_startAfterNow_neverGoesNegative() throws {
        let en = calendar(locale: "en_US")
        let now = try XCTUnwrap(en.date(from: DateComponents(year: 2026, month: 4, day: 12)))

        let label = ProfileCustomizationSheet.memberDurationLabel(since: now.addingTimeInterval(86_400), now: now, calendar: en)

        XCTAssertFalse(label.contains("-"), label)
    }
}
