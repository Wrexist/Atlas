import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// ActivityAttributes describing the lock-screen + Dynamic Island dose
/// window. Lives in /Shared so both the app target (which starts and
/// updates the activity) and the widget extension (which renders it)
/// see the same struct.
///
/// `staticAttributes` carries everything that doesn't change for the
/// lifetime of one dose window — the peptide name + dose string. The
/// `ContentState` carries everything the system pushes updates for —
/// the seconds remaining + completion flag — so widgets can tween the
/// countdown without the app having to push every second.
@available(iOS 16.1, *)
struct DoseWindowAttributes: ActivityAttributes {
    public typealias DoseWindowStatus = ContentState

    public struct ContentState: Codable, Hashable {
        /// Wall-clock time the dose was scheduled for. The widget
        /// renders Text(timerInterval:) against this to drive the
        /// countdown without requiring per-second push updates.
        public var doseTime: Date
        /// True once the user marks the dose taken. Flips the live
        /// activity into a brief "Logged" state before being dismissed
        /// from the parent app via `end(_:)`.
        public var completed: Bool

        public init(doseTime: Date, completed: Bool) {
            self.doseTime = doseTime
            self.completed = completed
        }
    }

    /// Stable identifier for the originating ProtocolEntry. Used by
    /// `DoseLiveActivityService` to match active activities back to
    /// the entry the app's UI is mutating.
    public let entryId: UUID
    /// Display label, e.g. "BPC-157".
    public let peptideAbbreviation: String
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
        doseDisplay: String,
        tintHex: UInt
    ) {
        self.entryId = entryId
        self.peptideAbbreviation = peptideAbbreviation
        self.doseDisplay = doseDisplay
        self.tintHex = tintHex
    }
}
#endif
