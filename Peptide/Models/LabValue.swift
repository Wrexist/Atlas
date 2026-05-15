import Foundation
import SwiftUI

/// One blood-work data point. Captures the result of a single lab
/// test on a specific date, plus the unit and an optional source
/// label (lab name, ordering provider). Stored on `UserProfile`
/// alongside the rest of the user's tracked metrics so labs survive
/// cross-device sync.
///
/// Reference ranges live on `LabPanel`, not here — every user's
/// "normal" is slightly different (age, sex, lab method), and
/// users in the peptide-optimisation cohort routinely chase
/// values above the population reference range anyway. The panel
/// surfaces a generic range as a guideline; this entry stores the
/// raw number.
struct LabValue: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// Date the blood was drawn. Surfaced on the trend chart.
    var date: Date
    /// Which marker this entry tracks. Drives display name + units
    /// + reference range.
    var panel: LabPanel
    /// The reported value. Stored in `panel.canonicalUnit` — the
    /// editor converts on input if the user reported in an
    /// alternative unit, so the timeline math doesn't have to
    /// branch.
    var value: Double
    /// Optional source — "Quest", "Marek Health", "Inside Tracker".
    /// Useful when a user runs labs at multiple places and wants
    /// to keep track of which set came from which.
    var source: String?
    /// Optional free-form note. Surfaced in the timeline detail.
    var note: String?
    /// Stamp on create / edit. Lets the list show an "edited"
    /// indicator if the user revised a value.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        panel: LabPanel,
        value: Double,
        source: String? = nil,
        note: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.panel = panel
        self.value = value
        self.source = source
        self.note = note
        self.updatedAt = updatedAt
    }
}

/// Common lab panels for the peptide-optimisation cohort. The list
/// errs on the side of "things this audience actually orders" —
/// testosterone + free T are the most-tracked, IGF-1 is the
/// signature marker for HGH-axis peptides, the thyroid trio and
/// the metabolic panel matter for GLP-1 / general health users.
///
/// Each case carries its display name, SF Symbol, accent tint, the
/// canonical unit, and a *general* reference range. The range is a
/// guideline only — labs use different methodologies, and the user
/// should always interpret against their own lab's reference.
enum LabPanel: String, Codable, CaseIterable, Identifiable, Sendable {
    // Sex hormones / HPTA
    case totalTestosterone
    case freeTestosterone
    case estradiol
    case shbg
    case lh
    case fsh
    case prolactin

    // GH / IGF axis
    case igf1

    // Thyroid
    case tsh
    case freeT3
    case freeT4

    // Metabolic
    case fastingGlucose
    case fastingInsulin
    case hba1c

    // Lipids
    case totalCholesterol
    case hdl
    case ldl
    case triglycerides

    // Liver / kidney / inflammation
    case alt
    case ast
    case creatinine
    case crp

    // Other
    case vitaminD
    case ferritin
    case hematocrit
    case cortisolMorning

