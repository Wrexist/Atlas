import Foundation

/// Snapshot of everything the cycle-share card needs to render. Computed
/// upstream so the SwiftUI view stays a pure function of its input —
/// `ImageRenderer` then captures it deterministically without pulling
/// `DataStore` into the view tree.
///
/// The `subjectTitle` and `peptides` make the card flexible enough to
/// represent either a single protocol (per-protocol share from the
/// Protocols tab) or the user's entire active stack (Profile-tab
/// "Share my cycle card" entry point) without branching the layout.
struct CycleCardModel {
    /// Top-bar subtitle, e.g. "My Protocol" for the Profile-tab path or
    /// the protocol's name for a per-protocol share.
    let subjectTitle: String

    /// Compounds rendered as vials. Caller is responsible for capping —
    /// the view trims at `maxVisibleVials` and surfaces "+N more".
    let peptides: [Peptide]

    let activeSinceDate: Date
    let cycleDay: Int
    let cycleTotalDays: Int

    let dosesLogged: Int
    let adherencePercent: Int
    let currentStreakDays: Int

    /// Optional health summary surfaced only when the user explicitly
    /// flips the "detailed card" toggle in the share preview *and* has
    /// granted Apple Health read access. Off by default, never bundles
    /// injection-site detail (per the spec's privacy guarantees).
    let healthSummary: HealthSummary?

    struct HealthSummary: Equatable {
        let weightDeltaKg: Double?
        let avgSleepHours: Double?
        let hrvTrendDescription: String?
    }
}

extension CycleCardModel {

    /// Builds a per-protocol model from the data store's existing stats.
    /// Used by the per-protocol share entry points (Protocols list, the
    /// detail screen). The subject title is the protocol name so the
    /// card reads "[Protocol Name]" in the top-bar slot.
    @MainActor
    static func forProtocol(
        _ proto: PeptideProtocol,
        in dataStore: DataStore,
        healthSummary: HealthSummary? = nil
    ) -> CycleCardModel {
        let logged = dataStore.entries
            .filter { $0.protocolId == proto.id && $0.completed }
            .count
        return CycleCardModel(
            subjectTitle: proto.name,
            peptides: proto.peptides,
            activeSinceDate: proto.startDate,
            cycleDay: cycleDay(for: proto),
            cycleTotalDays: max(1, proto.cycleLengthWeeks * 7),
            dosesLogged: logged,
            adherencePercent: Int((dataStore.averageCompliance * 100).rounded()),
            currentStreakDays: dataStore.currentStreak,
            healthSummary: healthSummary
        )
    }

    /// Builds a stack-level model summarising every active protocol. The
    /// "active since" date is the earliest `startDate` across the active
    /// set so the card represents the user's overall journey rather than
    /// any one protocol.
    @MainActor
    static func forStack(
        in dataStore: DataStore,
        healthSummary: HealthSummary? = nil
    ) -> CycleCardModel {
        let active = dataStore.activeProtocols
        let earliestStart = active.map(\.startDate).min() ?? Date()
        let longestCycle = active.map { max(1, $0.cycleLengthWeeks * 7) }.max() ?? 1
        // A protocol with a future startDate (scheduled to begin tomorrow)
        // would otherwise show "Day 1 of N" — misleading. Render day 0
        // when the cycle hasn't started yet so the view can downgrade the
        // copy to "Starts soon" if it wants to.
        let raw = Calendar.current.dateComponents([.day], from: earliestStart, to: Date()).day ?? 0
        let cycleDay = max(0, raw + 1)
        return CycleCardModel(
            subjectTitle: "My Protocol",
            peptides: dataStore.stackPeptides,
            activeSinceDate: earliestStart,
            cycleDay: cycleDay,
            cycleTotalDays: longestCycle,
            dosesLogged: dataStore.entries.filter(\.completed).count,
            adherencePercent: Int((dataStore.averageCompliance * 100).rounded()),
            currentStreakDays: dataStore.currentStreak,
            healthSummary: healthSummary
        )
    }

    private static func cycleDay(for proto: PeptideProtocol) -> Int {
        let start = Calendar.current.startOfDay(for: proto.startDate)
        let today = Calendar.current.startOfDay(for: Date())
        return max(1, (Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
    }
}
