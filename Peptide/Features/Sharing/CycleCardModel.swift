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
    var healthSummary: HealthSummary?

    /// True when `currentStreakDays` is the user's app-wide streak shown on
    /// a single protocol's card, so the label says so.
    var streakIsOverall = false

    struct HealthSummary: Equatable {
        let weightDeltaKg: Double?
        let avgSleepHours: Double?
        let hrvTrendDescription: String?
        /// The sharer's display unit for `weightDeltaKg`.
        var weightUnit: MeasurementUnit = .metric

        /// Nothing to draw: the card would carry a bare heading.
        var isEmpty: Bool {
            weightDeltaKg == nil && avgSleepHours == nil && hrvTrendDescription == nil
        }
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
            healthSummary: healthSummary,
            streakIsOverall: true
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
        let stats = stackStats(protocols: dataStore.activeProtocols, entries: dataStore.entries)
        return CycleCardModel(
            subjectTitle: String(localized: "My Protocol"),
            peptides: dataStore.stackPeptides,
            activeSinceDate: start,
            cycleDay: cycleDay(from: start),
            cycleTotalDays: (anchor?.safeCycleLengthWeeks ?? 1) * 7,
            dosesLogged: stats.dosesLogged,
            adherencePercent: stats.adherencePercent,
            currentStreakDays: dataStore.currentStreak,
            healthSummary: healthSummary
        )
    }

    /// Doses and adherence scoped to the stack the card shows: completed
    /// doses of `protocols` only, and their due/completed counts pooled
    /// with the per-protocol card's definition — each protocol from its
    /// own start, a scheduled day without a logged dose counting as missed.
    static func stackStats(
        protocols: [PeptideProtocol],
        entries: [ProtocolEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (dosesLogged: Int, adherencePercent: Int) {
        let ids = Set(protocols.map(\.id))
        let logged = entries.filter { ids.contains($0.protocolId) && $0.completed }.count
        let counts = protocols.map { proto in
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: proto.startDate),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            return proto.adherenceCounts(entries: entries, days: max(1, days + 1), now: now, calendar: calendar)
        }
        let due = counts.reduce(0) { $0 + $1.due }
        let completed = counts.reduce(0) { $0 + $1.completed }
        let percent = due > 0 ? Int((Double(completed) / Double(due) * 100).rounded()) : 0
        return (logged, percent)
    }

    // MARK: - Card text

    /// "A", "B", … for the masked vial at `index`.
    static func maskLetter(_ index: Int) -> String {
        String(Character(UnicodeScalar(UInt8(65 + index))))
    }

    static func maskedCompoundName(_ index: Int) -> String {
        String(localized: "Compound \(maskLetter(index))")
    }

    /// Protocols are often named after their compounds ("BPC-157 +
    /// TB-500"), so the mask hides the title as well as the vials.
    func displayTitle(maskCompoundNames: Bool) -> String {
        maskCompoundNames ? String(localized: "My Protocol") : subjectTitle
    }

    var activeSinceFormatted: String {
        activeSinceDate.formatted(.dateTime.month(.wide).day().year())
    }

    /// "Day 0 of 84" read as a broken counter for a protocol that
    /// hasn't begun, and "Day 120 of 84" for one past its length; name
    /// the start date or the completed cycle instead.
    var cycleProgressLine: String {
        guard cycleDay > 0 else { return String(localized: "Starts \(activeSinceFormatted)") }
        guard cycleDay <= cycleTotalDays else {
            return String(localized: "Cycle complete · \(cycleTotalDays) days")
        }
        return String(localized: "Day \(cycleDay) of \(cycleTotalDays) cycle")
    }

    var streakValue: String {
        currentStreakDays == 1 ? String(localized: "1 day") : String(localized: "\(currentStreakDays) days")
    }

    var streakTitle: String {
        streakIsOverall ? String(localized: "Overall streak") : String(localized: "Streak")
    }

    /// What the card says, for VoiceOver — on the card itself and on the
    /// rendered preview, whose pixels carry none of it. Honours the mask:
    /// a sighted user sees "Compound A / B", so VoiceOver must not read
    /// the real abbreviations (audit Sharing P2).
    func spokenSummary(maskCompoundNames: Bool) -> String {
        let names = maskCompoundNames
            ? peptides.indices.map(Self.maskedCompoundName).joined(separator: ", ")
            : peptides.map(\.abbreviation).joined(separator: ", ")
        return String(localized: "\(displayTitle(maskCompoundNames: maskCompoundNames)) cycle card. \(cycleProgressLine). ") +
               String(localized: "Peptides: \(names). ") +
               String(localized: "Doses logged: \(dosesLogged). Adherence: \(adherencePercent) percent. ") +
               String(localized: "\(streakTitle): \(streakValue). Watermark: Atlas.")
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
