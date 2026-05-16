import Foundation

/// Discrete muscle regions rendered by `MuscleMapView`. Each case maps
/// to a specific shape on either the front or back anatomical figure.
/// Pulled out of the dataset's raw 17 muscle strings into a renderable
/// taxonomy so the map view doesn't have to do string parsing in its
/// drawing code, and so a future polish pass can split or merge regions
/// (e.g. upper vs lower abs) without touching the dataset side.
enum AnatomicalMuscle: String, CaseIterable, Codable, Hashable, Sendable {
    // Front
    case chest
    case abdominals
    case obliques
    case shouldersFront
    case bicepsLeft
    case bicepsRight
    case forearmsFront
    case quadricepsLeft
    case quadricepsRight
    case adductors
    case calvesFront
    case neckFront

    // Back
    case traps
    case lats
    case lowerBack
    case shouldersBack
    case tricepsLeft
    case tricepsRight
    case forearmsBack
    case glutesLeft
    case glutesRight
    case hamstringsLeft
    case hamstringsRight
    case calvesBack

    /// True when the muscle is rendered on the back-view half of
    /// `MuscleMapView`. Drives which side of the map a highlight
    /// lights up.
    var isBack: Bool {
        switch self {
        case .traps, .lats, .lowerBack, .shouldersBack,
             .tricepsLeft, .tricepsRight, .forearmsBack,
             .glutesLeft, .glutesRight,
             .hamstringsLeft, .hamstringsRight, .calvesBack:
            return true
        default:
            return false
        }
    }

    /// Maps a raw dataset muscle string (e.g. "lats", "middle back",
    /// "biceps") to the regions that should highlight on the map.
    /// One raw string can light up multiple anatomical regions —
    /// "biceps" highlights both arms, "quadriceps" highlights both
    /// legs — so the return is a `Set` rather than a single value.
    static func regions(forRawMuscle raw: String) -> Set<AnatomicalMuscle> {
        switch raw.lowercased() {
        case "chest":               return [.chest]
        case "abdominals":          return [.abdominals]
        case "obliques":            return [.obliques]
        case "shoulders":           return [.shouldersFront, .shouldersBack]
        case "neck":                return [.neckFront]
        case "biceps":              return [.bicepsLeft, .bicepsRight]
        case "triceps":             return [.tricepsLeft, .tricepsRight]
        case "forearms":            return [.forearmsFront, .forearmsBack]
        case "quadriceps":          return [.quadricepsLeft, .quadricepsRight]
        case "hamstrings":          return [.hamstringsLeft, .hamstringsRight]
        case "calves":              return [.calvesFront, .calvesBack]
        case "glutes":              return [.glutesLeft, .glutesRight]
        case "lats":                return [.lats]
        case "middle back":         return [.lats, .traps]
        case "lower back":          return [.lowerBack]
        case "traps":               return [.traps]
        case "adductors":           return [.adductors]
        case "abductors":           return [.glutesLeft, .glutesRight]
        default:                    return []
        }
    }

    /// Convenience: collapses a list of raw muscle strings (the
    /// `primaryMuscles` / `secondaryMuscles` arrays on `Exercise`)
    /// into the union of every anatomical region they touch. Used by
    /// `MuscleMapView` callers to translate an exercise's muscle list
    /// into the map's highlight payload in one call.
    static func regions(forRawMuscles raws: [String]) -> Set<AnatomicalMuscle> {
        raws.reduce(into: Set<AnatomicalMuscle>()) { acc, raw in
            acc.formUnion(regions(forRawMuscle: raw))
        }
    }
}
