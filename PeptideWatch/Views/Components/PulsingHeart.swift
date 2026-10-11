import SwiftUI

/// The Recovery page's hero: a heart that beats at the user's own
/// resting heart rate, glowing like the system Heart Rate app's.
/// Holds still in Always On and under Reduce Motion.
struct PulsingHeart: View {
    let bpm: Int
    var size: CGFloat = 64

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One beat: a quick swell, then a slower release. Sized from the
    /// real rate so 50 bpm and 80 bpm look different on the wrist.
    private var beat: Double { 60 / Double(min(max(bpm, 35), 180)) }

    var body: some View {
        Group {
            if isLuminanceReduced || reduceMotion {
                heart
            } else {
                heart
                    .phaseAnimator([1.0, 1.14, 1.0]) { content, scale in
                        content.scaleEffect(scale)
                    } animation: { scale in
                        scale > 1 ? Animation.easeOut(duration: beat * 0.18) : Animation.easeIn(duration: beat * 0.41)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(WatchPalette.heart)
            .shadow(color: WatchPalette.heart.opacity(isLuminanceReduced ? 0 : 0.8), radius: size * 0.3)
    }
}
