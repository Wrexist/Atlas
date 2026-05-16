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
    }

    struct Suggestion: Identifiable, Equatable {
        let id: UUID
        let protocolID: UUID?
        let kind: Kind
        let title: String
        let rationale: String
        let confidence: Confidence

        init(
            id: UUID = UUID(),
            protocolID: UUID? = nil,
            kind: Kind,
            title: String,
            rationale: String,
            confidence: Confidence
        ) {
            self.id = id
            self.protocolID = protocolID
            self.kind = kind
            self.title = title
            self.rationale = rationale
            self.confidence = confidence
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

        for proto in protocols where proto.status == .completed {
            if let nudge = offCycleNudge(for: proto, today: today, calendar: calendar) {
                out.append(nudge)
            }
        }

        return out.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Heuristics

    /// Within 5 days of cycle end → "wrapping up" nudge so the user
    /// can plan whether to extend, pause, or move on.
    private static func wrappingUpNudge(
        for proto: PeptideProtocol,
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        let weeks = proto.safeCycleLengthWeeks
        guard let end = calendar.date(byAdding: .day, value: weeks * 7, to: proto.startDate) else { return nil }
        let remaining = calendar.dateComponents([.day], from: today, to: end).day ?? -1
        guard remaining >= 0, remaining <= 5 else { return nil }

        return Suggestion(
            protocolID: proto.id,
            kind: .cycleWrappingUp(daysRemaining: remaining),
            title: "\(proto.name) wraps up in \(remaining) day\(remaining == 1 ? "" : "s")",
            rationale: "Plan whether to extend, take an off-cycle break, or transition to your next stack while it's still fresh.",
            confidence: remaining <= 2 ? .high : .medium
        )
    }

    /// No completed entries in the past 7 days for an "active" protocol
    /// → recommend pausing rather than silently abandoning.
    private static func idleNudge(
        for proto: PeptideProtocol,
        entries: [ProtocolEntry],
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let recent = entries.filter { $0.completed && $0.date >= cutoff }
        guard recent.isEmpty else { return nil }

        let lastCompleted = entries.filter(\.completed).map(\.date).max()
        let idleDays: Int = {
            guard let last = lastCompleted else { return 30 }
            return max(7, calendar.dateComponents([.day], from: last, to: today).day ?? 7)
        }()

        return Suggestion(
            protocolID: proto.id,
            kind: .considerPausing(daysIdle: idleDays),
            title: "Pause \(proto.name)?",
            rationale: "No doses logged for \(idleDays) days. Pausing keeps your stats clean and stops misleading streak alerts.",
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

        let cycleStart = calendar.startOfDay(for: proto.startDate)
        let mid = calendar.date(byAdding: .day, value: (weeks * 7) / 2, to: cycleStart) ?? cycleStart
        let firstHalf = entries.filter { $0.date < mid && $0.date >= cycleStart }
        let secondHalf = entries.filter { $0.date >= mid && $0.date <= today }
        guard firstHalf.count >= 5, secondHalf.count >= 5 else { return nil }

        let firstRate = Double(firstHalf.filter(\.completed).count) / Double(firstHalf.count)
        let secondRate = Double(secondHalf.filter(\.completed).count) / Double(secondHalf.count)
        guard secondRate + 0.20 < firstRate else { return nil }

        let suggested = max(2, weeks - 2)
        return Suggestion(
            protocolID: proto.id,
            kind: .shortenNextCycle(currentWeeks: weeks, suggestedWeeks: suggested),
            title: "Try a \(suggested)-week cycle next time",
            rationale: "Adherence dropped from \(Int(firstRate * 100))% in week 1-\(weeks/2) to \(Int(secondRate * 100))% after. A shorter cycle tends to land more doses.",
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
            title: "Shift the \(worst.time) dose",
            rationale: "You take it \(Int(worst.rate * 100))% of the time vs \(Int(best.rate * 100))% at \(best.time). Moving it closer to a slot you nail might lift adherence.",
            confidence: best.rate - worst.rate >= 0.40 ? .high : .medium
        )
    }

    /// Completed protocol's recommended off-cycle window has elapsed
    /// (heuristic: cycleLengthWeeks * 0.5) → suggest restarting or
    /// transitioning to a successor stack.
    private static func offCycleNudge(
        for proto: PeptideProtocol,
        today: Date,
        calendar: Calendar
    ) -> Suggestion? {
        let weeks = proto.safeCycleLengthWeeks
        guard let end = calendar.date(byAdding: .day, value: weeks * 7, to: proto.startDate) else { return nil }
        let offWindowDays = max(7, weeks * 7 / 2)
        guard let resumeDate = calendar.date(byAdding: .day, value: offWindowDays, to: end) else { return nil }
        guard today >= resumeDate else { return nil }
        let elapsed = calendar.dateComponents([.day], from: end, to: today).day ?? 0

        return Suggestion(
            protocolID: proto.id,
            kind: .offCycleReady(daysSinceLast: elapsed),
            title: "Ready to start a new \(proto.name) cycle?",
            rationale: "It's been \(elapsed) days off-cycle — past the typical \(offWindowDays)-day rest window for this stack length.",
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
    // Read-only after configuration; DateFormatter is documented
    // thread-safe for reads. `nonisolated(unsafe)` is the right
    // escape hatch since the type isn't marked Sendable.
    nonisolated(unsafe) private static let timeKeyFormatter: DateFormatter = {
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
