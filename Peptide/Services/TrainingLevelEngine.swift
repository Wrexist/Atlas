import Foundation

/// Training level: every finished workout earns XP for the work in it,
/// and levels get a little further apart as they climb, so the first
/// weeks level up often and a long history still has somewhere to go.
///
/// Derived from saved sessions alone, never stored, so an edited or
/// deleted workout moves the level with it.
enum TrainingLevelEngine {
    /// XP for finishing at all, so a short session still counts.
    static let finishXP = 20
    static let xpPerSet = 5
    /// Sets past this earn nothing more, so one marathon session can't
    /// skip several levels.
    static let maxCountedSets = 40

    struct Progress: Equatable, Sendable {
        let totalXP: Int
        let level: Int
        let xpIntoLevel: Int
        let xpForNextLevel: Int

        var fraction: Double {
            xpForNextLevel > 0 ? Double(xpIntoLevel) / Double(xpForNextLevel) : 0
        }
        var xpToNextLevel: Int { xpForNextLevel - xpIntoLevel }
    }

    struct Gain: Equatable, Sendable {
        let before: Progress
        let after: Progress
        var earnedXP: Int { after.totalXP - before.totalXP }
        var levelsGained: Int { after.level - before.level }
    }

    static func xp(for session: WorkoutSession) -> Int {
        guard !session.isActive else { return 0 }
        let sets = session.completedSetCount
        guard sets > 0 else { return 0 }
        return finishXP + xpPerSet * min(sets, maxCountedSets)
    }

    /// XP needed to go from `level` to the next one.
    static func xpRequired(forLevel level: Int) -> Int {
        100 + 40 * (max(level, 1) - 1)
    }

    static func progress(totalXP: Int) -> Progress {
        var level = 1
        var remaining = max(totalXP, 0)
        while remaining >= xpRequired(forLevel: level) {
            remaining -= xpRequired(forLevel: level)
            level += 1
        }
        return Progress(totalXP: max(totalXP, 0), level: level,
                        xpIntoLevel: remaining, xpForNextLevel: xpRequired(forLevel: level))
    }

    /// What `session` added on top of every workout started before it.
    /// `history` may contain `session` itself; it is matched by id.
    static func gain(for session: WorkoutSession, history: [WorkoutSession]) -> Gain {
        let earlier = history
            .filter { $0.id != session.id && $0.startedAt < session.startedAt }
            .reduce(0) { $0 + xp(for: $1) }
        return Gain(before: progress(totalXP: earlier),
                    after: progress(totalXP: earlier + xp(for: session)))
    }
}
