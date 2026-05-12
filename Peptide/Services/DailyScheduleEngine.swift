import Foundation

/// Builds a per-day plan from today's `ProtocolEntry` list:
/// - Groups doses into time-of-day slots (morning fasted, post-workout, pre-bed, …).
/// - Orders doses within each slot so fasted/critical-timing peptides go first.
/// - Surfaces validated co-injection synergies (e.g. CJC-1295 + Ipamorelin).
/// - Flags same-day conflicts (intranasal spacing, GHS-R/GHRH receptor overlap,
///   GLP-1 stacking, IGF-1 stacking, hepatic load).
///
/// The engine is pure and deterministic — no I/O, no side effects — so it's easy
/// to unit-test and safe to call on every view update.
enum DailyScheduleEngine {

    // MARK: - Slots

    enum DaySlot: Int, CaseIterable, Comparable, Hashable {
        case morningFasted
        case morningWithFood
        case midday
        case preWorkout
        case postWorkout
        case evening
        case preBed

        var title: String {
            switch self {
            case .morningFasted:    return "Morning · Fasted"
            case .morningWithFood:  return "Morning · With Food"
            case .midday:           return "Midday"
            case .preWorkout:       return "Pre-Workout"
            case .postWorkout:      return "Post-Workout"
            case .evening:          return "Evening"
            case .preBed:           return "Before Bed"
            }
        }

