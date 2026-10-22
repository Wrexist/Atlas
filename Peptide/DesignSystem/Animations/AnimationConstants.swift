import SwiftUI
import UIKit

enum AppAnimation {
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let springSmooth = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let springGentle = Animation.spring(response: 0.8, dampingFraction: 0.9)

    static let fadeIn = Animation.easeOut(duration: 0.25)
    static let fadeInSlow = Animation.easeOut(duration: 0.4)

    /// Small state flips: a tab tint, a toggle's dim, a focused field.
    static let quick = Animation.easeOut(duration: 0.18)
    /// Button press-down. Shorter than `quick` so release never lags the finger.
    static let press = Animation.easeOut(duration: 0.16)
    /// Toasts and banners sliding in and out.
    static let toast = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// Moving between steps of a multi-step flow, and paging a calendar.
    static let step = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// Layout that should land without overshoot: expand/collapse, scroll-to.
    static let settle = Animation.smooth(duration: 0.35)
    /// One leg of an error shake, then the return to rest.
    static let shake = Animation.spring(response: 0.12, dampingFraction: 0.45)
    static let shakeSettle = Animation.spring(response: 0.18, dampingFraction: 0.6)
    /// A chart line or path drawing itself in.
    static let draw = Animation.easeOut(duration: 1.2)
    /// Slow backdrop cross-fades behind content (onboarding, tours).
    static let ambient = Animation.easeInOut(duration: 1.2)
    /// One top-to-bottom sweep of the muscle map's scan beam.
    static let muscleScan = Animation.easeInOut(duration: 0.9)
    /// A cut-out dish flying from the table photo to its slot in the
    /// review grid. Long enough to follow which plate went where.
    static let liftFly = Animation.spring(response: 0.6, dampingFraction: 0.78)
    /// Gap between consecutive dishes leaving the photo.
    static let liftStagger: Double = 0.08

    // MARK: Loops — one period each, run through `motionAwareLoop`

    /// "This is live / working": an opacity, scale or beam that swings back
    /// and forth. Slow enough to read as ambient rather than urgent.
    static let breathe = Animation.easeInOut(duration: 1.4)
    /// A status dot's ring expanding outward and fading, then restarting.
    static let ripple = Animation.easeOut(duration: 1.4)
    /// One skeleton shimmer sweep — the beat Health and the App Store use,
    /// slow enough to read as "still working" without feeling stalled.
    static let loadingSweep = Animation.linear(duration: 1.4)

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
    /// (and a stray 300ms variant) that used to be sprinkled across
    /// the sheet-handoff paths in `HomeMealsSection`,
    /// `ProfileCustomizationSheet`, and the meal-scan flow — name
    /// the magic number once so the next sheet-chain author doesn't
    /// pick a different value and find out the hard way that 200ms
    /// is too short.
    static let sheetDismissDelay: Duration = .milliseconds(350)

    /// How long an "Added" confirmation stays on screen before its sheet
    /// dismisses. Skipped under Reduce Motion.
    static let confirmationHold: Duration = .milliseconds(600)

    // MARK: - Food library timings

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

    /// `withAnimation` that reads Reduce Motion itself, for actions and
    /// callbacks with no view environment to hand. Under Reduce Motion the
    /// state still changes, it just doesn't move.
    @MainActor
    @discardableResult
    static func with<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : animation, body)
    }
}

private struct ReduceMotionAwareAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Starts the loop on appear and follows Reduce Motion while on screen:
/// turning it on mid-session snaps the state back without animation, and
/// turning it off restarts the loop.
private struct MotionAwareLoop: ViewModifier {
    let animation: Animation
    @Binding var isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onChange(of: reduceMotion) { sync() }
    }

    private func sync() {
        if reduceMotion {
            withTransaction(Transaction(animation: nil)) { isRunning = false }
        } else {
            withAnimation(animation) { isRunning = true }
        }
    }
}

extension View {
    /// `.animation(_:value:)` that is skipped under Reduce Motion.
    func appAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(ReduceMotionAwareAnimation(animation: animation, value: value))
    }

    /// Repeats one of the `AppAnimation` loop tokens by flipping `isRunning`
    /// to true. A loop that never ends is the motion WCAG 2.2.2 is about, so
    /// under Reduce Motion `isRunning` stays false.
    func motionAwareLoop(_ animation: Animation, autoreverses: Bool, isRunning: Binding<Bool>) -> some View {
        modifier(MotionAwareLoop(
            animation: animation.repeatForever(autoreverses: autoreverses),
            isRunning: isRunning
        ))
    }
}
