import Foundation

/// The pure half of lab-report scanning: decodes the `lab-scan` route's
/// answer, maps each printed test name onto the `LabPanel` catalog, and
/// converts each value into the panel's canonical unit. `LabScanService`
/// does the network half; the review screen edits the rows built here.
///
/// Matching is exact on a normalised name, never a substring: "Non-HDL
/// cholesterol" contains "HDL" and is a different number. A name that
/// isn't in the synonym table is left for the user to match by hand.
enum LabReportEngine {

    // MARK: - Wire format

    /// What the `lab-scan` route returns under `result`.
    struct Scan: Decodable, Equatable, Sendable {
        let isLabReport: Bool
        /// Draw date as printed, `YYYY-MM-DD`.
        let collectedOn: String?
        let labName: String?
        let markers: [Marker]

        enum CodingKeys: String, CodingKey {
            case markers
            case isLabReport = "is_lab_report"
            case collectedOn = "collected_on"
            case labName     = "lab_name"
        }
    }

    /// One result row, transcribed as printed.
    struct Marker: Decodable, Equatable, Sendable {
        let name: String
        /// Nil when the result isn't a number ("Negative").
        let value: Double?
        let unit: String
        let referenceLow: Double?
        let referenceHigh: Double?
        let referenceText: String?
        let collectedOn: String?

        enum CodingKeys: String, CodingKey {
            case name, value, unit
            case referenceLow  = "reference_low"
            case referenceHigh = "reference_high"
            case referenceText = "reference_text"
            case collectedOn   = "collected_on"
        }
    }

    private struct Envelope: Decodable {
        let result: Scan
    }

    static func decode(_ data: Data) throws -> Scan {
        try JSONDecoder().decode(Envelope.self, from: data).result
    }

    // MARK: - Review rows

    /// One editable line on the review screen.
    struct Row: Identifiable, Equatable, Sendable {
        let id: UUID
        let marker: Marker
        var panel: LabPanel?
        /// In `panel.canonicalUnit`. Nil when the printed unit can't be
        /// converted — the user types the value rather than the app
        /// saving a number in the wrong unit.
        var value: Double?
        /// The row's own draw date when the report printed one; otherwise
        /// the report's date applies.
        var date: Date?
        var isIncluded: Bool
    }

