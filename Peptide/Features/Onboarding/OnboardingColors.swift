import SwiftUI

/// Tints used by the Onboarding goal cards and background gradients. Kept in
/// the Onboarding feature folder rather than in the app-wide design system
/// because they're specific to the goal-selection visual language.
enum OnboardingTint {
    static let muscleRecovery = Color(hex: 0x5B8FB9)
    static let sleep          = Color(hex: 0x9B72CF)
    static let cognitive      = Color(hex: 0x9B72CF)
    static let antiAging      = Color(hex: 0xD4A844)
    static let fatLoss        = Color(hex: 0xE88D4F)
    static let immune         = Color(hex: 0xCF7272)
}
