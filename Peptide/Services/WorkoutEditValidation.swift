import Foundation

enum WorkoutEditValidation {
    struct InvalidDraft: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func validate(_ draft: WorkoutSession, original: WorkoutSession) throws {
        if let message = issue(in: draft, original: original) { throw InvalidDraft(message: message) }
    }
    /// Decimal input without grouping separators. Handles the current locale's
    /// decimal separator and decimal digits; rejects partial/ambiguous input.
    static func number(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimal = locale.decimalSeparator ?? "."
        if decimal != ".", trimmed.contains(".") { return nil }
        let normalized = trimmed.replacingOccurrences(of: decimal, with: ".")
        var ascii = ""
        for character in normalized {
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { ascii += String(digit) }
            else if character == "." || (character == "-" && ascii.isEmpty) { ascii.append(character) }
            else { return nil }
        }
        guard let value = Double(ascii), value.isFinite else { return nil }
        return value
    }

    static func issue(in draft: WorkoutSession, original: WorkoutSession) -> String? {
        guard draft.id == original.id, draft.finishedAt != nil else { return "This saved workout is unavailable for editing." }
        // Name/note edits remain possible for older manual logs with no sets.
        if original.completedSetCount > 0 && draft.completedSetCount == 0 {
            return "Keep at least one completed working set in this workout."
        }
        let originalSets = Dictionary(original.exercises.flatMap(\.sets).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for set in draft.exercises.flatMap(\.sets) where set != originalSets[set.id] {
            switch set.measurement?.kind {
            case .timed:
                if set.completed && !((set.measurement?.seconds).map { $0.isFinite && $0 > 0 } ?? false) {
                    return "Set \(set.index): enter a duration greater than zero."
                }
            case .distance:
                if set.completed && !((set.measurement?.meters).map { $0.isFinite && $0 > 0 } ?? false) {
                    return "Set \(set.index): enter a distance greater than zero."
                }
            default:
                if !set.weightKg.isFinite || !SetEntryLimits.weightKg.contains(set.weightKg)
                    || !SetEntryLimits.reps.contains(set.reps) {
                    return "Set \(set.index): enter a valid load and repetition count."
                }
            }
        }
        return nil
    }
}
