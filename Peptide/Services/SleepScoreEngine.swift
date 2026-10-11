import Foundation

/// Turns last night's raw sleep-analysis segments into a staged summary
/// and a 0…100 Sleep Score for the Watch's Sleep page and complication.
/// Pure value-in / value-out, like `RecoveryScoreEngine`, so it tests
/// without HealthKit.
///
/// The score has three parts:
/// - **Duration** against the sleep target. This dominates, because
///   short sleep is the failure that matters most.
/// - **Restorative share**: deep + REM as a fraction of time asleep.
/// - **Continuity**: how little of the night was spent awake.
///
/// Sources that record no stages (most third-party trackers, iPhone-only
/// sleep) are scored on duration and continuity alone, with the weights
/// renormalised, rather than being punished for data they never had.
enum SleepScoreEngine {

    enum Stage: Sendable, Equatable {
        case deep, core, rem, unspecified, awake
    }

    struct Segment: Sendable, Equatable {
        let stage: Stage
        let start: Date
        let end: Date
        /// Writing app's bundle identifier. Used to keep a single source
        /// per night, so Apple Watch plus AutoSleep never double-count.
        let source: String

        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    struct Night: Sendable, Equatable {
        let start: Date
        let end: Date
        let deep: TimeInterval
        let core: TimeInterval
        let rem: TimeInterval
        let unspecified: TimeInterval
        let awake: TimeInterval

        var asleep: TimeInterval { deep + core + rem + unspecified }
        /// True when most of the night carries stages. A mostly
        /// unspecified night with a few staged minutes would otherwise be
        /// scored on a restorative share it never measured.
        var hasStages: Bool { asleep > 0 && (deep + core + rem) / asleep >= 0.5 }
    }

    // MARK: - Tuning

    static let durationWeight = 0.60
    static let restorativeWeight = 0.25
    static let continuityWeight = 0.15
    /// Deep + REM at or above this share of time asleep scores in full.
    /// Healthy adults typically spend 13–23% in deep and 20–25% in REM.
    static let restorativeTarget = 0.40
    /// Awake at or above this share of the night scores zero continuity.
    static let awakeCeiling = 0.15
    /// Segments further apart than this belong to separate sleeps.
    static let sessionGap: TimeInterval = 2 * 3600
    /// The latest session at least this long counts as "the night", so a
    /// nap after waking doesn't replace it.
    static let minimumNight: TimeInterval = 3 * 3600

    // MARK: - Public

    /// The most recent night in `segments`, or nil when nothing asleep
    /// was recorded.
    static func night(from segments: [Segment]) -> Night? {
        guard let source = dominantSource(in: segments) else { return nil }
        let sessions = split(segments.filter { $0.source == source })
        let chosen = sessions.last { asleepTime(in: $0) >= minimumNight } ?? sessions.last
        guard let chosen, asleepTime(in: chosen) > 0 else { return nil }
        return summarize(chosen)
    }

    static func score(_ night: Night, targetHours: Double) -> Int {
        guard night.asleep > 0, targetHours > 0 else { return 0 }
        let duration = min(1, night.asleep / (targetHours * 3600))
        let awakeShare = night.awake / (night.asleep + night.awake)
        let continuity = max(0, 1 - awakeShare / awakeCeiling)

        let weighted: Double
        if night.hasStages {
            let restorative = min(1, (night.deep + night.rem) / night.asleep / restorativeTarget)
            weighted = duration * durationWeight
                + restorative * restorativeWeight
                + continuity * continuityWeight
        } else {
            weighted = (duration * durationWeight + continuity * continuityWeight)
                / (durationWeight + continuityWeight)
        }
        return Int((weighted * 100).rounded())
    }

    // MARK: - Private

    private static func dominantSource(in segments: [Segment]) -> String? {
        var asleepBySource: [String: TimeInterval] = [:]
        for segment in segments where segment.stage != .awake {
            asleepBySource[segment.source, default: 0] += segment.duration
        }
        // Tie-break on the identifier: Dictionary order changes per launch.
        return asleepBySource.max {
            $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key
        }?.key
    }

    private static func split(_ segments: [Segment]) -> [[Segment]] {
        var sessions: [[Segment]] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let lastEnd = sessions.last?.map(\.end).max(),
               segment.start.timeIntervalSince(lastEnd) <= sessionGap {
                sessions[sessions.count - 1].append(segment)
            } else {
                sessions.append([segment])
            }
        }
        return sessions
    }

    private static func asleepTime(in session: [Segment]) -> TimeInterval {
        session.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
    }

    private static func summarize(_ session: [Segment]) -> Night {
        func total(_ stage: Stage) -> TimeInterval {
            session.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
        }
        return Night(
            start: session.map(\.start).min() ?? .distantPast,
            end: session.map(\.end).max() ?? .distantPast,
            deep: total(.deep),
            core: total(.core),
            rem: total(.rem),
            unspecified: total(.unspecified),
            awake: total(.awake)
        )
    }
}
