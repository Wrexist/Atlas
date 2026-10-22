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
            .map(\.displayName)
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
        // A recap reopened from history charts that workout's own week,
        // which is not "this week" to the reader.
        let span = week.isCurrent ? "this week" : "that week"
        var lines = [
            "Workouts completed \(week.isCurrent ? "so far this week" : span): \(week.count)",
            "Days with a workout \(span): \(week.days.filter { $0.count > 0 }.count)"
        ]
        if let volume = week.volumeKg {
            lines.append("Recorded training volume \(span): \(RecapFormat.volume(volume, unit: unit))")
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
            task = "Recap the user's training for the week in the facts."
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
        let allowed = facts.statements.reduce(into: Set<String>()) { $0.formUnion(numbers(in: $1)) }
        guard numbers(in: text).isSubset(of: allowed) else { return nil }
        return text
    }

    /// Each number in `text` as a canonical value, so "12,400", "12 400" and
    /// "12400" compare equal while "5.2" and "5,2" stay distinct from "52".
    ///
    /// Facts carry integers grouped by the locale's `formatted()` (",", "." or
    /// a no-break space) and one-decimal values from `%.1f`. A separator
    /// followed by exactly three digits is therefore grouping; any other
    /// `.` or `,` is the decimal point. A space only ever groups.
    static func numbers(in text: String) -> Set<String> {
        let characters = Array(text)
        var found = Set<String>()
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            var groups = [digitRun(in: characters, from: &index)]
            var marks: [Character] = []
            while index + 1 < characters.count, characters[index + 1].isNumber,
                  decimalMarks.contains(characters[index]) || groupingSpaces.contains(characters[index]) {
                let mark = characters[index]
                var next = index + 1
                let group = digitRun(in: characters, from: &next)
                if groupingSpaces.contains(mark), group.count != 3 { break }
                marks.append(mark)
                groups.append(group)
                index = next
            }
            found.insert(canonicalNumber(groups: groups, marks: marks))
        }
        return found
    }

    private static let decimalMarks: Set<Character> = [".", ","]
    private static let groupingSpaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}"]

    private static func digitRun(in characters: [Character], from index: inout Int) -> String {
        var run = ""
        while index < characters.count, characters[index].isNumber {
            run.append(characters[index])
            index += 1
        }
        return run
    }

    private static func canonicalNumber(groups: [String], marks: [Character]) -> String {
        guard let last = marks.last, let fraction = groups.last, decimalMarks.contains(last),
              fraction.count != 3 || marks.dropLast().contains(where: { decimalMarks.contains($0) && $0 != last })
        else { return groups.joined() }
        let integer = groups.dropLast().joined()
        let trimmed = String(fraction.reversed().drop(while: { $0 == "0" }).reversed())
        return trimmed.isEmpty ? integer : integer + "." + trimmed
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
