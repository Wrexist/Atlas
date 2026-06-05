import Foundation

/// Discrete muscle *heads* rendered by `MuscleMapView`. The dataset tags
/// exercises at the muscle-group level ("chest", "shoulders", "triceps"),
/// but most groups have several heads that different movements emphasise —
/// an incline press favours the clavicular pec, a lateral raise the side
/// deltoid, a pushdown the lateral triceps. Splitting the group into heads
/// lets the map light precisely what a given lift actually trains.
///
/// `headWeights(forRawMuscle:exerciseName:)` is the single source of truth:
/// it maps a raw dataset string (plus, optionally, the exercise name) to a
/// `[head: weight]` payload where 1.0 is full stimulus and lower values are
/// the heads a movement works less. With no recognised name cue every head
/// defaults to a high weight, so the whole group lights evenly and nothing
/// regresses versus the old group-level behaviour.
enum AnatomicalMuscle: String, CaseIterable, Codable, Hashable, Sendable {
    // Front
    case pecClavicular
    case pecSternal
    case deltAnterior
    case deltLateralFront
    case biceps
    case forearmFront
    case abdominals
    case obliques
    case quadRectus
    case quadLateralis
    case quadMedialis
    case adductors
    case tibialis
    case neck

    // Back
    case trapsUpper
    case trapsLower
    case rhomboids
    case deltPosterior
    case deltLateralBack
    case tricepsLong
    case tricepsLateral
    case lats
    case lowerBack
    case forearmBack
    case glutes
    case gluteMedius
    case hamstringLateral
    case hamstringMedial
    case gastrocnemius
    case soleus

    /// True when the head is rendered on the back-view half of
    /// `MuscleMapView`. Drives which figure a highlight lights up.
    var isBack: Bool {
        switch self {
        case .trapsUpper, .trapsLower, .rhomboids, .deltPosterior, .deltLateralBack,
             .tricepsLong, .tricepsLateral, .lats, .lowerBack, .forearmBack,
             .glutes, .gluteMedius, .hamstringLateral, .hamstringMedial,
             .gastrocnemius, .soleus:
            return true
        default:
            return false
        }
    }

    /// Friendly, user-facing name for the head — shown on the top-muscles
    /// row and the tap-to-identify label. A few heads share a group label
    /// (the two triceps heads both read "Triceps") where the distinction
    /// only matters for the map's tint, not the callout.
    var displayName: String {
        switch self {
        case .pecClavicular:    return "Upper chest"
        case .pecSternal:       return "Chest"
        case .deltAnterior:     return "Front delts"
        case .deltLateralFront, .deltLateralBack: return "Side delts"
        case .deltPosterior:    return "Rear delts"
        case .biceps:           return "Biceps"
        case .forearmFront, .forearmBack: return "Forearms"
        case .abdominals:       return "Abs"
        case .obliques:         return "Obliques"
        case .quadRectus:       return "Quads · rectus femoris"
        case .quadLateralis:    return "Quads · outer sweep"
        case .quadMedialis:     return "Quads · inner (teardrop)"
        case .adductors:        return "Adductors"
        case .tibialis:         return "Shins"
        case .neck:             return "Neck"
        case .trapsUpper:       return "Upper traps"
        case .trapsLower:       return "Lower traps"
        case .rhomboids:        return "Rhomboids"
        case .tricepsLong:      return "Triceps · long head"
        case .tricepsLateral:   return "Triceps · lateral head"
        case .lats:             return "Lats"
        case .lowerBack:        return "Lower back"
        case .glutes:           return "Glutes"
        case .gluteMedius:      return "Glute medius"
        case .hamstringLateral: return "Hamstrings · outer"
        case .hamstringMedial:  return "Hamstrings · inner"
        case .gastrocnemius:    return "Calves · gastrocnemius"
        case .soleus:           return "Calves · soleus"
        }
    }

