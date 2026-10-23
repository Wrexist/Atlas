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
        /// The sharer's display unit for `weightDeltaKg`.
        var weightUnit: MeasurementUnit = .metric
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
        // Per-protocol card uses the protocol-scoped adherence so the
        // shared "75%" figure reflects this stack — not the user's
        // global average across every protocol they run (audit
        // Sharing P1.6).
        let adherence = dataStore.adherence(forProtocol: proto.id)
        return CycleCardModel(
            subjectTitle: proto.name,
            peptides: proto.peptides,
            activeSinceDate: proto.startDate,
            cycleDay: cycleDay(from: proto.startDate),
            cycleTotalDays: proto.safeCycleLengthWeeks * 7,
            dosesLogged: logged,
            adherencePercent: Int((adherence * 100).rounded()),
            currentStreakDays: dataStore.currentStreak,
            healthSummary: healthSummary
        )
    }

    /// Builds a stack-level model summarising every active protocol. The
    /// card is anchored on the earliest-started protocol so the "active
    /// since" date shows the user's overall journey, and the day and cycle
    /// length come from that same protocol so the counter can't mix one
    /// protocol's start with another's cycle.
    @MainActor
    static func forStack(
        in dataStore: DataStore,
        healthSummary: HealthSummary? = nil
    ) -> CycleCardModel {
        let anchor = dataStore.activeProtocols.min { $0.startDate < $1.startDate }
        let start = anchor?.startDate ?? Date()
        return CycleCardModel(
            subjectTitle: String(localized: "My Protocol"),
            peptides: dataStore.stackPeptides,
            activeSinceDate: start,
            cycleDay: cycleDay(from: start),
            cycleTotalDays: (anchor?.safeCycleLengthWeeks ?? 1) * 7,
            dosesLogged: dataStore.entries.filter(\.completed).count,
            adherencePercent: Int((dataStore.averageCompliance * 100).rounded()),
            currentStreakDays: dataStore.currentStreak,
            healthSummary: healthSummary
        )
    }

    /// 1-based calendar day of a cycle that began on `start`, counted
    /// between start-of-day boundaries so a late-evening start is day 2
    /// the next morning. 0 for a cycle that hasn't begun, so the card can
    /// name the start date instead. Not capped at the cycle length — the
    /// card reads an overrun as a completed cycle.
    static func cycleDay(from start: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        guard startDay <= today else { return 0 }
        return (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1
    }
}
