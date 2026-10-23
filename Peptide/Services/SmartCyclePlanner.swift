import Foundation

/// Roadmap v3.3 — additive analyser that pulls patterns out of the
/// user's existing protocol + entry history and emits cycle-planning
/// suggestions. Pure functions over the inputs (no IO, no actor) so
/// the View layer can call this on every render without paying for
/// a re-fetch — `DataStore` already caches expensive derivatives.
///
/// Suggestions land on the Home tab via `SmartCyclePlannerCard`. The
/// engine is intentionally conservative: every suggestion includes a
/// rationale + a confidence score, and the UI hides anything below
/// `.medium` so the user isn't drowned in low-signal nudges.
enum SmartCyclePlanner {

    enum Confidence: Int, Comparable {
        case low = 0, medium = 1, high = 2
        static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Kind: Equatable {
        /// Compliance is decaying — recommend a shorter cycle next time.
        case shortenNextCycle(currentWeeks: Int, suggestedWeeks: Int)
        /// User consistently misses the same time slot — suggest a
        /// schedule shift.
        case shiftDoseTime(from: String, to: String)
        /// Cycle nearing the end of its window — surface a wrap-up nudge.
        case cycleWrappingUp(daysRemaining: Int)
        /// User has been off-cycle long enough — suggest a fresh start.
        case offCycleReady(daysSinceLast: Int)
        /// Stack hasn't logged in N days — recommend pausing instead of
        /// silently abandoning.
        case considerPausing(daysIdle: Int)
        /// The current on-phase ends soon and the wash-out starts on its own.
        case washoutStarting(daysRemaining: Int)

        /// The heuristic that produced it, without its payload.
        var heuristic: String {
            switch self {
            case .shortenNextCycle: "shorten"
            case .shiftDoseTime: "shift"
            case .cycleWrappingUp: "wrapUp"
            case .offCycleReady: "offCycle"
            case .considerPausing: "pause"
            case .washoutStarting: "washout"
            }
        }
    }

    struct Suggestion: Identifiable, Equatable {
        let protocolID: UUID?
        let kind: Kind
        let title: String
        let rationale: String
        let confidence: Confidence

        init(
            protocolID: UUID? = nil,
            kind: Kind,
            title: String,
            rationale: String,
            confidence: Confidence
        ) {
            self.protocolID = protocolID
            self.kind = kind
            self.title = title
            self.rationale = rationale
            self.confidence = confidence
        }

        /// One suggestion per protocol and heuristic, so the id is stable
        /// across recomputes and ForEach identity doesn't churn.
        var id: String {
            "\(protocolID?.uuidString ?? "-")|\(kind.heuristic)"
        }
    }

    // MARK: - Entry point

    /// Builds the full suggestion list. Ordered by confidence (highest
    /// first) so the highest-signal nudges sit at the top of any UI
    /// surface that renders the array directly.
    static func suggestions(
        protocols: [PeptideProtocol],
        entries: [ProtocolEntry],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [Suggestion] {
        var out: [Suggestion] = []

        for proto in protocols where proto.status == .active {
            let entriesForProto = entries.filter { $0.protocolId == proto.id }

            if let nudge = wrappingUpNudge(for: proto, today: today, calendar: calendar) {
                out.append(nudge)
            }
            if let nudge = idleNudge(for: proto, entries: entriesForProto, today: today, calendar: calendar) {
                out.append(nudge)
            }
            if let nudge = decayingComplianceNudge(for: proto, entries: entriesForProto, today: today, calendar: calendar) {
                out.append(nudge)
            }
            if let nudge = missedTimeSlotNudge(for: proto, entries: entriesForProto, today: today, calendar: calendar) {
                out.append(nudge)
            }
        }

        // Only the most recently ended protocol, and not when one running
        // now already uses its peptides — otherwise every finished
        // protocol keeps a permanent "start a new cycle?" row.
        let activePeptideIDs = Set(protocols.filter { $0.status == .active }.flatMap { $0.peptides.map(\.id) })
        if let latest = protocols.filter({ $0.status == .completed }).max(by: { $0.cycleEndDay < $1.cycleEndDay }),
           !latest.peptides.contains(where: { activePeptideIDs.contains($0.id) }),
           let nudge = offCycleNudge(for: latest, today: today, calendar: calendar) {
            out.append(nudge)
        }

        return out.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Heuristics

    /// Within 5 days of cycle end → "wrapping up" nudge so the user
    /// can plan whether to extend, pause, or move on. A wash-out protocol
    /// doesn't end: its current on-phase hands over to the wash-out on
    /// its own, so it gets a heads-up about that instead.
    private static func wrappingUpNudge(
        for proto: PeptideProtocol,
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        if proto.washoutWeeks > 0 {
            let status = CyclePhaseEngine.status(for: proto, at: today)
            guard case .onCycle = status.phase else { return nil }
            let remaining = CyclePhaseEngine.daysUntilPhaseEnd(status, from: today, calendar: calendar)
            guard remaining <= 5 else { return nil }
            return Suggestion(
                protocolID: proto.id,
                kind: .washoutStarting(daysRemaining: remaining),
                title: remaining <= 1
                    ? String(localized: "\(proto.name) wash-out begins tomorrow", comment: "Smart planner — a wash-out protocol's last on-cycle day is today.")
                    : String(localized: "\(proto.name) wash-out begins in \(remaining) days"),
                rationale: String(localized: "Doses pause automatically during the wash-out and resume when the next cycle starts."),
                confidence: .medium
            )
        }

        // Use the protocol's canonical, start-of-day-normalised cycle
        // end so this agrees with `daysRemaining` / CycleCompletionService
        // rather than drifting by the start date's time-of-day.
        let end = proto.cycleEndDay
        let remaining = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: today), to: end
        ).day ?? -1
        guard remaining >= 0, remaining <= 5 else { return nil }

        return Suggestion(
            protocolID: proto.id,
            kind: .cycleWrappingUp(daysRemaining: remaining),
            title: String(localized: "\(proto.name) wraps up in \(remaining) days"),
            rationale: String(localized: "Plan whether to extend, take an off-cycle break, or transition to your next protocol while it's still fresh."),
            confidence: remaining <= 2 ? .high : .medium
        )
    }