    /// Open slot for any test not in the curated list. Display name
    /// + unit come from a sibling field on `LabValue` once we add
    /// the "custom panel" editor path. For v1 this is unused; the
    /// case is reserved so a future schema can flip the editor on
    /// without a migration.
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .totalTestosterone:  String(localized: "Total testosterone")
        case .freeTestosterone:   String(localized: "Free testosterone")
        case .estradiol:          String(localized: "Estradiol")
        case .shbg:               String(localized: "SHBG")
        case .lh:                 String(localized: "LH")
        case .fsh:                String(localized: "FSH")
        case .prolactin:          String(localized: "Prolactin")
        case .igf1:               String(localized: "IGF-1")
        case .tsh:                String(localized: "TSH")
        case .freeT3:             String(localized: "Free T3")
        case .freeT4:             String(localized: "Free T4")
        case .fastingGlucose:     String(localized: "Fasting glucose")
        case .fastingInsulin:     String(localized: "Fasting insulin")
        case .hba1c:              String(localized: "HbA1c")
        case .totalCholesterol:   String(localized: "Total cholesterol")
        case .hdl:                String(localized: "HDL")
        case .ldl:                String(localized: "LDL")
        case .triglycerides:      String(localized: "Triglycerides")
        case .alt:                String(localized: "ALT")
        case .ast:                String(localized: "AST")
        case .creatinine:         String(localized: "Creatinine")
        case .crp:                String(localized: "hs-CRP")
        case .vitaminD:           String(localized: "Vitamin D")
        case .ferritin:           String(localized: "Ferritin")
        case .hematocrit:         String(localized: "Hematocrit")
        case .cortisolMorning:    String(localized: "Cortisol (AM)")
        case .other:              String(localized: "Other")
        }
    }

    /// Short abbreviation for the sparkline cards. Picked to be
    /// unambiguous at glance — "TT" vs "FT" is clearer than the
    /// full name shrunken to 8pt.
    var shortName: String {
        switch self {
        case .totalTestosterone: "Total T"
        case .freeTestosterone:  "Free T"
        case .estradiol:         "E2"
        case .shbg:              "SHBG"
        case .lh:                "LH"
        case .fsh:               "FSH"
        case .prolactin:         "Prolactin"
        case .igf1:              "IGF-1"
        case .tsh:               "TSH"
        case .freeT3:            "Free T3"
        case .freeT4:            "Free T4"
        case .fastingGlucose:    "Glucose"
        case .fastingInsulin:    "Insulin"
        case .hba1c:             "HbA1c"
        case .totalCholesterol:  "Chol"
        case .hdl:               "HDL"
        case .ldl:               "LDL"
        case .triglycerides:     "Trigs"
        case .alt:               "ALT"
        case .ast:               "AST"
        case .creatinine:        "Cr"
        case .crp:               "hs-CRP"
        case .vitaminD:          "Vit D"
        case .ferritin:          "Ferritin"
        case .hematocrit:        "Hct"
        case .cortisolMorning:   "Cortisol"
        case .other:             "Other"
        }
    }

    /// US-convention canonical unit. Internal storage on
    /// `LabValue.value` is always in this unit; the editor accepts
    /// the user's reported number and converts on save when their
    /// lab reports in the SI alternative.
    var canonicalUnit: String {
        switch self {
        case .totalTestosterone:  "ng/dL"
        case .freeTestosterone:   "pg/mL"
        case .estradiol:          "pg/mL"
        case .shbg:               "nmol/L"
        case .lh:                 "mIU/mL"
        case .fsh:                "mIU/mL"
        case .prolactin:          "ng/mL"
        case .igf1:               "ng/mL"
        case .tsh:                "μIU/mL"
        case .freeT3:             "pg/mL"
        case .freeT4:             "ng/dL"
        case .fastingGlucose:     "mg/dL"
        case .fastingInsulin:     "μIU/mL"
        case .hba1c:              "%"
        case .totalCholesterol:   "mg/dL"
        case .hdl:                "mg/dL"
        case .ldl:                "mg/dL"
        case .triglycerides:      "mg/dL"
        case .alt:                "U/L"
        case .ast:                "U/L"
        case .creatinine:         "mg/dL"
        case .crp:                "mg/L"
        case .vitaminD:           "ng/mL"
        case .ferritin:           "ng/mL"
        case .hematocrit:         "%"
        case .cortisolMorning:    "μg/dL"
        case .other:              ""
        }
    }

    /// Generic adult reference range. Used as a guideline overlay
    /// on the chart — the user's actual lab will list their lab's
    /// own ranges, which may differ. Ranges drawn from broad
    /// LabCorp / Quest adult reference intervals; they're a
    /// starting point, not a clinical recommendation.
    var typicalRange: ClosedRange<Double>? {
        switch self {
        case .totalTestosterone:  return 264...916
        case .freeTestosterone:   return 8.7...25.1
        case .estradiol:          return 7.6...42.6
        case .shbg:               return 16.5...55.9
        case .lh:                 return 1.7...8.6
        case .fsh:                return 1.5...12.4
        case .prolactin:          return 4.0...15.2
        case .igf1:               return 78...258
        case .tsh:                return 0.45...4.5
        case .freeT3:             return 2.0...4.4
        case .freeT4:             return 0.82...1.77
        case .fastingGlucose:     return 70...99
        case .fastingInsulin:     return 2.6...24.9
        case .hba1c:              return 4.0...5.6
        case .totalCholesterol:   return 100...199
        case .hdl:                return 40...100
        case .ldl:                return 0...99
        case .triglycerides:      return 0...149
        case .alt:                return 7...56
        case .ast:                return 10...40
        case .creatinine:         return 0.7...1.3
        case .crp:                return 0...3
        case .vitaminD:           return 30...100
        case .ferritin:           return 30...400
        case .hematocrit:         return 38.3...48.6
        case .cortisolMorning:    return 6.2...19.4
        case .other:              return nil
        }
    }

    /// Grouping for the list view's section headers.
    var category: Category {
        switch self {
        case .totalTestosterone, .freeTestosterone, .estradiol, .shbg, .lh, .fsh, .prolactin:
            return .sexHormones
        case .igf1:
            return .growth
        case .tsh, .freeT3, .freeT4:
            return .thyroid
        case .fastingGlucose, .fastingInsulin, .hba1c:
            return .metabolic
        case .totalCholesterol, .hdl, .ldl, .triglycerides:
            return .lipids
        case .alt, .ast, .creatinine, .crp:
            return .organHealth
        case .vitaminD, .ferritin, .hematocrit, .cortisolMorning, .other:
            return .other
        }
    }

    /// Single source of truth for the section accent tint —
    /// consumed by the list rows and the per-panel chart so a
    /// "thyroid" page reads as one design idiom end to end.
    var tint: Color {
        switch category {
        case .sexHormones: Color(red: 0.92, green: 0.45, blue: 0.62)
        case .growth:      Color(red: 0.40, green: 0.78, blue: 0.55)
        case .thyroid:     Color(red: 0.48, green: 0.50, blue: 0.92)
        case .metabolic:   Color(red: 0.95, green: 0.65, blue: 0.30)
        case .lipids:      Color(red: 0.92, green: 0.38, blue: 0.38)
        case .organHealth: Color(red: 0.55, green: 0.78, blue: 0.92)
        case .other:       Color(red: 0.75, green: 0.75, blue: 0.85)
        }
    }

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case sexHormones
        case growth
        case thyroid
        case metabolic
        case lipids
        case organHealth
        case other

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sexHormones: String(localized: "Sex hormones")
            case .growth:      String(localized: "Growth")
            case .thyroid:     String(localized: "Thyroid")
            case .metabolic:   String(localized: "Metabolic")
            case .lipids:      String(localized: "Lipids")
            case .organHealth: String(localized: "Organ health")
            case .other:       String(localized: "Other")
            }
        }
    }
}
