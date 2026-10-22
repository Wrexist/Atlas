import Foundation

/// The most recently finished workout, flattened to what a training
/// widget renders. Volume stays in canonical kilograms — the same
/// contract `SetEntry` and session totals keep in-app — and is
/// converted for display against `WidgetData.measurementUnit`.
struct WidgetWorkoutSummary: Codable, Hashable, Sendable {
    /// Session name, or "" for an unnamed workout (the widget falls
    /// back to a date label rather than printing an empty line).
    let name: String
    let finishedAt: Date
    let setCount: Int
    let volumeKg: Double
    let durationMinutes: Int
}
