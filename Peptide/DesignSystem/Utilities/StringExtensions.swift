import Foundation

extension String {
    /// Returns `nil` when the string is empty after trimming, else
    /// returns the trimmed string. Lets callers collapse "should I
    /// store an empty placeholder or nil" into one expression.
    ///
    /// Previously the same property was redefined privately in three
    /// places (`CustomFood.swift`, `CustomFoodEditorSheet.swift`,
    /// `OpenFoodFactsService.swift` as `nonEmptyOrNil`) — keeping
    /// them in lockstep was a foot-gun no one would catch until a
    /// future contributor edited only one copy. Centralised here so
    /// every consumer reads the same rule.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