    /// Rows for the review screen. A row starts included only when it is
    /// matched, converted, and the first row for its panel — a second
    /// "Glucose" on the same report is more often a urine or repeat value
    /// than the one the user wants charted.
    static func rows(
        from scan: Scan,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [Row] {
        var claimed: Set<LabPanel> = []
        return scan.markers.map { marker in
            let matched = panel(named: marker.name)
            let value = matched.flatMap { convertedValue(marker, to: $0) }
            let isFirst = matched.map { claimed.insert($0).inserted } ?? false
            return Row(
                id: UUID(),
                marker: marker,
                panel: matched,
                value: value,
                date: date(from: marker.collectedOn, notAfter: today, calendar: calendar),
                isIncluded: value != nil && isFirst
            )
        }
    }

    /// The marker's value in `panel`'s canonical unit, or nil.
    static func convertedValue(_ marker: Marker, to panel: LabPanel) -> Double? {
        guard let value = marker.value else { return nil }
        return convert(value, from: marker.unit, to: panel)
    }

    // MARK: - Name matching

    /// The catalog panel a printed test name refers to, or nil.
    static func panel(named name: String) -> LabPanel? {
        synonymIndex[normalizedName(name)]
    }

    /// Case, accents, punctuation, word order and specimen prefixes
    /// removed: "S-Testosteron", "Testosterone, Total" and "TOTAL
    /// TESTOSTERONE (serum)" all reduce to a stable key.
    static func normalizedName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignoredWords.contains($0) }
        return words.sorted().joined(separator: " ")
    }

    /// Specimen prefixes ("S-", "P-", "fP-", "B-" on Nordic reports) and
    /// filler that doesn't change which test it is.
    private static let ignoredWords: Set<String> = [
        "s", "p", "b", "fp", "fs", "pt", "serum", "plasma", "blood", "level", "result",
    ]

    /// Printed names per panel, English plus the Swedish and German forms
    /// common on European reports. Normalised once into `synonymIndex`.
    static let synonyms: [LabPanel: [String]] = [
        .totalTestosterone: ["Testosterone", "Total testosterone", "Testosterone, total", "Testosteron", "Testosteron total"],
        .freeTestosterone: [
            "Free testosterone", "Free testosterone, direct", "Free testosterone, calculated",
            "Calculated free testosterone", "Fritt testosteron", "Freies Testosteron",
        ],
        .estradiol: ["Estradiol", "Oestradiol", "Östradiol", "E2", "Estradiol, sensitive", "Estradiol, ultrasensitive"],
        .shbg: ["SHBG", "Sex hormone binding globulin", "Sexhormonbindande globulin"],
        .lh: ["LH", "Luteinizing hormone", "Luteinising hormone", "Luteiniserande hormon"],
        .fsh: ["FSH", "Follicle stimulating hormone", "Follikelstimulerande hormon"],
        .prolactin: ["Prolactin", "Prolaktin"],
        .igf1: [
            "IGF-1", "IGF1", "IGF-I", "Insulin-like growth factor 1", "Insulin-like growth factor I", "Somatomedin C",
        ],
        .tsh: ["TSH", "Thyroid stimulating hormone", "Thyrotropin", "Tyreoideastimulerande hormon"],
        .freeT3: ["Free T3", "FT3", "T3, free", "Fritt T3", "Free triiodothyronine", "Triiodothyronine, free"],
        .freeT4: ["Free T4", "FT4", "T4, free", "Fritt T4", "Free thyroxine", "Thyroxine, free", "T4, free (direct)"],
        .fastingGlucose: ["Glucose", "Fasting glucose", "Glucose, fasting", "Fasting plasma glucose", "Glukos", "Glucose, serum"],
        .fastingInsulin: ["Insulin", "Fasting insulin", "Insulin, fasting"],
        .hba1c: [
            "HbA1c", "Hb A1c", "A1c", "Hemoglobin A1c", "Haemoglobin A1c", "Glycated hemoglobin",
            "Glycated haemoglobin", "Glykerat hemoglobin",
        ],
        .totalCholesterol: ["Cholesterol", "Total cholesterol", "Cholesterol, total", "Kolesterol", "Total kolesterol", "Gesamtcholesterin"],
        .hdl: ["HDL", "HDL cholesterol", "HDL-C", "Cholesterol, HDL", "HDL-kolesterol", "HDL-Cholesterin"],
        .ldl: [
            "LDL", "LDL cholesterol", "LDL-C", "Cholesterol, LDL", "LDL cholesterol, calculated", "LDL chol calc (NIH)",
            "LDL-kolesterol", "LDL-Cholesterin",
        ],
        .triglycerides: ["Triglycerides", "Triglyceride", "Triglycerider", "Triglyzeride"],
        .alt: ["ALT", "ALAT", "ALT (SGPT)", "SGPT", "Alanine aminotransferase", "Alanine transaminase", "GPT"],
        .ast: ["AST", "ASAT", "AST (SGOT)", "SGOT", "Aspartate aminotransferase", "Aspartate transaminase", "GOT"],
        .creatinine: ["Creatinine", "Kreatinin", "Creatinine, serum"],
        .crp: [
            "hs-CRP", "hsCRP", "CRP", "C-reactive protein", "High sensitivity C-reactive protein",
            "C-reactive protein, cardiac", "CRP, high sensitivity",
        ],
        .vitaminD: [
            "Vitamin D", "25-OH vitamin D", "Vitamin D, 25-hydroxy", "25-hydroxyvitamin D", "25-OH-D",
            "Vitamin D, total", "25-OH vitamin D, total", "D-vitamin", "25-OH D-vitamin",
        ],
        .ferritin: ["Ferritin"],
        .hematocrit: ["Hematocrit", "Haematocrit", "Hct", "EVF", "Packed cell volume", "PCV", "Hämatokrit"],
        .cortisolMorning: ["Cortisol", "Cortisol, AM", "Morning cortisol", "Cortisol, morning", "Kortisol"],
    ]

    private static let synonymIndex: [String: LabPanel] = {
        var index: [String: LabPanel] = [:]
        for (panel, names) in synonyms {
            for name in names { index[normalizedName(name)] = panel }
        }
        return index
    }()

    // MARK: - Unit conversion

    /// `canonical = value × scale + offset`. Only HbA1c (IFCC mmol/mol →
    /// NGSP %) needs the offset.
    struct Conversion: Equatable, Sendable {
        let scale: Double
        var offset: Double = 0
    }

    /// `value` in `panel.canonicalUnit`, rounded to two places, or nil
    /// when the unit isn't one this panel is reported in.
    static func convert(_ value: Double, from unit: String, to panel: LabPanel) -> Double? {
        guard value.isFinite, value >= 0, panel != .other else { return nil }
        let key = normalizedUnit(unit)
        let conversion: Conversion?
        if key == normalizedUnit(panel.canonicalUnit) {
            conversion = Conversion(scale: 1)
        } else {
            conversion = conversions[panel]?[key]
        }
        guard let conversion else { return nil }
        let converted = value * conversion.scale + conversion.offset
        return (converted * 100).rounded() / 100
    }

    /// Lower case, micro sign and Greek mu as "u", "mcg" as "ug", and IU
    /// as U — labs print mIU/mL and mU/mL for the same hormone units.
    static func normalizedUnit(_ unit: String) -> String {
        unit.lowercased()
            .replacingOccurrences(of: "\u{00B5}", with: "u")
            .replacingOccurrences(of: "\u{03BC}", with: "u")
            .replacingOccurrences(of: "mcg", with: "ug")
            .replacingOccurrences(of: "iu", with: "u")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Non-canonical units per panel, keyed by `normalizedUnit`. Factors
    /// are the standard molar-mass and IS conversions.
    private static let conversions: [LabPanel: [String: Conversion]] = {
        let cholesterol: [String: Conversion] = ["mmol/l": Conversion(scale: 38.67)]
        let massPerLitre: [String: Conversion] = ["ug/l": Conversion(scale: 1)]
        return [
            .totalTestosterone: [
                "nmol/l": Conversion(scale: 28.842),
                "ng/ml": Conversion(scale: 100),
                "ug/l": Conversion(scale: 100),
            ],
            .freeTestosterone: [
                "pmol/l": Conversion(scale: 0.28842),
                "nmol/l": Conversion(scale: 288.42),
                "ng/dl": Conversion(scale: 10),
                "ng/l": Conversion(scale: 1),
            ],
            .estradiol: ["pmol/l": Conversion(scale: 1 / 3.671), "ng/l": Conversion(scale: 1)],
            .lh: ["u/l": Conversion(scale: 1)],
            .fsh: ["u/l": Conversion(scale: 1)],
            .prolactin: ["ug/l": Conversion(scale: 1), "mu/l": Conversion(scale: 1 / 21.2)],
            .igf1: ["ug/l": Conversion(scale: 1), "nmol/l": Conversion(scale: 7.649)],
            .tsh: ["mu/l": Conversion(scale: 1)],
            .freeT3: ["pmol/l": Conversion(scale: 0.651), "ng/l": Conversion(scale: 1)],
            .freeT4: [
                "pmol/l": Conversion(scale: 1 / 12.871),
                "pg/ml": Conversion(scale: 0.1),
                "ng/l": Conversion(scale: 0.1),
            ],
            .fastingGlucose: ["mmol/l": Conversion(scale: 18.016)],
            .fastingInsulin: ["mu/l": Conversion(scale: 1), "pmol/l": Conversion(scale: 1 / 6)],
            .hba1c: ["mmol/mol": Conversion(scale: 0.09148, offset: 2.152)],
            .totalCholesterol: cholesterol,
            .hdl: cholesterol,
            .ldl: cholesterol,
            .triglycerides: ["mmol/l": Conversion(scale: 88.57)],
            .alt: ["ukat/l": Conversion(scale: 60)],
            .ast: ["ukat/l": Conversion(scale: 60)],
            .creatinine: ["umol/l": Conversion(scale: 1 / 88.42)],
            .crp: ["mg/dl": Conversion(scale: 10)],
            .vitaminD: ["nmol/l": Conversion(scale: 1 / 2.496), "ug/l": Conversion(scale: 1)],
            .ferritin: massPerLitre,
            .hematocrit: ["l/l": Conversion(scale: 100)],
            .cortisolMorning: ["nmol/l": Conversion(scale: 1 / 27.59)],
        ]
    }()

    // MARK: - Dates

    /// A printed `YYYY-MM-DD` draw date at local noon, so no time zone
    /// can tip it into the neighbouring day. Nil for anything malformed,
    /// impossible (Feb 31) or after `notAfter` — the editor never allows
    /// a future draw date either.
    static func date(from text: String?, notAfter: Date, calendar: Calendar = .current) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] >= 1900 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == parts[0], back.month == parts[1], back.day == parts[2] else { return nil }
        guard calendar.startOfDay(for: date) <= calendar.startOfDay(for: notAfter) else { return nil }
        return date
    }

    /// A converted value ten times outside the typical range is almost
    /// always a unit slip — the same bound `LabEntryEditor` warns at.
    static func looksLikeUnitSlip(_ value: Double, panel: LabPanel, sex: BiologicalSex) -> Bool {
        guard let range = panel.typicalRange(for: sex) else { return false }
        return value < range.lowerBound * 0.1 || value > range.upperBound * 10
    }
}
