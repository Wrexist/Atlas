import Foundation

/// Builds a per-day plan from today's `ProtocolEntry` list:
/// - Groups doses into time-of-day slots (morning fasted, post-workout, pre-bed, …).
/// - Orders doses within each slot so fasted/critical-timing peptides go first.
/// - Surfaces researched pairings (e.g. CJC-1295 + Ipamorelin).
/// - Flags same-day conflicts (intranasal spacing, GHS-R/GHRH receptor overlap,
///   GLP-1 stacking, IGF-1 stacking, hepatic load).
///
/// The engine is pure and deterministic — no I/O, no side effects — so it's easy
/// to unit-test and safe to call on every view update.
enum DailyScheduleEngine {

    // MARK: - Slots

    enum DaySlot: Int, CaseIterable, Comparable, Hashable {
        case morningFasted
        /// Clock-derived morning: no fasted claim without timing data.
        case morning
        case morningWithFood
        case midday
        case preWorkout
        case postWorkout
        case evening
        case preBed

        var title: String {
            switch self {
            case .morningFasted:    return String(localized: "Morning · Fasted")
            case .morning:          return String(localized: "Morning")
            case .morningWithFood:  return String(localized: "Morning · With Food")
            case .midday:           return String(localized: "Midday")
            case .preWorkout:       return "Pre-Workout"
            case .postWorkout:      return "Post-Workout"
            case .evening:          return String(localized: "Evening")
            case .preBed:           return String(localized: "Before Bed")
            }
        }

        var iconName: String {
            switch self {
            case .morningFasted:    return "sunrise.fill"
            case .morning:          return "sun.horizon.fill"
            case .morningWithFood:  return "fork.knife"
            case .midday:           return "sun.max.fill"
            case .preWorkout:       return "figure.run"
            case .postWorkout:      return "figure.cooldown"
            case .evening:          return "sunset.fill"
            case .preBed:           return "moon.stars.fill"
            }
        }

        var caption: String {
            switch self {
            case .morningFasted:    return String(localized: "On waking, empty stomach")
            case .morning:          return String(localized: "Early in the day")
            case .morningWithFood:  return String(localized: "After breakfast")
            case .midday:           return "Mid-day"
            case .preWorkout:       return String(localized: "30–45 min before training")
            case .postWorkout:      return String(localized: "Within 30 min of training")
            case .evening:          return String(localized: "Late afternoon / evening")
            case .preBed:           return String(localized: "30–60 min before sleep")
            }
        }

        static func < (lhs: DaySlot, rhs: DaySlot) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Maps the timing window vocabulary used in PeptideTimingData to a
        /// concrete day slot. `.anyTime` returns nil so the caller can fall
        /// back to the entry's clock time.
        static func from(_ window: PeptideTimingData.TimingWindow) -> DaySlot? {
            switch window {
            case .morningFasted:   return .morningFasted
            case .morningWithFood: return .morningWithFood
            case .preworkout:      return .preWorkout
            case .postWorkout:     return .postWorkout
            case .evening:         return .evening
            case .preBed:          return .preBed
            case .anyTime:         return nil
            }
        }

        /// Classifies a clock time into a coarse slot when no peptide-specific
        /// timing is available. Conservative bands — leaves "fasted" assertions
        /// to the timing knowledge base.
        static func from(hour: Int) -> DaySlot {
            switch hour {
            // A 0–5 AM dose maps to `.preBed`, not `.evening` — mapping
            // it to `.evening` collided with the 16–20 band, so a 2 AM
            // and a 6 PM dose landed in the same slot and got analysed
            // as co-administered (spurious conflict/combination hints).
            case 0..<5:    return .preBed
            case 5..<10:   return .morning
            case 10..<12:  return .morningWithFood
            case 12..<16:  return .midday
            case 16..<20:  return .evening
            default:       return .preBed
            }
        }
    }

    // MARK: - Hints

    struct CombinationHint: Hashable {
        let withAbbreviation: String
        let synergy: String
    }

    struct ConflictHint: Hashable {
        enum Severity: Int, Comparable {
            case info, caution, danger
            static func < (lhs: Severity, rhs: Severity) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        let severity: Severity
        let title: String
        let detail: String
        let counterpart: String?
    }

