import Foundation

/// Collapsed 9-chip taxonomy used by the Train tab filter row. The
/// underlying dataset uses 17 raw muscle strings; we keep the raw
/// strings on `Exercise` for the detail screen and only collapse at
/// the filter layer so the UI stays clean without losing information.
enum MuscleGroup: String, CaseIterable, Codable, Identifiable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    case glutes
    case core
    case fullBody
    case cardioMobility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest:          return String(localized: "Chest")
        case .back:           return String(localized: "Back")
        case .shoulders:      return String(localized: "Shoulders")
        case .arms:           return String(localized: "Arms")
        case .legs:           return String(localized: "Legs")
        case .glutes:         return String(localized: "Glutes")
        case .core:           return String(localized: "Core")
        case .fullBody:       return String(localized: "Full Body")
        case .cardioMobility: return String(localized: "Cardio & Mobility")
        }
    }

    /// SF Symbol picked to read at chip size. Falls back to a neutral
    /// figure when no better symbol exists.
    var symbolName: String {
        switch self {
        case .chest:          return "figure.mixed.cardio"
        case .back:           return "figure.archery"
        case .shoulders:      return "figure.arms.open"
        case .arms:           return "dumbbell.fill"
        case .legs:           return "figure.strengthtraining.functional"
        case .glutes:         return "figure.cooldown"
        case .core:           return "figure.core.training"
        case .fullBody:       return "figure.strengthtraining.traditional"
        case .cardioMobility: return "figure.flexibility"
        }
    }

    /// Maps a raw dataset muscle string (e.g. "lats", "middle back",
    /// "quadriceps") to its collapsed group. Returns `nil` for
    /// unrecognized strings so callers can decide whether to fall
    /// through to `.fullBody` (compound) or just skip the exercise.
    /// Also accepts this enum's own raw values, which custom exercises
    /// store as their muscles.
    static func fromRaw(_ raw: String) -> MuscleGroup? {
        switch raw.lowercased() {
        case "chest":                                            return .chest
        case "back", "lats", "middle back", "lower back",
             "traps":                                            return .back
        case "shoulders", "neck":                                return .shoulders
        case "arms", "biceps", "triceps", "forearms":            return .arms
        case "legs", "quadriceps", "hamstrings", "calves",
             "adductors":                                        return .legs
        // Abductors (gluteus medius/minimus) anatomically sit with the
        // glutes — `AnatomicalMuscle.fromRaw` already maps them that
        // way, so the collapsed group matches (audit Train M5).
        case "glutes", "abductors":                              return .glutes
        case "core", "abdominals":                               return .core
        case "fullbody":                                         return .fullBody
        case "cardiomobility":                                   return .cardioMobility
        default:                                                 return nil
        }
    }
}
