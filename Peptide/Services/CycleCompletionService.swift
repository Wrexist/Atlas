import Foundation

/// Manages the active → completed state transition for protocols whose
/// cycle window (`startDate + cycleLengthWeeks` weeks) has elapsed.
///
/// Distinct from `CycleMilestoneService` (which is about celebrating
/// milestones — share cards, social moments). This service exists to
/// **prevent stale state**: an `.active` protocol past its cycle end
/// keeps emitting scheduled dose dots on the calendar and firing
/// notifications forever. The cycle-ended protocol should either flip
/// to `.completed` (the user is done), get extended (the user is
/// continuing past the planned end), or be replaced by a new cycle.
///
/// Behaviour by phase, tied to the user's level of engagement:
/// - **Day 0 past end → Day 6 past end**: surface a prompt on every
///   launch with three options (Mark complete · Extend · Start new).
///   Each dismissal increments a counter scoped to this cycle.
/// - **Day 7+ past end OR 3 dismissals**: soft auto-complete. The
///   protocol's status flips to `.completed` automatically, with the
///   transition logged so the user can audit it later. After auto-
///   completion the prompt no longer surfaces.
///
/// Auto-completion only sets `.status = .completed`; it never deletes
/// data, never cancels logged entries, and never changes the
/// `startDate` — so the user can manually flip back to `.active` if
/// the auto-completion was premature.
@MainActor
final class CycleCompletionService {
    static let shared = CycleCompletionService()

    /// Number of dismissals after which the next launch auto-completes
    /// the protocol. Three is enough to confirm intent without
    /// trapping the user in a loop.
    static let autoCompleteDismissThreshold: Int = 3

    /// Days past cycle end after which the protocol auto-completes
    /// regardless of dismiss count. Catches the "user opens the app
    /// rarely" case without leaving stale `.active` state for weeks.
    static let autoCompleteGraceDays: Int = 7

    /// What the prompt offers when fired.
    enum Resolution {
        case markCompleted
        case extendCycle(addWeeks: Int)
        case startNewCycle
        case dismissed
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let dismissCountKey = "cycle.completion.dismissCount"
    private static let autoCompletedKey = "cycle.completion.autoCompleted"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Queries

    /// Returns the first `.active` protocol whose cycle has ended and
    /// is eligible for a completion prompt. Returns nil when nothing
    /// is due. Iterates start-date-first so the longest-running cycle
    /// surfaces before any others to keep prompt order stable.
    func pendingCompletion(in protocols: [PeptideProtocol]) -> PeptideProtocol? {
        let candidates = protocols
            .filter { $0.status == .active }
            .filter { hasCycleEnded($0) }
            .filter { !wasAutoCompleted($0) }
            .sorted { $0.startDate < $1.startDate }
        return candidates.first
    }

    /// Set of protocols that should be auto-completed on this launch:
    /// either they've crossed the dismiss threshold, or they're past
    /// the grace window. Callers (DataStore) flip the status and
    /// record via `markAutoCompleted`.
    func protocolsDueForAutoCompletion(in protocols: [PeptideProtocol]) -> [PeptideProtocol] {
        protocols.filter { proto in
            guard proto.status == .active else { return false }
            guard hasCycleEnded(proto) else { return false }
            guard !wasAutoCompleted(proto) else { return false }
            if dismissCount(for: proto) >= Self.autoCompleteDismissThreshold { return true }
            if daysPastCycleEnd(of: proto) >= Self.autoCompleteGraceDays { return true }
            return false
        }
    }

    // MARK: - State transitions

    /// Records that the user dismissed the prompt without picking an
    /// action. Counts toward the auto-completion threshold.
    func recordDismissal(for proto: PeptideProtocol) {
        let current = dismissCount(for: proto)
        var map = dismissCounts
        map[key(for: proto)] = current + 1
        persistDismissCounts(map)
    }

    /// Records that the user (or the auto-completion sweep) marked
    /// the protocol completed. Prevents the prompt from re-firing.
    func markAutoCompleted(_ proto: PeptideProtocol) {
        var set = autoCompletedIdentifiers
        set.insert(key(for: proto))
        defaults.set(Array(set), forKey: Self.autoCompletedKey)
    }

    /// Test-only reset hook.
    func resetForTesting() {
        defaults.removeObject(forKey: Self.dismissCountKey)
        defaults.removeObject(forKey: Self.autoCompletedKey)
    }

    // MARK: - Predicates

    /// True when "now" is past the cycle's end. Reads the single
    /// source of truth (`PeptideProtocol.cycleEndDay`) so the
    /// completion service and `daysRemaining` never drift —
    /// previously the local math here computed startOfDay+days, the
    /// model's `endDate` did `weekOfYear`-add on the raw startDate,
    /// and the two diverged for protocols created at non-midnight
    /// timestamps.
    private func hasCycleEnded(_ proto: PeptideProtocol) -> Bool {
        calendar.startOfDay(for: Date()) >= proto.cycleEndDay
    }

    private func daysPastCycleEnd(of proto: PeptideProtocol) -> Int {
        let today = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: proto.cycleEndDay, to: today).day ?? 0
    }

    private func dismissCount(for proto: PeptideProtocol) -> Int {
        dismissCounts[key(for: proto)] ?? 0
    }

    private func wasAutoCompleted(_ proto: PeptideProtocol) -> Bool {
        autoCompletedIdentifiers.contains(key(for: proto))
    }

    // MARK: - Persistence

    private var dismissCounts: [String: Int] {
        defaults.dictionary(forKey: Self.dismissCountKey) as? [String: Int] ?? [:]
    }

    private func persistDismissCounts(_ map: [String: Int]) {
        defaults.set(map, forKey: Self.dismissCountKey)
    }

    private var autoCompletedIdentifiers: Set<String> {
        Set(defaults.stringArray(forKey: Self.autoCompletedKey) ?? [])
    }

    /// Suppression key. Same shape as `CycleMilestoneService.key` —
    /// includes `startDate` so a stop + restart of the same protocol
    /// gets a fresh slate.
    private func key(for proto: PeptideProtocol) -> String {
        let stamp = Int(proto.startDate.timeIntervalSince1970)
        return "\(proto.id.uuidString):\(stamp)"
    }
}
