import Foundation

/// One open fast reduced to the two instants every glanceable surface
/// draws from: the Live Activity, the Dynamic Island and the fasting
/// widget. Lives in /Shared so the widget extension, which can't see
/// `FastSession` or `FastingEngine`, does the same arithmetic the app
/// does. Every value is an absolute interval between two dates, so a
/// fast that spans a DST change still reads its true length.
struct FastingWindow: Codable, Hashable, Sendable {
    let startedAt: Date
    let targetEnd: Date

    /// The fast's goal length. Zero if `targetEnd` somehow precedes the
    /// start, rather than a negative length that would invert a range.
    var targetDuration: TimeInterval { max(0, targetEnd.timeIntervalSince(startedAt)) }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }

    /// Time left to the goal; zero once it's reached.
    func remaining(at now: Date) -> TimeInterval {
        max(0, targetEnd.timeIntervalSince(now))
    }

    /// 0…1 toward the goal; 1 once it's reached or for a zero-length goal.
    func progress(at now: Date) -> Double {
        guard targetDuration > 0 else { return 1 }
        return min(1, elapsed(at: now) / targetDuration)
    }

    func isGoalReached(at now: Date) -> Bool { now >= targetEnd }

    /// The goal as a range, for a `ProgressView(timerInterval:)` ring the
    /// system fills on its own between pushes. Bounds ordered so a
    /// malformed window can't trap the range initialiser.
    var goalInterval: ClosedRange<Date> { startedAt...max(startedAt, targetEnd) }

    /// Range for `Text(timerInterval:countsDown: true)`, which stops at
    /// 0:00 on the goal instead of counting back up. Starts at `now`,
    /// clamped, so the text shows the true time left.
    func countdownInterval(from now: Date) -> ClosedRange<Date> {
        min(now, targetEnd)...targetEnd
    }

    /// How far `Text(timerInterval:countsDown: false)` keeps counting up.
    /// Well past the 72-hour longest goal the tracker allows.
    static let elapsedCeiling: TimeInterval = 7 * 24 * 3600

    /// Range for an elapsed clock that counts up from the start with no
    /// pushes at all.
    var elapsedInterval: ClosedRange<Date> {
        startedAt...startedAt.addingTimeInterval(Self.elapsedCeiling)
    }

    /// Instants a widget timeline should redraw at: every `step` from
    /// `now`, `count` of them, so the progress bar and the minutes on the
    /// circular gauge move, plus the goal itself when it falls inside
    /// that span, so the widget flips to "Goal reached" on time.
    func timelineDates(from now: Date, step: TimeInterval = 15 * 60, count: Int = 16) -> [Date] {
        guard step > 0, count > 0 else { return [now] }
        let steps = (0..<count).map { now.addingTimeInterval(Double($0) * step) }
        guard let last = steps.last, targetEnd > now, targetEnd < last, !steps.contains(targetEnd) else { return steps }
        return (steps + [targetEnd]).sorted()
    }
}

#if canImport(ActivityKit)
import ActivityKit

/// ActivityAttributes for the fast in progress. Lives in /Shared so the
/// app target (which starts, updates and ends the activity) and the
/// widget extension (which renders it) see the same struct — the
/// arrangement `WorkoutActivityAttributes` uses.
///
/// The protocol name ("16:8") is fixed for a fast's life. The start is
/// not — the user can move it back to when they actually stopped eating
/// — so the start and the goal live in `ContentState`, where an update
/// can reach them.
@available(iOS 16.1, *)
struct FastingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAt: Date
        public var targetEnd: Date
        /// Set when the fast ends. Flips the activity into a short
        /// summary beat before it dismisses itself.
        public var endedAt: Date?

        public init(startedAt: Date, targetEnd: Date, endedAt: Date? = nil) {
            self.startedAt = startedAt
            self.targetEnd = targetEnd
            self.endedAt = endedAt
        }
    }

    /// The originating `FastSession`, so the service and the End fast
    /// button can match an open activity back to its fast.
    public let fastId: UUID
    /// Pre-resolved app-side ("16:8", "OMAD") so the widget needs no
    /// model types.
    public let protocolName: String

    public init(fastId: UUID, protocolName: String) {
        self.fastId = fastId
        self.protocolName = protocolName
    }
}

// MARK: - Status state machine

@available(iOS 16.1, *)
extension FastingActivityAttributes.ContentState {

    /// What the activity renders, so the lock screen and every island
    /// presentation read one enum.
    enum Status: Equatable {
        /// Still short of the goal.
        case fasting
        /// Past the goal and still fasting.
        case goalReached
        /// Terminal. The activity dismisses shortly after.
        case ended
    }

    var window: FastingWindow { FastingWindow(startedAt: startedAt, targetEnd: targetEnd) }

    /// Pure: same inputs, same answer, so it's testable without
    /// ActivityKit in the loop.
    func status(at now: Date = Date()) -> Status {
        if endedAt != nil { return .ended }
        return window.isGoalReached(at: now) ? .goalReached : .fasting
    }

    /// The goal while it's still ahead: a Live Activity only redraws on
    /// a push or at its stale date, so this is what moves a suspended
    /// app's activity into "Goal reached". Nil after that, since nothing
    /// changes again until the user ends the fast.
    func staleDate(now: Date = Date()) -> Date? {
        targetEnd > now ? targetEnd : nil
    }
}
#endif
