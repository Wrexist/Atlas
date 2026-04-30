import XCTest
@testable import Peptide

final class PeptideDoseCalculatorTests: XCTestCase {

    // MARK: - Fixtures

    private func peptide(_ abbrev: String, range: String = "PUBLISHED-RANGE") -> Peptide {
        Peptide(
            name: abbrev,
            abbreviation: abbrev,
            category: .recovery,
            description: "",
            benefits: [],
            dosageRange: range,
            frequency: "Daily",
            halfLife: "Unknown",
            adminRoute: "Subcutaneous",
            researchLinks: [],
            imageSystemName: "flask"
        )
    }

    private func metrics(weightKg: Double?) -> BodyMetrics {
        BodyMetrics(
            weightKg: weightKg,
            heightCm: nil,
            age: nil,
            sex: .unspecified,
            activityLevel: .moderate,
            unit: .metric
        )
    }

    // MARK: - Fallback when no weight is available

    func test_dose_returnsPublishedRange_whenWeightMissing() {
        let result = PeptideDoseCalculator.dose(
            for: peptide("BPC-157", range: "250-500 mcg"),
            metrics: metrics(weightKg: nil)
        )
        XCTAssertEqual(result, "250-500 mcg")
    }

    func test_dose_returnsPublishedRange_whenWeightOutOfBounds() {
        let lowResult = PeptideDoseCalculator.dose(
            for: peptide("BPC-157", range: "250-500 mcg"),
            metrics: metrics(weightKg: 10) // implausibly low
        )
        let highResult = PeptideDoseCalculator.dose(
            for: peptide("BPC-157", range: "250-500 mcg"),
            metrics: metrics(weightKg: 500) // implausibly high
        )
        XCTAssertEqual(lowResult, "250-500 mcg")
        XCTAssertEqual(highResult, "250-500 mcg")
    }

    func test_dose_returnsPublishedRange_whenPeptideNotInTable() {
        let result = PeptideDoseCalculator.dose(
            for: peptide("Unknown", range: "5 mg twice weekly"),
            metrics: metrics(weightKg: 80)
        )
        XCTAssertEqual(result, "5 mg twice weekly")
    }

    // MARK: - Per-kg scaling

    func test_dose_scalesBPC157ByWeight() {
        // 2.5–5.0 mcg/kg × 80 kg = 200–400 mcg
        let result = PeptideDoseCalculator.dose(
            for: peptide("BPC-157"),
            metrics: metrics(weightKg: 80)
        )
        XCTAssertEqual(result, "200–400 mcg")
    }

    func test_dose_scalesTesamorelinAndCrossesMgThreshold() {
        // 14–28 mcg/kg × 80 kg = 1120–2240 mcg → expressed in mg
        let result = PeptideDoseCalculator.dose(
            for: peptide("Tesamorelin"),
            metrics: metrics(weightKg: 80)
        )
        XCTAssertEqual(result, "1.12–2.24 mg")
    }

    func test_dose_scalesIpamorelinAtLowWeight() {
        // 1–3 mcg/kg × 50 kg = 50–150 mcg
        let result = PeptideDoseCalculator.dose(
            for: peptide("Ipamorelin"),
            metrics: metrics(weightKg: 50)
        )
        XCTAssertEqual(result, "50–150 mcg")
    }

    // MARK: - Personalization flag

    func test_isPersonalized_trueWhenWeightAndPeptideMatch() {
        XCTAssertTrue(PeptideDoseCalculator.isPersonalized(
            peptide("BPC-157"),
            metrics: metrics(weightKg: 80)
        ))
    }

    func test_isPersonalized_falseWithoutWeight() {
        XCTAssertFalse(PeptideDoseCalculator.isPersonalized(
            peptide("BPC-157"),
            metrics: metrics(weightKg: nil)
        ))
    }

    func test_isPersonalized_falseForUnknownPeptide() {
        XCTAssertFalse(PeptideDoseCalculator.isPersonalized(
            peptide("MysteryX"),
            metrics: metrics(weightKg: 80)
        ))
    }

    // MARK: - Non-daily peptides intentionally excluded

    func test_dose_doesNotPersonalizeNonDailyPeptides() {
        // TB-500 is dosed weekly, must fall back to its published range so
        // the UI doesn't paint a misleading "per day" frame around it.
        for abbrev in ["TB-500", "CJC-1295 DAC", "Epitalon", "DSIP"] {
            let p = peptide(abbrev, range: "FALLBACK")
            XCTAssertEqual(
                PeptideDoseCalculator.dose(for: p, metrics: metrics(weightKg: 80)),
                "FALLBACK",
                "\(abbrev) should not be weight-personalized"
            )
            XCTAssertFalse(
                PeptideDoseCalculator.isPersonalized(p, metrics: metrics(weightKg: 80)),
                "\(abbrev) should report as not personalized"
            )
        }
    }
}
