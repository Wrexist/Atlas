import SwiftUI

extension View {
    /// `.sensoryFeedback` that honours the user's Haptic Feedback setting.
    ///
    /// SwiftUI's modifier plays regardless of that preference, so a raw
    /// `.sensoryFeedback` buzzes with haptics turned off. This resolves the
    /// setting through `Haptics` each time the trigger changes, so it stays
    /// live the same way `Haptics.selection()` does.
    func appSensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        condition: ((T, T) -> Bool)? = nil
    ) -> some View {
        sensoryFeedback(trigger: trigger) { oldValue, newValue in
            guard Haptics.isEnabled, condition?(oldValue, newValue) ?? true else { return nil }
            return feedback
        }
    }
}
