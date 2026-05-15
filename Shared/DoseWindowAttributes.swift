import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// ActivityAttributes describing the lock-screen + Dynamic Island dose
/// window. Lives in /Shared so both the app target (which starts and
/// updates the activity) and the widget extension (which renders it)
/// see the same struct.
///
/// `staticAttributes` carries everything that doesn't change for the
/// lifetime of one dose window — the peptide name, dose string, and
/// the window bounds used by the progress ring. The `ContentState`
/// carries everything the system pushes updates for — the completion
/// flag + the optional logged-at timestamp — so widgets can tween the
/// countdown and ring without the app having to push every second.
@available(iOS 16.1, *)
struct DoseWindowAttributes: ActivityAttributes {
    public typealias DoseWindowStatus = ContentState

    public struct ContentState: Codable, Hashable {
        /// Wall-clock time the dose was scheduled for. The widget
        /// renders `Text(timerInterval:)` and the ring against this
        /// without needing per-second push updates.
        public var doseTime: Date
        /// Earliest wall-clock the window opens — the progress ring's
        /// 0% anchor. Defaults on the app side to `doseTime - 30min`
        /// so the arc fills smoothly as the dose approaches.
        public var windowStart: Date
        /// True once the user marks the dose taken. Flips the live
        /// activity into a brief "Logged" confirmation before the
        /// parent app ends it.
        public var completed: Bool
        /// When the user logged the dose. Nil while the dose is still
        /// pending; set by `markCompleted` so the widget can show a
        /// "Logged at 8:14 AM" subtitle.
        public var loggedAt: Date?

        public init(
            doseTime: Date,
            windowStart: Date,
            completed: Bool,
            loggedAt: Date? = nil
        ) {
            self.doseTime = doseTime
            self.windowStart = windowStart
            self.completed = completed
            self.loggedAt = loggedAt
        }
    }

    /// Stable identifier for the originating ProtocolEntry. Used by
    /// `DoseLiveActivityService` to match active activities back to
    /// the entry the app's UI is mutating, and by the deep-link
    /// handler in `PeptideApp` to route a tap on the live activity
    /// to the matching dose-logging sheet.
    public let entryId: UUID
    /// Display label, e.g. "BPC-157".
    public let peptideAbbreviation: String
    /// Full peptide name, e.g. "BPC-157" or "Body Protection Compound".
    /// Used by the expanded Dynamic Island region which has room for
    /// the longer form.
    public let peptideName: String
    /// Dose string, e.g. "250 mcg" — pre-formatted in the app so the
    /// widget doesn't need any model dependencies.
    public let doseDisplay: String
    /// Hex string of the compound's vial palette so the widget can
    /// tint without depending on `VialPalette` (which lives in the
    /// app target).
    public let tintHex: UInt

    public init(
        entryId: UUID,
        peptideAbbreviation: String,
        peptideName: String,
        doseDisplay: String,
        tintHex: UInt
    ) {
        self.entryId = entryId
        self.peptideAbbreviation = peptideAbbreviation
        self.peptideName = peptideName
        self.doseDisplay = doseDisplay
        self.tintHex = tintHex
    }
}

// MARK: - Status state machine

@available(iOS 16.1, *)
extension DoseWindowAttributes.ContentState {

    /// Derived status the widget renders. Computed from `doseTime`,
    /// `completed`, and the current wall-clock — keeping the math in
    /// the shared layer means the lock screen and the expanded
    /// Dynamic Island read the same enum without duplicating
    /// time-offset thresholds.
    ///
    /// Access level: internal. `/Shared` is compiled into both the
    /// app and the widget-extension targets, so every member here
    /// only needs to be reachable within each compiled module —
    /// `public` would be vestigial and the compiler caps it at the
    /// (internal) enclosing struct anyway.
    enum Status: Equatable {
        /// More than 5 minutes before `doseTime`. Carries the
        /// rounded minute count so the widget can render "in 12 min"
        /// without re-doing the math.
        case upcoming(minutesUntil: Int)
        /// Within ±5 minutes of `doseTime`. The "take it now" beat —
        /// the live activity flips to its primary action state.
        case dueNow
        /// More than 5 minutes past `doseTime`. Carries the rounded
        /// minute count of how late the user is so the widget can
        /// render "8 min late".
        case late(minutes: Int)
        /// User has marked the dose taken. Terminal state — the
        /// service will dismiss the activity a few seconds after.
        case completed
    }

    /// Window after which a dose flips from "due now" into "late".
    /// 5 minutes is wide enough to catch the natural "I'll do it in
    /// a moment" pause without showing a red badge the second the
    /// scheduled time hits.
    static let dueNowToleranceMinutes: Int = 5

    /// Resolves the current status against `now`. Pure — same input
    /// always yields the same output so the widget renders are
    /// deterministic and unit-testable.
    func status(at now: Date = Date()) -> Status {
        if completed { return .completed }
        let delta = doseTime.timeIntervalSince(now)
        let minutes = Int((abs(delta) / 60).rounded())
        if delta > Double(Self.dueNowToleranceMinutes * 60) {
            return .upcoming(minutesUntil: minutes)
        }
        if delta < -Double(Self.dueNowToleranceMinutes * 60) {
            return .late(minutes: minutes)
        }
        return .dueNow
    }

    /// 0…1 fraction of progress through the active window. Drives
    /// the ring fill on the lock screen and the expanded Dynamic
    /// Island. Clamped to [0,1] so the visual never overshoots once
    /// the user is past the scheduled time.
    func windowProgress(at now: Date = Date()) -> Double {
        if completed { return 1.0 }
        let total = doseTime.timeIntervalSince(windowStart)
        guard total > 0 else { return 1.0 }
        let elapsed = now.timeIntervalSince(windowStart)
        return min(max(elapsed / total, 0), 1)
    }
}
#endif
