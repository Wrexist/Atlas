import Foundation

/// Whole-number macro entry shared by the meal editors, so a stray
/// "200000" kcal can't reach the diary from one editor while the other
/// rejects it.
enum MacroInput {
    static let range = 0...100_000

    /// The typed value, or nil when blank, not a whole number, or out of range.
    static func parse(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              range.contains(value) else { return nil }
        return value
    }
}
