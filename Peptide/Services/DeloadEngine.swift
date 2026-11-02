import Foundation

/// Decides when a block of training has earned a lighter week: volume that
/// has climbed week after week, or lifts that stopped moving. Reads only
/// weeks that have ended, so the verdict holds for the whole current week
/// and a deload week's own lighter sessions don't cancel it midway.
enum DeloadEngine {

    enum Reason: Equatable, Sendable {
        case risingVolume
        case stalledLifts
    }

    /// Consecutive training weeks, each with more volume than the last.
    static let risingWeeks = 4
    static let stalledLiftCount = 3
    /// Stalls only count when they're most of what the user trains, so a
    /// couple of stubborn isolation lifts don't call a deload on their own.
    static let stalledShare = 0.5
    static let stallLookbackWeeks = 4
    /// A lift has stalled when its last this-many sessions brought no progress.
    static let stallSessions = 3

    static func reason(history: [WorkoutSession], now: Date, calendar: Calendar) -> Reason? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        let finished = history
            .filter { $0.finishedAt != nil && $0.startedAt < thisWeek.start }
            .sorted { $0.startedAt < $1.startedAt }
        if risingVolumeWeeks(finished, before: thisWeek.start, calendar: calendar) >= risingWeeks {
            return .risingVolume
        }
        guard let lookbackStart = calendar.date(byAdding: .weekOfYear, value: -stallLookbackWeeks, to: thisWeek.start)
        else { return nil }
        let (stalled, tracked) = stalledLifts(finished.filter { $0.startedAt >= lookbackStart })
        guard stalled >= stalledLiftCount, Double(stalled) >= Double(tracked) * stalledShare else { return nil }
        return .stalledLifts
    }

    /// Length of the run of back-to-back weeks before `weekStart` whose
    /// volume rose week on week. A week without volume ends the run.
    static func risingVolumeWeeks(_ sessions: [WorkoutSession], before weekStart: Date, calendar: Calendar) -> Int {
        var volumes: [Double] = []   // newest first
        var end = weekStart
        while volumes.count < risingWeeks, let start = calendar.date(byAdding: .weekOfYear, value: -1, to: end) {
            let volume = sessions
                .filter { $0.startedAt >= start && $0.startedAt < end }
                .reduce(0) { $0 + $1.totalVolumeKg }
            guard volume > 0 else { break }
            volumes.append(volume)
            end = start
        }
        guard !volumes.isEmpty else { return 0 }
        return 1 + zip(volumes, volumes.dropFirst()).prefix { newer, older in newer > older }.count
    }

    /// How many loaded lifts with enough recent sessions have stalled, out of
    /// how many had enough sessions to judge. `sessions` run oldest first.
    static func stalledLifts(_ sessions: [WorkoutSession]) -> (stalled: Int, tracked: Int) {
        var topSets: [String: [SetEntry]] = [:]
        for session in sessions {
            for exerciseID in Set(session.exercises.map(\.exerciseID)) {
                let working = session.exercises
                    .filter { $0.exerciseID == exerciseID }
                    .flatMap(\.completedWorkingSets)
                if let top = topSet(working) { topSets[exerciseID, default: []].append(top) }
            }
        }
        let judged = topSets.values.filter { $0.count >= stallSessions }
        let stalled = judged.filter { tops in
            let recent = tops.suffix(stallSessions)
            return !zip(recent, recent.dropFirst()).contains { progressed(from: $0, to: $1) }
        }
        return (stalled.count, judged.count)
    }

    /// The heaviest loaded set, most reps breaking a tie.
    private static func topSet(_ sets: [SetEntry]) -> SetEntry? {
        sets.filter { $0.weightKg > 0 && $0.reps > 0 }
            .max { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }
    }

    /// More weight, or more reps at the same weight.
    private static func progressed(from old: SetEntry, to new: SetEntry) -> Bool {
        if new.weightKg > old.weightKg + 0.01 { return true }
        return abs(new.weightKg - old.weightKg) <= 0.01 && new.reps > old.reps
    }
}