    /// Order-independent pair used to dedupe symmetrical hints
    /// ({"BPC-157", "TB-500"} == {"TB-500", "BPC-157"}).
    private struct UnorderedPair: Hashable {
        let a: String
        let b: String

        init(_ x: String, _ y: String) {
            if x <= y {
                self.a = x; self.b = y
            } else {
                self.a = y; self.b = x
            }
        }
    }

    // MARK: - Plan

    struct PlannedDose: Identifiable, Hashable {
        var id: UUID { entry.id }
        let entry: ProtocolEntry
        let order: Int
        let slot: DaySlot
        let timingNote: String
        let mustBeFasted: Bool
        let combinations: [CombinationHint]
        let conflicts: [ConflictHint]
    }

    struct ScheduledSlot: Identifiable, Hashable {
        var id: DaySlot { slot }
        let slot: DaySlot
        let doses: [PlannedDose]
    }

    struct DailyPlan {
        let slots: [ScheduledSlot]
        let totalDoses: Int

        var hasAny: Bool { totalDoses > 0 }

        /// Counts unique (peptide, counterpart) conflict pairs so the badge
        /// shows pairs, not per-dose chips (which would double for symmetrical
        /// warnings like Semax↔Selank spacing). Informational notes such as
        /// "Stay fasted" aren't conflicts and don't count.
        var conflictCount: Int {
            var pairs = Set<UnorderedPair>()
            var unpaired = 0
            for slot in slots {
                for dose in slot.doses {
                    for conflict in dose.conflicts where conflict.severity > .info {
                        if let counterpart = conflict.counterpart {
                            pairs.insert(UnorderedPair(dose.entry.peptide.abbreviation, counterpart))
                        } else {
                            unpaired += 1
                        }
                    }
                }
            }
            return pairs.count + unpaired
        }

        /// Counts unique co-injection pairs (BPC-157↔TB-500 = 1 pair).
        var combinationCount: Int {
            var pairs = Set<UnorderedPair>()
            for slot in slots {
                for dose in slot.doses {
                    for combo in dose.combinations {
                        pairs.insert(UnorderedPair(dose.entry.peptide.abbreviation, combo.withAbbreviation))
                    }
                }
            }
            return pairs.count
        }

        /// Short, user-facing summary used as the card subtitle.
        /// Phrased around the next dose still to take, so a logged morning
        /// dose doesn't keep leading the evening.
        var headline: String {
            let doses = slots.flatMap(\.doses)
            guard !doses.isEmpty else { return String(localized: "Nothing scheduled today") }
            guard let first = doses.first(where: { !$0.entry.completed }) else {
                return String(localized: "All doses logged today")
            }
            let abbrev = first.entry.peptide.abbreviation
            switch first.slot {
            case .morningFasted where first.mustBeFasted:
                return String(localized: "Start with \(abbrev) — fasted, on waking")
            case .morningFasted:
                return String(localized: "Start with \(abbrev) on waking")
            case .preBed:
                return String(localized: "End the day with \(abbrev) before bed")
            case .postWorkout:
                return String(localized: "Take \(abbrev) right after training")
            case .preWorkout:
                return String(localized: "Take \(abbrev) before training")
            default:
                return String(localized: "Begin with \(abbrev) at \(Self.shortTime(first.entry.date))")
            }
        }

        var summary: String {
            let slotCount = slots.count
            var parts: [String] = []
            parts.append(String(localized: "\(totalDoses) doses across \(slotCount) windows"))
            if combinationCount > 0 {
                parts.append(String(localized: "\(combinationCount) research pairings"))
            }
            if conflictCount > 0 {
                parts.append(String(localized: "\(conflictCount) timing notes"))
            }
            return parts.joined(separator: " · ")
        }

        private static func shortTime(_ date: Date) -> String {
            date.formatted(.dateTime.hour().minute())
        }
    }

    // MARK: - Public API

