import Foundation

/// The facts an on-device summary may restate, and the check that what came
/// back restated only those facts.
///
/// Every number is computed by an existing engine and written into a fact
/// line here; the language model only rephrases. `accept(_:for:)` rejects any
/// output carrying a number that is not in the facts, so a hallucinated
/// "bench up 5 kg" falls back to the deterministic copy instead of shipping.
enum OnDeviceSummaryEngine {
    enum Kind: String, Sendable {
        case workout, week, coaching
    }

    struct Facts: Hashable, Sendable {
        let kind: Kind
        /// Calendar day the summary belongs to — scopes the cache.
        let day: String
        /// Complete, already-formatted fact lines.
        let statements: [String]
        /// Deterministic copy shown until (or instead of) the model's text.
        /// `nil` means the surface shows nothing extra without the model.
        let fallback: String?

        var cacheKey: String {
            ([kind.rawValue, day] + statements).joined(separator: "|")
        }
    }

    static let maxLength = 280

    static let instructions = """
    You write one or two short, friendly sentences for a fitness app. \
    Use only the facts provided. Never add numbers, names, causes, comparisons, \
    medical claims, or advice that are not in the facts. \
    Write every number with digits, exactly as it appears in the facts. \
    Address the user as "you". No greetings, no emoji, no markdown.
    """

    // MARK: - Fact building

    static func workout(_ summary: WorkoutRecapEngine.Summary, newPRCount: Int, weekCount: Int?,
                        unit: MeasurementUnit, now: Date = Date(), calendar: Calendar = .current) -> Facts? {
        guard summary.workingSetCount > 0 else { return nil }
        var lines = [
            "Workout: \(summary.name)",
            "Exercises completed: \(summary.entries.count)",
            "Working sets completed: \(summary.workingSetCount)"
        ]
        if case .tracked(let seconds) = summary.duration, seconds >= 60 {
            lines.append("Duration: \(Int((seconds / 60).rounded())) minutes")
        }
        if let volume = summary.volumeKg {
            lines.append("Total volume lifted: \(RecapFormat.volume(volume, unit: unit))")
        }
        let muscles = summary.muscles
            .filter { $0.role == .primary }
            .sorted { $0.setCount != $1.setCount ? $0.setCount > $1.setCount : $0.name < $1.name }
            .prefix(3)
            .map(\.name)
        if !muscles.isEmpty {
            lines.append("Main muscles worked: \(muscles.joined(separator: ", "))")
        }
        if newPRCount > 0 {
            lines.append("New personal records: \(newPRCount)")
        }
        if let weekCount, weekCount > 0 {
            lines.append("Workouts completed this week, including this one: \(weekCount)")
        }
        return Facts(kind: .workout, day: dayKey(now, calendar), statements: lines, fallback: nil)
    }

    static func week(_ week: WorkoutRecapEngine.Week, unit: MeasurementUnit,
                     now: Date = Date(), calendar: Calendar = .current) -> Facts? {
        guard week.count > 0 else { return nil }
        var lines = [
            "Workouts completed so far this week: \(week.count)",
            "Days with a workout this week: \(week.days.filter { $0.count > 0 }.count)"
        ]
        if let volume = week.volumeKg {
            lines.append("Recorded training volume this week: \(RecapFormat.volume(volume, unit: unit))")
        }
        return Facts(kind: .week, day: dayKey(now, calendar), statements: lines, fallback: nil)
    }

    static func coaching(_ message: CoachingMessageEngine.CoachingMessage,
                         context: CoachingMessageEngine.Context,
                         now: Date = Date(), calendar: Calendar = .current) -> Facts? {
        guard let body = message.body, message.tone != .welcome else { return nil }
        var lines = ["Headline already shown above your text: \(message.title)", "Recommendation: \(body)"]
        if let recovery = context.recoveryScore {
            lines.append("Recovery score today: \(recovery)%")
        }
        if let sleep = context.sleepHours, sleep > 0 {
            lines.append("Sleep last night: \(String(format: "%.1f", sleep)) hours")
        }
        return Facts(kind: .coaching, day: dayKey(now, calendar), statements: lines, fallback: body)
    }

    // MARK: - Prompt

    static func prompt(for facts: Facts) -> String {
        let task: String
        switch facts.kind {
        case .workout:
            task = "Summarize the workout the user just finished."
        case .week:
            task = "Recap the user's training so far this week."
        case .coaching:
            task = "Rewrite the recommendation so it reads naturally. Do not repeat the headline. "
                + "Keep its meaning, and keep any advice exactly as cautious as the original."
        }
        return task + "\nFacts:\n" + facts.statements.map { "- \($0)" }.joined(separator: "\n")
    }

    // MARK: - Validation

    /// The trimmed output when it is usable, else `nil`. Usable means
    /// non-empty, short, and carrying no number absent from the facts.
    static func accept(_ output: String, for facts: Facts) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxLength else { return nil }
        let allowed = numbers(in: facts.statements.joined(separator: " "))
        guard numbers(in: text).isSubset(of: allowed) else { return nil }
        return text
    }

    /// Each number in `text`, reduced to its digits so "6,720" and "6720"
    /// compare equal. A `.` or `,` only joins digits on both sides.
    static func numbers(in text: String) -> Set<String> {
        var found = Set<String>()
        var current = ""
        var pendingSeparator = false
        for character in text {
            if character.isNumber {
                current.append(character)
                pendingSeparator = false
            } else if (character == "." || character == ","), !current.isEmpty, !pendingSeparator {
                pendingSeparator = true
            } else {
                if !current.isEmpty { found.insert(current) }
                current = ""
                pendingSeparator = false
            }
        }
        if !current.isEmpty { found.insert(current) }
        return found
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
