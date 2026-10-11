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
                TimelineView(.animation) { context in
                    heart.scaleEffect(scale(at: context.date))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Swells over the first 18% of each beat, releases over the next
    /// 41%, then rests. Driven by the clock rather than a phase animator
    /// so the period is exactly one beat.
    private func scale(at date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: beat) / beat
        let swell = phase < 0.18 ? phase / 0.18 : max(0, 1 - (phase - 0.18) / 0.41)
        return 1 + 0.14 * sin(swell * .pi / 2)
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(WatchPalette.heart)
            .shadow(color: WatchPalette.heart.opacity(isLuminanceReduced ? 0 : 0.8), radius: size * 0.3)
    }
}