    /// Start of the run the protocol is dosing in now: the current
    /// on-phase for a wash-out protocol, else its start. Nil during a
    /// wash-out or before it starts, when no doses are due.
    private static func currentRunStart(
        of proto: PeptideProtocol,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        switch CyclePhaseEngine.status(for: proto, at: today).phase {
        case .onCycle(let day, _):
            return calendar.date(byAdding: .day, value: -(day - 1), to: calendar.startOfDay(for: today))
        case .completed:
            return calendar.startOfDay(for: proto.startDate)
        case .washout, .upcoming:
            return nil
        }
    }

    /// No completed entries in the past 7 days for an "active" protocol
    /// → recommend pausing rather than silently abandoning. Gated on
    /// the protocol being at least 7 days old — a brand-new
    /// protocol naturally has no completed entries yet and triggering
    /// "Pause this stack?" on day one is wrong (audit Library P1.7).
    private static func idleNudge(
        for proto: PeptideProtocol,
        entries: [ProtocolEntry],
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        // Wash-out weeks have no doses by design; idle time is measured
        // within the current run so they never count towards it.
        guard let runStart = currentRunStart(of: proto, today: today, calendar: calendar) else { return nil }
        let daysSinceStart = calendar.dateComponents([.day], from: runStart, to: today).day ?? 0
        guard daysSinceStart >= 7 else { return nil }

        let cutoff = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let recent = entries.filter { $0.completed && $0.date >= cutoff }
        guard recent.isEmpty else { return nil }

        let lastCompleted = entries.filter { $0.completed && $0.date >= runStart }.map(\.date).max()
        let idleDays: Int = {
            guard let last = lastCompleted else {
                // No completions in this run, but it's ≥7 days old —
                // measure idle from its start rather than the
                // misleading fallback of 30.
                return daysSinceStart
            }
            return max(7, calendar.dateComponents([.day], from: last, to: today).day ?? 7)
        }()

        return Suggestion(
            protocolID: proto.id,
            kind: .considerPausing(daysIdle: idleDays),
            title: String(localized: "Pause \(proto.name)?"),
            rationale: String(localized: "No doses logged for \(idleDays) days. Pausing keeps your stats clean and stops misleading streak alerts."),
            confidence: idleDays >= 14 ? .high : .medium
        )
    }

    /// Compliance over the second half of the cycle is materially worse
    /// than the first half → recommend a shorter window next time.
    private static func decayingComplianceNudge(
        for proto: PeptideProtocol,
        entries: [ProtocolEntry],
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        let weeks = proto.safeCycleLengthWeeks
        guard weeks >= 4 else { return nil } // too short to split

        guard let cycleStart = currentRunStart(of: proto, today: today, calendar: calendar) else { return nil }
        let mid = calendar.date(byAdding: .day, value: (weeks * 7) / 2, to: cycleStart) ?? cycleStart
        let firstHalf = entries.filter { $0.date < mid && $0.date >= cycleStart }
        let secondHalf = entries.filter { $0.date >= mid && $0.date <= today }
        // Require enough samples in each half to draw a real signal —
        // 5 was low enough that 5 entries spanning a few days in the
        // second half could outweigh 30 over weeks in the first and
        // produce a spurious 'compliance decaying' high-confidence
        // card. 10 per half is a defensible minimum for a 4-week
        // cycle (~7 entries/half if 1×/day, so this also blocks
        // 1×/day protocols from the heuristic — those are too sparse
        // to support a half-vs-half claim).
        guard firstHalf.count >= 10, secondHalf.count >= 10 else { return nil }

        let firstRate = Double(firstHalf.filter(\.completed).count) / Double(firstHalf.count)
        let secondRate = Double(secondHalf.filter(\.completed).count) / Double(secondHalf.count)
        guard secondRate + 0.20 < firstRate else { return nil }

        let suggested = max(2, weeks - 2)
        return Suggestion(
            protocolID: proto.id,
            kind: .shortenNextCycle(currentWeeks: weeks, suggestedWeeks: suggested),
            title: String(localized: "Try a \(suggested)-week cycle next time"),
            rationale: String(localized: "Adherence dropped from \(Int(firstRate * 100))% in week 1-\(weeks/2) to \(Int(secondRate * 100))% after. A shorter cycle tends to land more doses."),
            confidence: secondRate + 0.30 < firstRate ? .high : .medium
        )
    }

