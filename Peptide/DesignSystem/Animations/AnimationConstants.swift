import SwiftUI

enum AppAnimation {
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let springSmooth = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let springGentle = Animation.spring(response: 0.8, dampingFraction: 0.9)

    static let fadeIn = Animation.easeOut(duration: 0.25)
    static let fadeInSlow = Animation.easeOut(duration: 0.4)

    static let staggerDelay: Double = 0.05
    static let sectionDelay: Double = 0.15

    // Cap the visible delay so long lists (10+ cards) don't take 1.5s+ to settle.
    private static let maxStaggerIndex = 8
    private static let maxSectionIndex = 4

    static func staggered(index: Int) -> Animation {
        springBouncy.delay(Double(min(index, maxStaggerIndex)) * staggerDelay)
    }

    static func sectionStaggered(index: Int) -> Animation {
        springSmooth.delay(Double(min(index, maxSectionIndex)) * sectionDelay)
    }

    /// Returns `nil` when Reduce Motion is on so callers can pass the result
    /// directly to `withAnimation(_:)` and have iOS skip the animation.
    /// Read `accessibilityReduceMotion` from the View's environment and pass it in.
    static func motionAware(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
