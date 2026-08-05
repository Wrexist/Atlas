import Foundation

/// Collapsed equipment taxonomy used by the Train tab filter row and by
/// onboarding's "equipment access" multi-select. Mirrors the dataset's
/// raw equipment strings but folds the long tail ("foam roll",
/// "medicine ball", "exercise ball", "other") into `.other` so the
/// chip row doesn't blow out.
enum EquipmentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case barbell
    case dumbbell
    case kettlebell
    case cable
    case machine
    case smith
    case band
    case bodyweight
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell:    return "Barbell"
        case .dumbbell:   return "Dumbbell"
        case .kettlebell: return "Kettlebell"
        case .cable:      return "Cable"
        case .machine:    return "Machine"
        case .smith:      return "Smith"
        case .band:       return "Bands"
        case .bodyweight: return "Bodyweight"
        case .other:      return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .barbell, .smith: return "figure.strengthtraining.traditional"
        case .dumbbell:        return "dumbbell.fill"
        // Not `figure.kettlebell` — no such SF Symbol. It resolved to
        // nothing, so the Kettlebell card in onboarding drew no icon and
        // collapsed to roughly half the height of its neighbours, which
        // is what made that grid look ragged.
        case .kettlebell:      return "figure.strengthtraining.functional"
        case .cable, .machine: return "gearshape.2.fill"
        case .band:            return "wave.3.right"
        case .bodyweight:      return "figure.run"
        case .other:           return "questionmark.app.fill"
        }
    }

    /// Maps the dataset's raw equipment string to the collapsed enum.
    /// `nil` and unknown strings collapse to `.bodyweight` (matches the
    /// "no equipment needed" intuition for items without a tag) when
    /// the string is missing or explicitly `"none"`, otherwise they
    /// fall through to `.other`.
    static func fromRaw(_ raw: String?) -> EquipmentKind {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return .bodyweight }
        switch raw {
        case "barbell", "e-z curl bar":                     return .barbell
        case "dumbbell":                                    return .dumbbell
        case "kettlebells", "kettlebell":                   return .kettlebell
        case "cable":                                       return .cable
        case "machine":                                     return .machine
        case "smith machine", "smith":                      return .smith
        case "bands", "band":                               return .band
        case "body only", "bodyweight", "none":             return .bodyweight
        default:                                            return .other
        }
    }
}
