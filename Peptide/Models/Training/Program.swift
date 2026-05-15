import Foundation

/// Multi-week structured training plan. Bundled programs ship as
/// JSON in `Peptide/Resources/programs.json` (loaded by
/// `ProgramCatalog`); user-published / custom programs are out of
/// scope for v1 and not persisted.
///
/// The data model is `Program → Week → Day → RoutineExercise`. A
/// `Day` is essentially an embedded routine — the same set-scheme
/// shape as `RoutineExercise` — without its own `Routine` row, since
/// programs are immutable.
struct Program: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// One-line tagline, e.g. "Strength-focused 3-day full-body for
    /// beginners".
    var tagline: String
    /// Long-form description used on the program detail screen.
    var summary: String
    /// Recommended experience level. Drives the program recommendation
    /// engine.
    var experienceLevel: Exercise.Level
    /// Required minimum days per week. The recommendation engine filters
    /// programs whose `daysPerWeek` exceeds the user's
    /// `TrainingPreferences.daysPerWeek`.
    var daysPerWeek: Int
    /// Equipment required for the program to function. The engine
    /// filters programs whose `requiredEquipment` is not a subset of
    /// the user's `equipmentAccess`.
    var requiredEquipment: Set<EquipmentKind>
    /// Goal tags this program serves — matched against the user's
    /// `primaryGoal` for the recommendation engine. Values are the
    /// canonical English strings used on the onboarding goals step.
    var goalTags: [String]
    var weeks: [ProgramWeek]

    init(
        id: UUID = UUID(),
        name: String,
        tagline: String,
        summary: String,
        experienceLevel: Exercise.Level,
        daysPerWeek: Int,
        requiredEquipment: Set<EquipmentKind>,
        goalTags: [String],
        weeks: [ProgramWeek]
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.summary = summary
        self.experienceLevel = experienceLevel
        self.daysPerWeek = daysPerWeek
        self.requiredEquipment = requiredEquipment
        self.goalTags = goalTags
        self.weeks = weeks
    }
}

struct ProgramWeek: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var weekNumber: Int
    var days: [ProgramDay]

    init(id: UUID = UUID(), weekNumber: Int, days: [ProgramDay]) {
        self.id = id
        self.weekNumber = weekNumber
        self.days = days
    }
}

struct ProgramDay: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var dayNumber: Int
    var name: String
    var exercises: [RoutineExercise]

    init(id: UUID = UUID(), dayNumber: Int, name: String, exercises: [RoutineExercise]) {
        self.id = id
        self.dayNumber = dayNumber
        self.name = name
        self.exercises = exercises
    }
}
