import Foundation

/// The floor that keeps a day: a few small things that still count on a
/// bad day. A day that meets them is a whole day, and five a week keeps
/// the week, so one missed day never undoes anything.
struct MinimumDay: Codable, Equatable, Sendable {
    enum Part: String, Codable, CaseIterable, Sendable {
        case logFood, protein, walk, checkIn
    }

    var parts: Set<Part>
    /// Days the minimum was met (`DayKey.compact`). Only ever added to,
    /// so the running total can't drop when a part is changed later.
    var metDayKeys: Set<String>

    static let `default` = MinimumDay(parts: [.logFood, .protein], metDayKeys: [])
    /// About ten minutes of walking.
    static let walkSteps = 1_000
    static let weeklyGoal = 5

    private enum CodingKeys: String, CodingKey {
        case parts, metDayKeys
    }

    /// Sorted arrays, so equal values encode to equal bytes and the
    /// profile blob isn't rewritten for a reordered set.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parts.map(\.rawValue).sorted(), forKey: .parts)
        try container.encode(metDayKeys.sorted(), forKey: .metDayKeys)
    }
}
