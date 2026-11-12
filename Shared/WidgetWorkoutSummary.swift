import Foundation

/// The most recently finished workout, flattened to what a training
/// widget renders. Volume stays in canonical kilograms — the same
/// contract `SetEntry` and session totals keep in-app — and is
/// converted for display against `WidgetData.measurementUnit`.
struct WidgetWorkoutSummary: Codable, Hashable, Sendable {
    /// Session name, or "" for an unnamed workout (the widget falls
    /// back to a date label rather than printing an empty line).
    let name: String
    /// Optional because payloads written before it existed carry only
    /// `finishedAt`.
    var startedAt: Date?
    let finishedAt: Date
    let setCount: Int
    let volumeKg: Double
    let durationMinutes: Int

    /// When the workout happened, for labels. A workout belongs to the
    /// day it started — the rule `WorkoutSession.dayAnchor` sets in-app —
    /// so one that ran past midnight is not labelled with the next day.
    var day: Date { startedAt ?? finishedAt }
}