    /// One scheduled time slot has materially worse adherence than the
    /// rest → recommend shifting it (e.g., the 9 PM dose is missed
    /// 60% of the time, suggest 8 PM).
    private static func missedTimeSlotNudge(
        for proto: PeptideProtocol,
        entries: [ProtocolEntry],
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        guard proto.schedule.preferredTimes.count >= 2 else { return nil }

        let perTime: [(time: String, rate: Double)] = proto.schedule.preferredTimes.compactMap { time -> (String, Double)? in
            let bucket = entries.filter { entryTimeKey(for: $0.date, calendar: calendar) == time }
            guard bucket.count >= 5 else { return nil }
            let rate = Double(bucket.filter(\.completed).count) / Double(bucket.count)
            return (time, rate)
        }
        guard perTime.count >= 2,
              let worst = perTime.min(by: { $0.rate < $1.rate }),
              let best = perTime.max(by: { $0.rate < $1.rate }),
              // When two slots tie on adherence, min/max may select
              // the same element. Suggesting "Shift 8:00 AM → 8:00 AM"
              // is nonsense; guard against the self-shift here.
              best.time != worst.time,
              best.rate - worst.rate >= 0.25
        else { return nil }

        return Suggestion(
            protocolID: proto.id,
            kind: .shiftDoseTime(from: worst.time, to: best.time),
            title: String(localized: "Shift the \(ProtocolSchedule.displayTime(worst.time)) dose"),
            rationale: String(localized: "You take it \(Int(worst.rate * 100))% of the time vs \(Int(best.rate * 100))% at \(ProtocolSchedule.displayTime(best.time)). Moving it closer to a slot you nail might lift adherence."),
            confidence: best.rate - worst.rate >= 0.40 ? .high : .medium
        )
    }

    /// How long after the rest window a restart is still suggested.
    private static let offCycleOfferDays = 30

    /// Completed protocol's recommended off-cycle window has elapsed
    /// (heuristic: cycleLengthWeeks * 0.5) → suggest restarting or
    /// transitioning to a successor stack.
    private static func offCycleNudge(
        for proto: PeptideProtocol,
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        let weeks = proto.safeCycleLengthWeeks
        let end = proto.cycleEndDay
        let offWindowDays = max(7, weeks * 7 / 2)
        guard let resumeDate = calendar.date(byAdding: .day, value: offWindowDays, to: end) else { return nil }
        let todayStart = calendar.startOfDay(for: today)
        guard todayStart >= resumeDate,
              let staleDate = calendar.date(byAdding: .day, value: offCycleOfferDays, to: resumeDate),
              todayStart < staleDate
        else { return nil }
        let elapsed = calendar.dateComponents([.day], from: end, to: todayStart).day ?? 0

        return Suggestion(
            protocolID: proto.id,
            kind: .offCycleReady(daysSinceLast: elapsed),
            title: String(localized: "Ready to start a new \(proto.name) cycle?"),
            rationale: String(localized: "It's been \(elapsed) days off-cycle — past the typical \(offWindowDays)-day rest window for this protocol length."),
            confidence: .medium
        )
    }

    // MARK: - Helpers

    /// Maps an entry's wall-clock time back to one of the protocol's
    /// preferred time strings (e.g. "8:00 AM"). Used to bucket entries
    /// for per-slot adherence math.
    ///
    /// Producer (`ScheduleEditor.formatter`) and consumer (here) must
    /// share an exact byte-identical format — iOS 17+ system locales
    /// use a narrow no-break space (U+202F) before AM/PM via
    /// `Date.formatted(...)`, which breaks naïve string equality.
    /// Both sides use `h:mm a` + `en_US_POSIX` so the AM/PM separator
    /// is a regular ASCII space and the bucket lookup keeps matching.
    private static let timeKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func entryTimeKey(for date: Date, calendar _: Calendar) -> String {
        // The formatter uses the user's current timezone by default,
        // matching `ScheduleEditor.formatter` (the producer of the
        // `preferredTimes` strings). The `calendar` argument is kept
        // for API symmetry but unused — both producer and consumer
        // operate in the user's local zone.
        timeKeyFormatter.string(from: date)
    }
}