    /// Per-head emphasis weights (0…1) for a raw dataset muscle string,
    /// specialised by the exercise name where a recognised cue exists.
    /// 1.0 = full stimulus for that head; lower = worked less by this
    /// movement. An unknown raw string yields an empty payload; an
    /// unrecognised name falls back to all heads near-full so the whole
    /// group lights.
    static func headWeights(
        forRawMuscle raw: String,
        exerciseName name: String = ""
    ) -> [AnatomicalMuscle: Double] {
        let n = name.lowercased()
        func has(_ keywords: String...) -> Bool { keywords.contains { n.contains($0) } }

        switch raw.lowercased() {
        case "chest":
            if has("incline") { return [.pecClavicular: 1.0, .pecSternal: 0.55] }
            if has("decline") { return [.pecSternal: 1.0, .pecClavicular: 0.30] }
            return [.pecSternal: 1.0, .pecClavicular: 0.70]

        case "shoulders":
            if has("lateral raise", "side lateral", "upright row") {
                return [.deltLateralFront: 1.0, .deltLateralBack: 1.0,
                        .deltAnterior: 0.30, .deltPosterior: 0.30]
            }
            if has("rear", "reverse fly", "reverse flye", "face pull", "rear delt") {
                return [.deltPosterior: 1.0, .deltLateralBack: 0.50,
                        .deltLateralFront: 0.20, .deltAnterior: 0.10]
            }
            if has("front raise", "press", "overhead", "military", "arnold", "push press") {
                return [.deltAnterior: 1.0, .deltLateralFront: 0.60,
                        .deltLateralBack: 0.30, .deltPosterior: 0.20]
            }
            return [.deltAnterior: 0.80, .deltLateralFront: 0.80,
                    .deltLateralBack: 0.70, .deltPosterior: 0.60]

        case "triceps":
            if has("overhead", "french", "skull", "lying triceps", "lying extension") {
                return [.tricepsLong: 1.0, .tricepsLateral: 0.60]
            }
            if has("pushdown", "pressdown", "kickback", "close-grip", "close grip", "dip") {
                return [.tricepsLateral: 1.0, .tricepsLong: 0.60]
            }
            return [.tricepsLong: 0.85, .tricepsLateral: 0.85]

        case "calves":
            if has("seated") { return [.soleus: 1.0, .gastrocnemius: 0.40, .tibialis: 0.15] }
            if has("tibialis", "toe raise") { return [.tibialis: 1.0, .gastrocnemius: 0.20, .soleus: 0.20] }
            return [.gastrocnemius: 1.0, .soleus: 0.70, .tibialis: 0.20]

        case "traps":
            if has("shrug") { return [.trapsUpper: 1.0, .trapsLower: 0.30] }
            if has("row", "face pull", "y raise", "y-raise", "pulldown", "pull-up", "pullup") {
                return [.trapsLower: 0.90, .trapsUpper: 0.60]
            }
            return [.trapsUpper: 0.90, .trapsLower: 0.70]

        case "middle back":
            // Rhomboids between the scapulae, plus lower-trap and lat help.
            return [.rhomboids: 1.0, .trapsLower: 0.50, .lats: 0.40]

        case "quadriceps":
            if has("hack", "front squat", "sissy", "leg extension") {
                return [.quadRectus: 1.0, .quadLateralis: 0.90, .quadMedialis: 0.90]
            }
            return [.quadRectus: 1.0, .quadLateralis: 1.0, .quadMedialis: 1.0]

        case "hamstrings":
            return [.hamstringLateral: 1.0, .hamstringMedial: 1.0]

        case "abdominals":   return [.abdominals: 1.0]
        case "obliques":     return [.obliques: 1.0]
        case "neck":         return [.neck: 1.0]
        case "biceps":       return [.biceps: 1.0]
        case "forearms":     return [.forearmFront: 1.0, .forearmBack: 1.0]
        case "glutes":       return [.glutes: 1.0]
        case "abductors":    return [.gluteMedius: 1.0]   // hip abductor / gluteus medius
        case "adductors":    return [.adductors: 1.0]
        case "lats":         return [.lats: 1.0]
        case "lower back":   return [.lowerBack: 1.0]
        default:             return [:]
        }
    }

    /// Context-free region set for a raw muscle string — every head of the
    /// group at once. Used where there's no exercise name to specialise by
    /// (and by the simpler highlight builders). One raw string can light
    /// several heads, so the return is a `Set`.
    static func regions(forRawMuscle raw: String) -> Set<AnatomicalMuscle> {
        Set(headWeights(forRawMuscle: raw).keys)
    }

    /// Convenience: the union of every head touched by a list of raw
    /// muscle strings (an exercise's `primaryMuscles` / `secondaryMuscles`).
    static func regions(forRawMuscles raws: [String]) -> Set<AnatomicalMuscle> {
        raws.reduce(into: Set<AnatomicalMuscle>()) { acc, raw in
            acc.formUnion(regions(forRawMuscle: raw))
        }
    }
}

extension AnatomicalMuscle: Identifiable {
    /// Stable identity for `.sheet(item:)` and `ForEach` — the raw case name.
    var id: String { rawValue }
}
