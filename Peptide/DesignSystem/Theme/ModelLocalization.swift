import SwiftUI

/// SwiftUI-localized titles for model enums. Kept in DesignSystem rather than
/// Models/ so the model layer remains UI-agnostic. Use these in `Text(...)`
/// to flow through Xcode's .xcstrings extraction and the user's locale.
extension PeptideCategory {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .growth: "Growth"
        case .recovery: "Recovery"
        case .cognitive: "Cognitive"
        case .antiAging: "Anti-Aging"
        case .immune: "Immune"
        case .metabolic: "Metabolic"
        case .other: "Other"
        }
    }
}

extension BiologicalSex {
    var localizedDisplay: LocalizedStringKey {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .unspecified: "Prefer not to say"
        }
    }

    var localizedShortLabel: LocalizedStringKey {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .unspecified: "Skip"
        }
    }
}

extension ActivityLevel {
    var localizedDisplay: LocalizedStringKey {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Light"
        case .moderate: "Moderate"
        case .active: "Active"
        case .athlete: "Athlete"
        }
    }

    var localizedSubtitle: LocalizedStringKey {
        switch self {
        case .sedentary: "Desk work, little exercise"
        case .light: "1–2 sessions per week"
        case .moderate: "3–4 sessions per week"
        case .active: "5–6 intense sessions"
        case .athlete: "Daily training, competition"
        }
    }
}
