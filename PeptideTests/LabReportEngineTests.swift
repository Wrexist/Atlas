import XCTest
@testable import Peptide

/// Lab-report scan → catalog: decoding the route's answer, matching
/// printed names onto `LabPanel`, unit conversion, and the review rows.
final class LabReportEngineTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func marker(_ name: String, _ value: Double?, _ unit: String, date: String? = nil) -> LabReportEngine.Marker {
        LabReportEngine.Marker(
            name: name, value: value, unit: unit,
            referenceLow: nil, referenceHigh: nil, referenceText: nil, collectedOn: date
        )
    }

    // MARK: - Decoding

    func test_decode_readsEnvelopeAndSnakeCaseFields() throws {
        let json = """
        {"result":{"is_lab_report":true,"collected_on":"2026-09-14","lab_name":"Unilabs",
          "markers":[{"name":"P-Glukos","value":5.4,"unit":"mmol/L","reference_low":4.0,
                      "reference_high":6.0,"reference_text":"4.0–6.0","collected_on":null},
                     {"name":"U-Glukos","value":null,"unit":"","reference_low":null,
                      "reference_high":null,"reference_text":"Negativ","collected_on":null}]},
         "model":"claude-opus-5-5"}
        """
        let scan = try LabReportEngine.decode(Data(json.utf8))

        XCTAssertTrue(scan.isLabReport)
        XCTAssertEqual(scan.collectedOn, "2026-09-14")
        XCTAssertEqual(scan.labName, "Unilabs")
        XCTAssertEqual(scan.markers.count, 2)
        XCTAssertEqual(scan.markers[0].value, 5.4)
        XCTAssertEqual(scan.markers[0].referenceHigh, 6.0)
        XCTAssertEqual(scan.markers[0].referenceText, "4.0–6.0")
        XCTAssertNil(scan.markers[1].value)
    }

    func test_decode_missingMarkers_throws() {
        let json = #"{"result":{"is_lab_report":true,"collected_on":null,"lab_name":null}}"#
        XCTAssertThrowsError(try LabReportEngine.decode(Data(json.utf8)))
    }

    func test_decode_errorBody_throws() {
        XCTAssertThrowsError(try LabReportEngine.decode(Data(#"{"error":{"message":"Upstream error"}}"#.utf8)))
    }

    // MARK: - Name matching

    func test_panelNamed_matchesWordOrderCasePunctuationAndSpecimenPrefix() {
        XCTAssertEqual(LabReportEngine.panel(named: "Testosterone, Total"), .totalTestosterone)
        XCTAssertEqual(LabReportEngine.panel(named: "TOTAL TESTOSTERONE (serum)"), .totalTestosterone)
        XCTAssertEqual(LabReportEngine.panel(named: "S-Testosteron"), .totalTestosterone)
        XCTAssertEqual(LabReportEngine.panel(named: "fP-Glukos"), .fastingGlucose)
        XCTAssertEqual(LabReportEngine.panel(named: "Glucose, Fasting"), .fastingGlucose)
        XCTAssertEqual(LabReportEngine.panel(named: "S-Östradiol"), .estradiol)
        XCTAssertEqual(LabReportEngine.panel(named: "Vitamin D, 25-Hydroxy"), .vitaminD)
        XCTAssertEqual(LabReportEngine.panel(named: "B-HbA1c"), .hba1c)
        XCTAssertEqual(LabReportEngine.panel(named: "B-EVF"), .hematocrit)
        XCTAssertEqual(LabReportEngine.panel(named: "T4, Free (Direct)"), .freeT4)
        XCTAssertEqual(LabReportEngine.panel(named: "IGF-I"), .igf1)
    }

    func test_panelNamed_freeAndTotalTestosterone_stayDistinct() {
        XCTAssertEqual(LabReportEngine.panel(named: "Testosterone, Free"), .freeTestosterone)
        XCTAssertEqual(LabReportEngine.panel(named: "Testosterone"), .totalTestosterone)
    }

    func test_panelNamed_relatedButDifferentTests_doNotMatch() {
        XCTAssertNil(LabReportEngine.panel(named: "Non-HDL Cholesterol"), "contains HDL, is not HDL")
        XCTAssertNil(LabReportEngine.panel(named: "VLDL Cholesterol"))
        XCTAssertNil(LabReportEngine.panel(named: "Total T3"))
        XCTAssertNil(LabReportEngine.panel(named: "Hemoglobin"))
        XCTAssertNil(LabReportEngine.panel(named: ""))
    }

    func test_synonymTable_hasNoCollisionsBetweenPanels() {
        for (panel, names) in LabReportEngine.synonyms {
            for name in names {
                XCTAssertEqual(LabReportEngine.panel(named: name), panel, "\(name) resolves to another panel")
            }
        }
    }

    func test_synonymTable_coversEveryCatalogPanelExceptOther() {
        let covered = Set(LabReportEngine.synonyms.keys)
        XCTAssertEqual(covered, Set(LabPanel.allCases).subtracting([.other]))
    }

    // MARK: - Unit conversion

    func test_convert_glucoseAndLipids_fromMmolPerLitre() {
        XCTAssertEqual(LabReportEngine.convert(5.4, from: "mmol/L", to: .fastingGlucose)!, 97.29, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(5.0, from: "mmol/l", to: .totalCholesterol)!, 193.35, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(1.3, from: "mmol/L", to: .hdl)!, 50.27, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(1.0, from: "mmol/L", to: .triglycerides)!, 88.57, accuracy: 0.01)
    }

    func test_convert_testosterone_fromNmolPerLitre() {
        XCTAssertEqual(LabReportEngine.convert(20, from: "nmol/L", to: .totalTestosterone)!, 576.84, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(5.0, from: "ng/mL", to: .totalTestosterone)!, 500, accuracy: 0.01)
    }

    func test_convert_hba1c_fromIfccMmolPerMol_isAffine() {
        // 48 mmol/mol is the diagnostic threshold, 6.5 % NGSP.
        XCTAssertEqual(LabReportEngine.convert(48, from: "mmol/mol", to: .hba1c)!, 6.54, accuracy: 0.02)
    }

    func test_convert_swedishKatalUnits_forLiverEnzymes() {
        XCTAssertEqual(LabReportEngine.convert(0.5, from: "µkat/L", to: .alt), 30)
        XCTAssertEqual(LabReportEngine.convert(0.5, from: "ukat/L", to: .ast), 30)
    }

    func test_convert_otherSiUnits() {
        XCTAssertEqual(LabReportEngine.convert(75, from: "nmol/L", to: .vitaminD)!, 30.05, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(88.42, from: "µmol/L", to: .creatinine)!, 1.0, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(15, from: "pmol/L", to: .freeT4)!, 1.17, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(100, from: "pmol/L", to: .estradiol)!, 27.24, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(0.42, from: "L/L", to: .hematocrit)!, 42, accuracy: 0.01)
        XCTAssertEqual(LabReportEngine.convert(400, from: "nmol/L", to: .cortisolMorning)!, 14.5, accuracy: 0.01)
    }

    func test_convert_canonicalUnitSpellings_passThrough() {
        XCTAssertEqual(LabReportEngine.convert(2.1, from: "mIU/L", to: .tsh), 2.1)
        XCTAssertEqual(LabReportEngine.convert(2.1, from: "μIU/mL", to: .tsh), 2.1, "Greek mu")
        XCTAssertEqual(LabReportEngine.convert(2.1, from: "µU/mL", to: .tsh), 2.1, "micro sign")
        XCTAssertEqual(LabReportEngine.convert(4.2, from: "IU/L", to: .lh), 4.2)
        XCTAssertEqual(LabReportEngine.convert(120, from: "mcg/L", to: .ferritin), 120)
        XCTAssertEqual(LabReportEngine.convert(97, from: "MG/DL", to: .fastingGlucose), 97)
    }

    func test_convert_unknownOrWrongUnit_returnsNil() {
        XCTAssertNil(LabReportEngine.convert(5.4, from: "", to: .fastingGlucose))
        XCTAssertNil(LabReportEngine.convert(5.4, from: "g/L", to: .fastingGlucose))
        XCTAssertNil(LabReportEngine.convert(20, from: "mmol/L", to: .totalTestosterone), "a wrong unit is not a guess")
        XCTAssertNil(LabReportEngine.convert(4.2, from: "mIU/L", to: .lh), "1000× off, not equivalent")
        XCTAssertNil(LabReportEngine.convert(1, from: "nmol/L", to: .other))
    }

    func test_convert_negativeOrNonFinite_returnsNil() {
        XCTAssertNil(LabReportEngine.convert(-1, from: "mg/dL", to: .fastingGlucose))
        XCTAssertNil(LabReportEngine.convert(.nan, from: "mg/dL", to: .fastingGlucose))
        XCTAssertNil(LabReportEngine.convert(.infinity, from: "mg/dL", to: .fastingGlucose))
    }

    // MARK: - Dates

    func test_date_parsesIsoDayAtNoon_andRejectsFutureAndImpossible() {
        let today = utc.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9))!
        let parsed = LabReportEngine.date(from: "2026-09-14", notAfter: today, calendar: utc)
        XCTAssertEqual(parsed.map { utc.dateComponents([.year, .month, .day, .hour], from: $0) },
                       DateComponents(year: 2026, month: 9, day: 14, hour: 12))
        XCTAssertNotNil(LabReportEngine.date(from: "2026-10-21", notAfter: today, calendar: utc), "today is allowed")
        XCTAssertNil(LabReportEngine.date(from: "2026-10-22", notAfter: today, calendar: utc))
        XCTAssertNil(LabReportEngine.date(from: "2026-02-31", notAfter: today, calendar: utc))
        XCTAssertNil(LabReportEngine.date(from: "14/09/2026", notAfter: today, calendar: utc))
        XCTAssertNil(LabReportEngine.date(from: nil, notAfter: today, calendar: utc))
    }

    // MARK: - Review rows

    func test_rows_matchConvertAndIncludeOnlyFirstConvertibleRowPerPanel() {
        let today = utc.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let scan = LabReportEngine.Scan(isLabReport: true, collectedOn: "2026-09-14", labName: nil, markers: [
            marker("P-Glukos", 5.4, "mmol/L"),
            marker("Glucose", 99, "mg/dL"),
            marker("Kolesterol", 5.0, "mmol/L", date: "2026-08-01"),
            marker("Ferritin", 80, "furlongs"),
            marker("Apolipoprotein B", 0.9, "g/L"),
            marker("HDL", nil, "mmol/L"),
        ])
        let rows = LabReportEngine.rows(from: scan, today: today, calendar: utc)

        XCTAssertEqual(rows.map(\.panel), [.fastingGlucose, .fastingGlucose, .totalCholesterol, .ferritin, nil, .hdl])
        XCTAssertEqual(rows.map(\.isIncluded), [true, false, true, false, false, false])
        XCTAssertEqual(rows[0].value!, 97.29, accuracy: 0.01)
        XCTAssertNil(rows[3].value, "unknown unit leaves the value for the user")
        XCTAssertNil(rows[4].value)
        XCTAssertNotNil(rows[2].date, "a row's own date is kept")
        XCTAssertNil(rows[0].date, "the report date applies")
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func test_looksLikeUnitSlip_flagsTenfoldOutliersOnly() {
        // A glucose left in mmol/L reads as 5.4 mg/dL — far below the 70 floor.
        XCTAssertTrue(LabReportEngine.looksLikeUnitSlip(5.4, panel: .fastingGlucose, sex: .male))
        XCTAssertFalse(LabReportEngine.looksLikeUnitSlip(97, panel: .fastingGlucose, sex: .male))
        XCTAssertFalse(LabReportEngine.looksLikeUnitSlip(5, panel: .totalTestosterone, sex: .unspecified), "no range, no flag")
    }
}
