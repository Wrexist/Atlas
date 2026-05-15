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

    /// Canonical "wait for a presented sheet to finish its dismiss
    /// animation before presenting the next one" delay. SwiftUI
    /// silently drops a second `.sheet(item:)` / `.sheet(isPresented:)`
    /// presentation that races with the first on the same runloop
    /// tick; 350 ms covers both standard and Reduce Motion timings
    /// without feeling laggy. Use with `Task.sleep(for:)` right after
    /// flipping the first binding to false.
    ///
    /// Replaces the inline `try? await Task.sleep(for: .milliseconds(350))`
    /// (and a stray 300ms variant) that were sprinkled across HomeView
    /// and LifestyleView — name the magic number once so the next
    /// sheet-chain author doesn't pick a different value and find out
    /// the hard way that 200ms is too short.
    static let sheetDismissDelay: Duration = .milliseconds(350)

    // MARK: - Food library timings

    /// "Logged ✓" overlay duration on the food library's quick-log
    /// rows. 1.5 s is long enough to read the confirmation badge
    /// without lingering past the user's next intent.
    static let quickLogConfirmationDuration: Duration = .milliseconds(1500)

    /// Debounce window between keystrokes in the food library search
    /// bar. Trades responsiveness for OFF rate-limit headroom — at
    /// 500 ms a typist of 240 wpm fires roughly one search per pause,
    /// which sits comfortably under the limiter's 8-per-minute slot
    /// budget.
    static let searchDebounceDelay: Duration = .milliseconds(500)

    /// Auto-close delay on the food library and barcode scanner's
    /// `.logged` success screens. The 4-5 s window gives users
    /// enough time to tap Undo without holding the sheet open
    /// indefinitely. Single source of truth so both flows agree.
    static let logSuccessAutoCloseDelay: Duration = .seconds(5)

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
