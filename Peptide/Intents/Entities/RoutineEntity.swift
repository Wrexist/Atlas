import AppIntents
import Foundation

/// App Intents projection of a saved `Routine`, so "Start workout" can
/// seed the session from the user's library. The routine that comes next
/// in their rotation is suggested first — the same pick as Train's
/// "Start <routine>" button.
struct RoutineEntity: AppEntity, Identifiable {
    let id: String        // routine UUID string
    let displayName: String
    let exerciseCount: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Routine", comment: "App Intents — type name for one workout routine entity"),
            numericFormat: LocalizedStringResource("\(placeholder: .int) routines")
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(exercisesLabel)")
    }

    /// "1 exercise" / "5 exercises", inflected like `RecipeEntity`'s count.
    private var exercisesLabel: String {
        String(AttributedString(localized: "^[\(exerciseCount) exercise](inflect: true)").characters)
    }

    init(routine: Routine) {
        id = routine.id.uuidString
        displayName = routine.name
        exerciseCount = routine.exercises.count
    }

    static let defaultQuery = RoutineEntityQuery()
}

struct RoutineEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RoutineEntity] {
        let all = await MainActor.run { Self.loadRoutines().map(RoutineEntity.init) }
        let lookup = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { lookup[$0] }
    }

    func suggestedEntities() async throws -> [RoutineEntity] {
        await MainActor.run {
            let history = SwiftDataRepository.shared.loadWorkoutSessions()
            return Self.startable(Self.loadRoutines(), history: history).map(RoutineEntity.init)
        }
    }

    /// Routine names are the user's own ("Push A", "Legs"), so a
    /// case-insensitive containment match is enough.
    func entities(matching string: String) async throws -> [RoutineEntity] {
        let needle = string.lowercased()
        let all = try await suggestedEntities()
        return all.filter { $0.displayName.lowercased().contains(needle) }
    }

    /// Routines that can seed a workout, in library order with the next
    /// one in the user's rotation moved to the front.
    @MainActor
    static func startable(_ routines: [Routine], history: [WorkoutSession]) -> [Routine] {
        let ready = routines.filter { !$0.exercises.isEmpty }
        guard let next = TrainOverviewView.suggestedRoutine(from: ready, history: history) else { return ready }
        return [next] + ready.filter { $0.id != next.id }
    }

    /// Re-read rather than trusting the in-memory library: a cold launch
    /// for the intent hasn't loaded it, and another device may have
    /// added a routine since.
    @MainActor
    static func loadRoutines() -> [Routine] {
        RoutineStore.shared.load()
        return RoutineStore.shared.routines
    }
}
