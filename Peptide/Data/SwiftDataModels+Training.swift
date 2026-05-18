import Foundation
import SwiftData

// MARK: - Shared codec
//
// The codec in `SwiftDataModels.swift` is file-private to that file.
// Mirror it here so this module is self-contained — duplicating two
// lightweight JSONCoder instances is cheaper than relaxing visibility
// and risking accidental shared mutable state.

private let trainingEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let trainingDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

// MARK: - StoredWorkoutSession

/// On-disk shell for a `WorkoutSession`. The exercises + sets nested
/// arrays are encoded as a single JSON blob on `exercisesData` rather
/// than relationship-mapped because (a) sessions are always read
/// whole, (b) sets are bounded (~40 per session), and (c) keeping
/// the blob means we can evolve the value-type schema without a
/// SwiftData migration.
@Model
final class StoredWorkoutSession {
    @Attribute(.unique) var id: UUID
    var name: String?
    var routineID: UUID?
    var programID: UUID?
    var startedAt: Date
    var finishedAt: Date?
    var note: String?
    var perceivedEffort: Int?
    /// JSON-encoded `[WorkoutExerciseEntry]`. See `WorkoutSession.swift`.
    var exercisesData: Data
    /// Cached totals, recomputed on every write. Lets the history
    /// list render without decoding the full exercises blob — the
    /// blob is only touched when the user drills into a specific
    /// session.
    var totalVolumeKg: Double
    var completedSetCount: Int

    init(
        id: UUID,
        name: String?,
        routineID: UUID?,
        programID: UUID?,
        startedAt: Date,
        finishedAt: Date?,
        note: String?,
        perceivedEffort: Int?,
        exercisesData: Data,
        totalVolumeKg: Double,
        completedSetCount: Int
    ) {
        self.id = id
        self.name = name
        self.routineID = routineID
        self.programID = programID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.note = note
        self.perceivedEffort = perceivedEffort
        self.exercisesData = exercisesData
        self.totalVolumeKg = totalVolumeKg
        self.completedSetCount = completedSetCount
    }

    static func make(from session: WorkoutSession) throws -> StoredWorkoutSession {
        let data = try trainingEncoder.encode(session.exercises)
        return StoredWorkoutSession(
            id: session.id,
            name: session.name,
            routineID: session.routineID,
            programID: session.programID,
            startedAt: session.startedAt,
            finishedAt: session.finishedAt,
            note: session.note,
            perceivedEffort: session.perceivedEffort,
            exercisesData: data,
            totalVolumeKg: session.totalVolumeKg,
            completedSetCount: session.completedSetCount
        )
    }

    func update(from session: WorkoutSession) throws {
        name = session.name
        routineID = session.routineID
        programID = session.programID
        startedAt = session.startedAt
        finishedAt = session.finishedAt
        note = session.note
        perceivedEffort = session.perceivedEffort
        exercisesData = try trainingEncoder.encode(session.exercises)
        totalVolumeKg = session.totalVolumeKg
        completedSetCount = session.completedSetCount
    }

    func toWorkoutSession() throws -> WorkoutSession {
        let exercises = try trainingDecoder.decode([WorkoutExerciseEntry].self, from: exercisesData)
        return WorkoutSession(
            id: id,
            name: name,
            routineID: routineID,
            programID: programID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exercises: exercises,
            note: note,
            perceivedEffort: perceivedEffort
        )
    }
}

// MARK: - StoredCustomExercise

@Model
final class StoredCustomExercise {
    @Attribute(.unique) var id: String
    var name: String
    var equipment: String?
    var createdAt: Date
    /// JSON-encoded `[String]`. Two columns instead of one keeps the
    /// primary/secondary distinction queryable from a future SwiftData
    /// predicate, but the predicate use is hypothetical today —
    /// callers go through `ExerciseLibrary` and resolve in memory.
    var primaryMusclesData: Data
    var secondaryMusclesData: Data
    /// JSON-encoded `[String]`.
    var instructionsData: Data

    init(
        id: String,
        name: String,
        equipment: String?,
        createdAt: Date,
        primaryMusclesData: Data,
        secondaryMusclesData: Data,
        instructionsData: Data
    ) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.createdAt = createdAt
        self.primaryMusclesData = primaryMusclesData
        self.secondaryMusclesData = secondaryMusclesData
        self.instructionsData = instructionsData
    }

    static func make(from exercise: CustomExercise) throws -> StoredCustomExercise {
        StoredCustomExercise(
            id: exercise.id,
            name: exercise.name,
            equipment: exercise.equipment,
            createdAt: exercise.createdAt,
            primaryMusclesData: try trainingEncoder.encode(exercise.primaryMuscles),
            secondaryMusclesData: try trainingEncoder.encode(exercise.secondaryMuscles),
            instructionsData: try trainingEncoder.encode(exercise.instructions)
        )
    }

    func update(from exercise: CustomExercise) throws {
        name = exercise.name
        equipment = exercise.equipment
        primaryMusclesData = try trainingEncoder.encode(exercise.primaryMuscles)
        secondaryMusclesData = try trainingEncoder.encode(exercise.secondaryMuscles)
        instructionsData = try trainingEncoder.encode(exercise.instructions)
    }

    func toCustomExercise() throws -> CustomExercise {
        CustomExercise(
            id: id,
            name: name,
            primaryMuscles: try trainingDecoder.decode([String].self, from: primaryMusclesData),
            secondaryMuscles: try trainingDecoder.decode([String].self, from: secondaryMusclesData),
            equipment: equipment,
            instructions: try trainingDecoder.decode([String].self, from: instructionsData),
            createdAt: createdAt
        )
    }
}

