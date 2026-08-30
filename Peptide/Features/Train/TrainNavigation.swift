import Foundation

/// Navigation values pushed onto the Train tab's `NavigationStack`.
/// Centralised so the same enum drives `NavigationLink(value:)` calls
/// from anywhere in the tab without each call site re-declaring its
/// own destination type.
enum TrainNavigation: Hashable {
    /// Drill into the full exercise detail (instructions, muscles,
    /// images, history).
    case exerciseDetail(String)
    /// Full workout-session detail: per-exercise sets, effort chip,
    /// PRs, note. Carries the session UUID so the destination view
    /// can fetch from SwiftData lazily — the alternative (passing
    /// the WorkoutSession value itself) would bloat the Hashable
    /// payload and prevent deep-link reconstruction.
    case workoutDetail(UUID)
    /// Full workout history list.
    case workoutHistory
    /// The routine editor. Carries the routine's UUID for the same
    /// reason `workoutDetail` does — the destination resolves it out of
    /// `RoutineStore` so a push survives an edit made elsewhere.
    case routineBuilder(UUID)
}
