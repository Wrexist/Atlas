import Foundation

/// Decides when to nudge the user to share a cycle snapshot card. The
/// spec calls for three milestones — Day 7, Day 30, and "cycle marked
/// complete" — and explicitly wants each prompt to fire at most once
/// per (protocol × milestone) so the user isn't badgered every time
/// they land on Home.
///
/// Suppression state lives in UserDefaults keyed by protocol ID +
/// milestone so a re-launched app remembers prior prompts. The service
/// is decision-only; the actual sheet presentation is handled by the
/// caller (currently `HomeView`).
@MainActor
final class CycleMilestoneService {
    static let shared = CycleMilestoneService()

    enum Milestone: String, CaseIterable {
        case day7
        case day30
        case completed

        /// Copy surfaced on the prompt sheet. Kept short so the modal
        /// title sits comfortably on a single line at every Dynamic
        /// Type setting.
        var prompt: String {
            switch self {
            case .day7:      "Share your week 1 snapshot?"
            case .day30:     "Share your 30-day protocol card?"
            case .completed: "You finished a cycle! Share your results?"
            }
        }
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private static let storageKey = "cycle.milestone.shown"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    /// Returns the next milestone the caller should prompt about for
    /// `protocols`, or nil when nothing is due. Iterates each protocol
    /// in start-date order so the most-progressed cycle's prompt
    /// surfaces first; only the first eligible match returns to keep
    /// HomeView from stacking modals.
    func pendingMilestone(in protocols: [PeptideProtocol]) -> (proto: PeptideProtocol, milestone: Milestone)? {
        let sorted = protocols.sorted { $0.startDate < $1.startDate }
        for proto in sorted {
            guard proto.status != .paused else { continue }
            for milestone in Milestone.allCases {
                guard !hasShown(milestone, for: proto.id) else { continue }
                guard isDue(milestone, for: proto) else { continue }
                return (proto, milestone)
            }
        }
        return nil
    }

    /// Records that a milestone prompt was surfaced — call this whether
    /// the user shared, dismissed, or skipped. Suppresses re-prompts.
    func markShown(_ milestone: Milestone, for protocolID: UUID) {
        var current = shownIdentifiers
        current.insert(key(milestone, protocolID: protocolID))
        defaults.set(Array(current), forKey: Self.storageKey)
    }

    /// Test-only reset hook so the suppression list doesn't carry across
    /// XCTest invocations. Internal so production code can't poke it.
    func resetForTesting() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Predicates

    private func isDue(_ milestone: Milestone, for proto: PeptideProtocol) -> Bool {
        switch milestone {
        case .day7:      return daysSinceStart(of: proto) >= 7
        case .day30:     return daysSinceStart(of: proto) >= 30
        case .completed: return proto.status == .completed
        }
    }

    private func daysSinceStart(of proto: PeptideProtocol) -> Int {
        let start = calendar.startOfDay(for: proto.startDate)
        let today = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: start, to: today).day ?? 0
    }

    private func hasShown(_ milestone: Milestone, for protocolID: UUID) -> Bool {
        shownIdentifiers.contains(key(milestone, protocolID: protocolID))
    }

    private var shownIdentifiers: Set<String> {
        Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    private func key(_ milestone: Milestone, protocolID: UUID) -> String {
        "\(protocolID.uuidString):\(milestone.rawValue)"
    }
}