// MARK: - StoredRoutine

@Model
final class StoredRoutine {
    @Attribute(.unique) var id: UUID
    var name: String
    var subtitle: String?
    var defaultRestSeconds: Int?
    var updatedAt: Date
    /// JSON-encoded `[RoutineExercise]`.
    var exercisesData: Data

    init(
        id: UUID,
        name: String,
        subtitle: String?,
        defaultRestSeconds: Int?,
        updatedAt: Date,
        exercisesData: Data
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.defaultRestSeconds = defaultRestSeconds
        self.updatedAt = updatedAt
        self.exercisesData = exercisesData
    }

    static func make(from routine: Routine) throws -> StoredRoutine {
        StoredRoutine(
            id: routine.id,
            name: routine.name,
            subtitle: routine.subtitle,
            defaultRestSeconds: routine.defaultRestSeconds,
            updatedAt: routine.updatedAt,
            exercisesData: try trainingEncoder.encode(routine.exercises)
        )
    }

    func update(from routine: Routine) throws {
        name = routine.name
        subtitle = routine.subtitle
        defaultRestSeconds = routine.defaultRestSeconds
        updatedAt = routine.updatedAt
        exercisesData = try trainingEncoder.encode(routine.exercises)
    }

    func toRoutine() throws -> Routine {
        Routine(
            id: id,
            name: name,
            subtitle: subtitle,
            exercises: try trainingDecoder.decode([RoutineExercise].self, from: exercisesData),
            defaultRestSeconds: defaultRestSeconds,
            updatedAt: updatedAt
        )
    }
}

// MARK: - StoredPersonalRecord

@Model
final class StoredPersonalRecord {
    @Attribute(.unique) var exerciseID: String
    var bestEstimatedOneRepMaxKg: Double?
    var bestEstimatedOneRepMaxAt: Date?
    var bestAbsoluteWeightKg: Double?
    var bestAbsoluteWeightAt: Date?
    var bestSessionVolumeKg: Double?
    var bestSessionVolumeAt: Date?
    /// Bodyweight rep PR — populated for weight-0 exercises like
    /// push-ups, pull-ups, dips. Older SwiftData stores migrate
    /// gracefully because Swift's @Model lightweight migration adds
    /// new optional properties as `nil` on existing rows.
    var bestRepsBodyweight: Int?
    var bestRepsBodyweightAt: Date?

    init(
        exerciseID: String,
        bestEstimatedOneRepMaxKg: Double? = nil,
        bestEstimatedOneRepMaxAt: Date? = nil,
        bestAbsoluteWeightKg: Double? = nil,
        bestAbsoluteWeightAt: Date? = nil,
        bestSessionVolumeKg: Double? = nil,
        bestSessionVolumeAt: Date? = nil,
        bestRepsBodyweight: Int? = nil,
        bestRepsBodyweightAt: Date? = nil
    ) {
        self.exerciseID = exerciseID
        self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
        self.bestEstimatedOneRepMaxAt = bestEstimatedOneRepMaxAt
        self.bestAbsoluteWeightKg = bestAbsoluteWeightKg
        self.bestAbsoluteWeightAt = bestAbsoluteWeightAt
        self.bestSessionVolumeKg = bestSessionVolumeKg
        self.bestSessionVolumeAt = bestSessionVolumeAt
        self.bestRepsBodyweight = bestRepsBodyweight
        self.bestRepsBodyweightAt = bestRepsBodyweightAt
    }

    static func make(from record: PersonalRecord) -> StoredPersonalRecord {
        StoredPersonalRecord(
            exerciseID: record.exerciseID,
            bestEstimatedOneRepMaxKg: record.bestEstimatedOneRepMaxKg,
            bestEstimatedOneRepMaxAt: record.bestEstimatedOneRepMaxAt,
            bestAbsoluteWeightKg: record.bestAbsoluteWeightKg,
            bestAbsoluteWeightAt: record.bestAbsoluteWeightAt,
            bestSessionVolumeKg: record.bestSessionVolumeKg,
            bestSessionVolumeAt: record.bestSessionVolumeAt,
            bestRepsBodyweight: record.bestRepsBodyweight,
            bestRepsBodyweightAt: record.bestRepsBodyweightAt
        )
    }

    func update(from record: PersonalRecord) {
        bestEstimatedOneRepMaxKg = record.bestEstimatedOneRepMaxKg
        bestEstimatedOneRepMaxAt = record.bestEstimatedOneRepMaxAt
        bestAbsoluteWeightKg = record.bestAbsoluteWeightKg
        bestAbsoluteWeightAt = record.bestAbsoluteWeightAt
        bestSessionVolumeKg = record.bestSessionVolumeKg
        bestSessionVolumeAt = record.bestSessionVolumeAt
        bestRepsBodyweight = record.bestRepsBodyweight
        bestRepsBodyweightAt = record.bestRepsBodyweightAt
    }

    func toPersonalRecord() -> PersonalRecord {
        PersonalRecord(
            exerciseID: exerciseID,
            bestEstimatedOneRepMaxKg: bestEstimatedOneRepMaxKg,
            bestEstimatedOneRepMaxAt: bestEstimatedOneRepMaxAt,
            bestAbsoluteWeightKg: bestAbsoluteWeightKg,
            bestAbsoluteWeightAt: bestAbsoluteWeightAt,
            bestSessionVolumeKg: bestSessionVolumeKg,
            bestSessionVolumeAt: bestSessionVolumeAt,
            bestRepsBodyweight: bestRepsBodyweight,
            bestRepsBodyweightAt: bestRepsBodyweightAt
        )
    }
}