        var iconName: String {
            switch self {
            case .morningFasted:    return "sunrise.fill"
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
            case .morningFasted:    return "On waking, empty stomach"
            case .morningWithFood:  return "After breakfast"
            case .midday:           return "Mid-day"
            case .preWorkout:       return "30–45 min before training"
            case .postWorkout:      return "Within 30 min of training"
            case .evening:          return "Late afternoon / evening"
            case .preBed:           return "30–60 min before sleep"
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
            case 0..<5:    return .evening   // late-night dose, treat as evening continuation
            case 5..<10:   return .morningFasted
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
        let stackName: String
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
        /// warnings like Semax↔Selank spacing).
        var conflictCount: Int {
            var pairs = Set<UnorderedPair>()
            var unpaired = 0
            for slot in slots {
                for dose in slot.doses {
                    for conflict in dose.conflicts {
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
        /// Phrased to highlight the first action the user should take.
        var headline: String {
            guard let first = slots.first?.doses.first else { return "Nothing scheduled today" }
            let abbrev = first.entry.peptide.abbreviation
            switch first.slot {
            case .morningFasted:
                return "Start with \(abbrev) — fasted, on waking"
            case .preBed:
                return "End the day with \(abbrev) before bed"
            case .postWorkout:
                return "Take \(abbrev) right after training"
            case .preWorkout:
                return "Take \(abbrev) before training"
            default:
                return "Begin with \(abbrev) at \(Self.shortTime(first.entry.date))"
            }
        }

        var summary: String {
            let slotCount = slots.count
            var parts: [String] = []
            parts.append("\(totalDoses) \(totalDoses == 1 ? "dose" : "doses") across \(slotCount) \(slotCount == 1 ? "window" : "windows")")
            if combinationCount > 0 {
                parts.append("\(combinationCount) co-inject \(combinationCount == 1 ? "match" : "matches")")
            }
            if conflictCount > 0 {
                parts.append("\(conflictCount) timing \(conflictCount == 1 ? "note" : "notes")")
            }
            return parts.joined(separator: " · ")
        }

        private static func shortTime(_ date: Date) -> String {
            date.formatted(.dateTime.hour().minute())
        }
    }

    // MARK: - Public API

    /// Builds a fully-ordered plan from today's entries.
    /// `now` is injected so tests can drive deterministic output.
    static func plan(for entries: [ProtocolEntry], now: Date = Date()) -> DailyPlan {
        guard !entries.isEmpty else {
            return DailyPlan(slots: [], totalDoses: 0)
        }

        let calendar = Calendar.current
        let assignments: [(entry: ProtocolEntry, slot: DaySlot, fasted: Bool, note: String)] = entries.map { entry in
            let info = PeptideTimingData.timingRecommendations[entry.peptide.abbreviation]
            let slot = resolveSlot(for: entry, timing: info, calendar: calendar)
            let fasted = info?.preferredWindows.contains(.morningFasted) == true
                && (info?.notes.lowercased().contains("fasted") == true
                    || info?.notes.lowercased().contains("empty stomach") == true)
            return (entry, slot, fasted, info?.notes ?? "")
        }

        let grouped = Dictionary(grouping: assignments, by: \.slot)

        let scheduled: [ScheduledSlot] = grouped.keys.sorted().map { slot in
            let bucket = grouped[slot] ?? []
            let abbrevsInSlot = bucket.map(\.entry.peptide.abbreviation)
            let ordered = orderWithinSlot(bucket)

            let doses: [PlannedDose] = ordered.enumerated().map { index, item in
                let combinations = combinationHints(
                    for: item.entry.peptide.abbreviation,
                    others: abbrevsInSlot
                )
                let conflicts = conflictHints(
                    for: item.entry.peptide.abbreviation,
                    others: abbrevsInSlot,
                    timing: PeptideTimingData.timingRecommendations[item.entry.peptide.abbreviation],
                    fastedRequired: item.fasted
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

    private static func resolveSlot(
        for entry: ProtocolEntry,
        timing: PeptideTimingData.PeptideTiming?,
        calendar: Calendar
    ) -> DaySlot {
        // Prefer the peptide's preferred window — picks the earliest slot in the
        // day so we order across slots cleanly. `.anyTime` is skipped because it
        // doesn't pin a time; fall back to the entry's clock hour for those.
        if let timing {
            let preferred = timing.preferredWindows
                .compactMap(DaySlot.from(_:))
                .sorted()
            if let earliest = preferred.first {
                // If the user's scheduled clock time clearly disagrees with the
                // peptide's preferred window (e.g. peptide says morningFasted but
                // entry is at 10pm), respect the user's clock time — they may have
                // a workout schedule we don't know about.
                let hour = calendar.component(.hour, from: entry.date)
                let userSlot = DaySlot.from(hour: hour)
                if userSlot == .preBed && !preferred.contains(.preBed) { return .preBed }
                return earliest
            }
        }
        let hour = calendar.component(.hour, from: entry.date)
        return DaySlot.from(hour: hour)
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
                    stackName: stack.name,
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
        fastedRequired: Bool
    ) -> [ConflictHint] {
        var hints: [ConflictHint] = []
        let companions = Array(Set(others).subtracting([abbreviation]))

        // Per-peptide explicit "avoid co-administration" list — typically
        // intranasals that compete for nasal mucosa absorption.
        if let avoid = timing?.avoidWith {
            for partner in avoid where companions.contains(partner) {
                hints.append(ConflictHint(
                    severity: .caution,
                    title: "Separate from \(partner) by 15+ min",
                    detail: "Both are intranasal — back-to-back administration reduces absorption of the second peptide.",
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
                    title: "Avoid same-day with \(partner)",
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
                    title: "Same pathway as \(partner)",
                    detail: "\(group.pathway) — \(group.warningText)",
                    counterpart: partner
                ))
            }
        }

        // Fasted reminder if at least one other dose lands in the same slot,
        // so the user knows not to break the fast for the second injection.
        if fastedRequired && !companions.isEmpty {
            let fastedNote = "Stay fasted — don't eat for 30 min after injection. Other doses in this window can be taken back-to-back without breaking the fast."
            // Only add if this is the first fasted-required peptide we see;
            // otherwise the note becomes redundant noise.
            if !hints.contains(where: { $0.title.hasPrefix("Stay fasted") }) {
                hints.append(ConflictHint(
                    severity: .info,
                    title: "Stay fasted",
                    detail: fastedNote,
                    counterpart: nil
                ))
            }
        }

        // Deduplicate while preserving severity order (danger > caution > info).
        return hints
            .sorted { $0.severity > $1.severity }
            .reduce(into: [ConflictHint]()) { acc, hint in
                if !acc.contains(hint) { acc.append(hint) }
            }
    }
}
