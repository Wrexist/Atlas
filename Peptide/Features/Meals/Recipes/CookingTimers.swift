import Foundation
import Observation

/// The countdowns a recipe's steps have started. Shared by the recipe page
/// and cooking mode, so a timer started on one keeps running on the other
/// and a step three screens back still rings when its rice is done.
@MainActor
@Observable
final class CookingTimers {

    /// One timer: step `step`'s `index`-th timed wait.
    struct Key: Hashable, Sendable {
        let step: Int
        let index: Int
    }

    private(set) var endDates: [Key: Date] = [:]
    private(set) var finished: Set<Key> = []
    @ObservationIgnored private var tasks: [Key: Task<Void, Never>] = [:]

    func isRunning(_ key: Key) -> Bool { endDates[key] != nil }

    struct Running: Identifiable, Hashable {
        let key: Key
        let end: Date
        var id: Key { key }
    }

    /// Every running timer, soonest first.
    var running: [Running] {
        endDates.map { Running(key: $0.key, end: $0.value) }.sorted { $0.end < $1.end }
    }

    func start(_ key: Key, seconds: Int) {
        cancel(key)
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        endDates[key] = end
        tasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.ring(key)
        }
    }

    func cancel(_ key: Key) {
        tasks[key]?.cancel()
        tasks[key] = nil
        endDates[key] = nil
        finished.remove(key)
    }

    private func ring(_ key: Key) {
        endDates[key] = nil
        tasks[key] = nil
        finished.insert(key)
        Haptics.success()
    }

    /// "4:05", or "1:02:30" past an hour.
    nonisolated static func clock(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// "8 min", "1 h 30 min" in the user's language.
    nonisolated static func label(seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}