    /// Builds a fully-ordered plan from today's entries. `calendar` reads
    /// each dose's clock hour; tests pass a fixed one.
    static func plan(for entries: [ProtocolEntry], calendar: Calendar = .current) -> DailyPlan {
        guard !entries.isEmpty else {
            return DailyPlan(slots: [], totalDoses: 0)
        }

        let assignments: [(entry: ProtocolEntry, slot: DaySlot, fasted: Bool, note: String)] = entries.map { entry in
            let info = PeptideTimingData.timingRecommendations[entry.peptide.abbreviation]
            let placement = resolveSlot(for: entry, timing: info, calendar: calendar)
            let fasted = info?.preferredWindows.contains(.morningFasted) == true
                && (info?.notes.lowercased().contains("fasted") == true
                    || info?.notes.lowercased().contains("empty stomach") == true)
            let usualWindow = placement.usualSlot.map { String(localized: "Usually taken: \($0.title).") }
            let note = [usualWindow, info?.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return (entry, placement.slot, fasted, note)
        }

        let grouped = Dictionary(grouping: assignments, by: \.slot)

        let scheduled: [ScheduledSlot] = grouped.keys.sorted().map { slot in
            let bucket = grouped[slot] ?? []
            let abbrevsInSlot = bucket.map(\.entry.peptide.abbreviation)
            let ordered = orderWithinSlot(bucket)
            // One "Stay fasted" note per window, on its first fasted dose.
            let firstFastedID = ordered.first(where: \.fasted)?.entry.id

            let doses: [PlannedDose] = ordered.enumerated().map { index, item in
                let combinations = combinationHints(
                    for: item.entry.peptide.abbreviation,
                    others: abbrevsInSlot
                )
                let conflicts = conflictHints(
                    for: item.entry.peptide.abbreviation,
                    others: abbrevsInSlot,
                    timing: PeptideTimingData.timingRecommendations[item.entry.peptide.abbreviation],
                    noteFasted: item.entry.id == firstFastedID
                )
                return PlannedDose(
                    entry: item.entry,
                    order: index + 1,
                    slot: slot,
                    timingNote: item.note,
                    mustBeFasted: item.fasted,
                    combinations: combinations,
                    conflicts: conflicts
                )
            }

            return ScheduledSlot(slot: slot, doses: doses)
        }

        return DailyPlan(slots: scheduled, totalDoses: entries.count)
    }

    // MARK: - Slot resolution

    /// The dose's clock time decides its slot — the user's schedule is the
    /// truth, so the list keeps clock order and only doses that really share
    /// a window are analysed together. A morning dose takes the peptide's
    /// own morning window so knowledge-base timing (fasted or with food)
    /// shows. `usualSlot` names the preferred window when the schedule
    /// sits outside every one of them.
    private static func resolveSlot(
        for entry: ProtocolEntry,
        timing: PeptideTimingData.PeptideTiming?,
        calendar: Calendar
    ) -> (slot: DaySlot, usualSlot: DaySlot?) {
        let clockSlot = DaySlot.from(hour: calendar.component(.hour, from: entry.date))
        let preferred = (timing?.preferredWindows ?? []).compactMap(DaySlot.from(_:)).sorted()
        if clockSlot == .morning,
           let morning = preferred.first(where: { $0 == .morningFasted || $0 == .morningWithFood }) {
            return (morning, nil)
        }
        if preferred.isEmpty || preferred.contains(clockSlot) {
            return (clockSlot, nil)
        }
        return (clockSlot, preferred.first)
    }

    // MARK: - Ordering within a slot

    private static func orderWithinSlot(
        _ items: [(entry: ProtocolEntry, slot: DaySlot, fasted: Bool, note: String)]
    ) -> [(entry: ProtocolEntry, slot: DaySlot, fasted: Bool, note: String)] {
        items.sorted { a, b in
            // 1. Fasted first — protect the empty-stomach window from later doses.
            if a.fasted != b.fasted { return a.fasted && !b.fasted }
            // 2. Validated co-injection partners next: GHRH analog before GHRP
            //    so the reader sees them as a paired step. Order is stable for
            //    pairs that don't match the rule.
            let aPriority = pathwayPriority(a.entry.peptide.abbreviation)
            let bPriority = pathwayPriority(b.entry.peptide.abbreviation)
            if aPriority != bPriority { return aPriority < bPriority }
            // 3. Earlier scheduled time first.
            if a.entry.date != b.entry.date { return a.entry.date < b.entry.date }
            // 4. Stable: alphabetical by abbreviation.
            return a.entry.peptide.abbreviation < b.entry.peptide.abbreviation
        }
    }

    /// Lower number = earlier in the slot. Pulls GHRH analogs ahead of GHRPs
    /// when both appear together; everything else lands in the middle.
    private static func pathwayPriority(_ abbreviation: String) -> Int {
        let ghrh: Set<String> = ["CJC-1295 DAC", "Mod GRF 1-29", "Sermorelin", "Tesamorelin"]
        let ghrp: Set<String> = ["Ipamorelin", "GHRP-2", "GHRP-6", "Hexarelin"]
        if ghrh.contains(abbreviation) { return 10 }
        if ghrp.contains(abbreviation) { return 11 }
        return 50
    }

    // MARK: - Combinations

    /// Validated stacks where this peptide and another peptide also dosed in
    /// the same slot share a research-backed synergy.
    private static func combinationHints(
        for abbreviation: String,
        others: [String]
    ) -> [CombinationHint] {
        let companions = Set(others).subtracting([abbreviation])
        guard !companions.isEmpty else { return [] }

        var hints: [CombinationHint] = []
        var seenPairs = Set<String>()

        for stack in PeptideCompatibilityData.validatedStacks {
            let abbrevs = Set(stack.peptideAbbreviations)
            guard abbrevs.contains(abbreviation) else { continue }
            let intersection = abbrevs.intersection(companions)
            for partner in intersection where !seenPairs.contains(partner) {
                seenPairs.insert(partner)
                hints.append(CombinationHint(
                    withAbbreviation: partner,
                    synergy: stack.synergy
                ))
            }
        }
        return hints
    }

    // MARK: - Conflicts

    private static func conflictHints(
        for abbreviation: String,
        others: [String],
        timing: PeptideTimingData.PeptideTiming?,
        noteFasted: Bool
    ) -> [ConflictHint] {
        var hints: [ConflictHint] = []
        let companions = Array(Set(others).subtracting([abbreviation]))

        // Per-peptide explicit "avoid co-administration" list — typically
        // intranasals that compete for nasal mucosa absorption.
        if let avoid = timing?.avoidWith {
            for partner in avoid where companions.contains(partner) {
                hints.append(ConflictHint(
                    severity: .caution,
                    title: String(localized: "Separate from \(partner) by 15+ min"),
                    detail: String(localized: "Both are intranasal — back-to-back administration reduces absorption of the second peptide."),
                    counterpart: partner
                ))
            }
        }

        // Known pair-level interactions from the compatibility database.
        // `Interaction.Severity` is a separate type (String-backed) from our
        // ConflictHint.Severity — compare via raw value to avoid type confusion.
        for partner in companions {
            if let interaction = PeptideCompatibilityData.findInteraction(between: abbreviation, and: partner) {
                let mapped: ConflictHint.Severity =
                    interaction.severity.rawValue == "danger" ? .danger : .caution
                hints.append(ConflictHint(
                    severity: mapped,
                    title: String(localized: "Avoid same-day with \(partner)"),
                    detail: interaction.reason,
                    counterpart: partner
                ))
            }
        }

        // Receptor-pathway redundancy — both peptides target a maxSafe=1 pathway.
        for group in PeptideCompatibilityData.pathwayGroups where group.maxSafe == 1 {
            let groupSet = Set(group.peptideAbbreviations)
            guard groupSet.contains(abbreviation) else { continue }
            for partner in companions where groupSet.contains(partner) {
                // Skip if we already added a more specific known interaction.
                let alreadyKnown = hints.contains { $0.counterpart == partner }
                if alreadyKnown { continue }
                hints.append(ConflictHint(
                    severity: .caution,
                    title: String(localized: "Same pathway as \(partner)"),
                    detail: "\(group.pathway) — \(group.warningText)",
                    counterpart: partner
                ))
            }
        }

        // Fasted reminder if at least one other dose lands in the same slot,
        // so the user knows not to break the fast for the second injection.
        // The caller asks for it once per slot.
        if noteFasted && !companions.isEmpty {
            hints.append(ConflictHint(
                severity: .info,
                title: String(localized: "Stay fasted"),
                detail: String(localized: "Your plan marks this dose as fasted. Other doses in this window can be taken back-to-back without breaking the fast."),
                counterpart: nil
            ))
        }

        // Deduplicate while preserving severity order (danger > caution > info).
        return hints
            .sorted { $0.severity > $1.severity }
            .reduce(into: [ConflictHint]()) { acc, hint in
                if !acc.contains(hint) { acc.append(hint) }
            }
    }
}
