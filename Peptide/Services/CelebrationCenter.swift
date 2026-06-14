import Foundation

/// Routes the app's "big moment" celebrations through one serialized
/// queue so a single mounted host (`CelebrationHostView`) can present
/// them on any tab — confetti for a habit completion, the level-up
/// overlay when the Atlas Score crosses a level.
///
/// Clones the proven FIFO pattern from `AchievementService`
/// (`queue` / `current` / `acknowledgeCurrent`): one save can cross
/// several moments at once, and a single slot would drop all but the
/// last, so events queue and the host drains them one at a time.
///
/// Achievement-unlock celebrations are intentionally *not* routed here —
/// those stay on `AchievementService`'s own toast pipeline; the host
/// observes that separately and layers confetti on top. Keeping the two
/// queues independent avoids a bridge that has to keep them in sync.
@MainActor @Observable
final class CelebrationCenter {
    static let shared = CelebrationCenter()

    private(set) var queue: [CelebrationEvent] = []

    /// The event the host should currently present — the head of the
    /// queue. The host presents it, then calls `acknowledgeCurrent()`.
    var current: CelebrationEvent? { queue.first }

    private init() {}

    func celebrate(_ kind: CelebrationEvent.Kind) {
        queue.append(CelebrationEvent(kind: kind))
    }

    /// Advances past the presented event. Call once the host has finished
    /// showing `current`.
    func acknowledgeCurrent() {
        if !queue.isEmpty { queue.removeFirst() }
    }
}

/// A queued celebration. Carries a stable `id` so SwiftUI can key its
/// presentation transitions and `.task(id:)` re-fires per event.
struct CelebrationEvent: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind

    enum Kind: Equatable {
        /// A habit was just completed. `tintHex` colors the confetti to
        /// match the habit; `allHabitsDone` upgrades the burst when this
        /// completion finished every habit due today.
        case habitComplete(tintHex: UInt32, allHabitsDone: Bool)
        /// The Atlas Score crossed into a new level.
        case levelUp(level: Int, tierName: String, tierSymbol: String, tintHex: UInt32)
    }

    static func == (lhs: CelebrationEvent, rhs: CelebrationEvent) -> Bool {
        lhs.id == rhs.id
    }
}
