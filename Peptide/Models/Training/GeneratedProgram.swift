import Foundation

/// What a generated program is built to do. Drives the set/rep/rest
/// scheme — the exercise selection is the same for every goal.
enum TrainingGoal: String, CaseIterable, Identifiable, Sendable {
    case strength, hypertrophy, fatLoss, general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength:    return "Get stronger"
        case .hypertrophy: return "Build muscle"
        case .fatLoss:     return "Lose fat"
        case .general:     return "General fitness"
        }
    }

    /// Maps the onboarding `PrimaryGoal` raw value stored on the profile.
    /// Goals that aren't about training (sleep, skin…) land on `.general`.
    init(goalRaw: String?) {
        switch goalRaw {
        case "getStronger", "athletic": self = .strength
        case "buildMuscle", "recomp":   self = .hypertrophy
        case "loseFat":                 self = .fatLoss
        default:                        self = .general
        }
    }
}

/// How a week of training is divided. Chosen from days per week, the way
/// most coaches would: every muscle twice a week without back-to-back
/// sessions hammering the same one.
enum TrainingSplit: String, CaseIterable, Sendable {
    case fullBody, upperLower, pushPullLegs

    static func forDays(_ days: Int) -> TrainingSplit {
        switch days {
        case ...3: return .fullBody
        case 4:    return .upperLower
        default:   return .pushPullLegs
        }
    }

    var displayName: String {
        switch self {
        case .fullBody:     return "Full body"
        case .upperLower:   return "Upper / lower"
        case .pushPullLegs: return "Push / pull / legs"
        }
    }
}

/// The job a routine slot does. A day is a list of these; the generator
/// fills each with the best exercise the user can actually do.
enum MovementPattern: String, CaseIterable, Sendable {
    case squat, hinge, lunge
    case horizontalPush, horizontalPull, verticalPush, verticalPull
    case chestIsolation, lateralDelt, rearDelt, biceps, triceps
    case quadIsolation, hamstringIsolation, calves, core

    var displayName: String {
        switch self {
        case .squat:              return "Squat"
        case .hinge:              return "Hinge"
        case .lunge:              return "Single leg"
        case .horizontalPush:     return "Horizontal push"
        case .horizontalPull:     return "Horizontal pull"
        case .verticalPush:       return "Vertical push"
        case .verticalPull:       return "Vertical pull"
        case .chestIsolation:     return "Chest"
        case .lateralDelt:        return "Side delts"
        case .rearDelt:           return "Rear delts"
        case .biceps:             return "Biceps"
        case .triceps:            return "Triceps"
        case .quadIsolation:      return "Quads"
        case .hamstringIsolation: return "Hamstrings"
        case .calves:             return "Calves"
        case .core:               return "Core"
        }
    }

    var isCompound: Bool {
        switch self {
        case .squat, .hinge, .lunge, .horizontalPush, .horizontalPull, .verticalPush, .verticalPull:
            return true
        default:
            return false
        }
    }

    /// The opposing isolation pattern, when there is one. Two antagonists
    /// can share a superset because neither tires the other.
    var antagonist: MovementPattern? {
        switch self {
        case .biceps:             return .triceps
        case .triceps:            return .biceps
        case .quadIsolation:      return .hamstringIsolation
        case .hamstringIsolation: return .quadIsolation
        case .chestIsolation:     return .rearDelt
        case .rearDelt:           return .chestIsolation
        default:                  return nil
        }
    }
}

extension Exercise.Level {
    /// Onboarding calls the top tier "advanced"; the dataset says "expert".
    var displayName: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert:       return "Advanced"
        }
    }
}

/// Everything the generator needs to know about the lifter.
struct ProgramRequest: Hashable, Sendable {
    var goal: TrainingGoal
    var experience: Exercise.Level
    var daysPerWeek: Int
    var sessionMinutes: Int
    /// Bodyweight is always added on top — everyone has a floor.
    var equipment: Set<EquipmentKind>

    static let dayRange = 2...6
    static let sessionOptions = [30, 45, 60, 75, 90]

    init(
        goal: TrainingGoal = .general,
        experience: Exercise.Level = .beginner,
        daysPerWeek: Int = 3,
        sessionMinutes: Int = 60,
        equipment: Set<EquipmentKind> = [.bodyweight]
    ) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = min(max(daysPerWeek, Self.dayRange.lowerBound), Self.dayRange.upperBound)
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
    }

    /// Prefills the form from what onboarding already asked.
    /// `experienceRaw` is onboarding's stored lifting-experience answer
    /// (`beginner` / `intermediate` / `advanced`).
    init(profile: UserProfile, experienceRaw: String?) {
        let preferences = profile.trainingPreferences ?? TrainingPreferences()
        self.init(
            goal: TrainingGoal(goalRaw: profile.primaryGoal ?? profile.goals.first),
            experience: Self.experience(fromRaw: experienceRaw),
            daysPerWeek: preferences.daysPerWeek,
            equipment: preferences.equipmentAccess
        )
    }

    static func experience(fromRaw raw: String?) -> Exercise.Level {
        switch raw {
        case "intermediate": return .intermediate
        case "advanced":     return .expert
        default:             return .beginner
        }
    }
}

/// The generator's output: one routine per training day, ready for
/// `RoutineStore.add(_:)`.
struct GeneratedProgram: Hashable, Sendable {
    let request: ProgramRequest
    let split: TrainingSplit
    var days: [GeneratedDay]

    var routines: [Routine] { days.map(\.routine) }
}

struct GeneratedDay: Hashable, Identifiable, Sendable {
    var routine: Routine
    /// The pattern each slot fills, keyed by `RoutineExercise.id`, so a
    /// swap can offer exercises that do the same job.
    var patterns: [UUID: MovementPattern]

    var id: UUID { routine.id }
}
