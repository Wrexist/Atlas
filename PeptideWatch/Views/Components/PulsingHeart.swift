import SwiftUI

/// One clock for everything on the Recovery page that beats, so the heart,
/// its ripples and the ECG trace stay in step at the user's real rate.
enum Heartbeat {
    /// Where the R wave peaks within a beat. The heart's swell and each
    /// ripple start here, so they land on the spike of the trace.
    static let rPeak = 0.24

    static func period(bpm: Int) -> Double { 60 / Double(min(max(bpm, 35), 180)) }

    /// Beats elapsed since the reference date, fractional.
    static func beats(at date: Date, bpm: Int) -> Double {
        date.timeIntervalSinceReferenceDate / period(bpm: bpm)
    }

    static func fraction(_ value: Double) -> Double { value - value.rounded(.down) }

    /// A stylised PQRST complex, roughly −0.3…1, for phase 0…1.
    static func voltage(at phase: Double) -> Double {
        func bump(_ center: Double, _ width: Double, _ height: Double) -> Double {
            height * exp(-pow((phase - center) / width, 2))
        }
        return bump(0.12, 0.025, 0.12)
            + bump(rPeak - 0.025, 0.008, -0.15)
            + bump(rPeak, 0.012, 1)
            + bump(rPeak + 0.025, 0.01, -0.28)
            + bump(0.45, 0.05, 0.24)
    }
}

/// The Recovery page's hero: a heart that beats at the user's own resting
/// heart rate and sends a ripple out on every beat. Holds still when there
/// is no resting heart rate, in Always On and under Reduce Motion, and
/// stops drawing while its page is off screen.
struct PulsingHeart: View {
    let bpm: Int?
    var size: CGFloat = 64

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPageIsActive) private var isActive

    private var isStill: Bool { bpm == nil || isLuminanceReduced || reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill || !isActive)) { context in
            let phase = bpm.map { Heartbeat.fraction(Heartbeat.beats(at: context.date, bpm: $0) - Heartbeat.rPeak) } ?? 0
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    ripple(age: (phase + Double(index)) / 2)
                }
                heart
                    .scaleEffect(isStill ? 1 : swell(at: phase))
            }
        }
        .frame(width: size * 1.9, height: size * 1.6)
        .accessibilityHidden(true)
    }

    /// Swells over the first 18% of each beat, releases over the next
    /// 41%, then rests until the next R wave.
    private func swell(at phase: Double) -> CGFloat {
        let swell = phase < 0.18 ? phase / 0.18 : max(0, 1 - (phase - 0.18) / 0.41)
        return 1 + 0.14 * sin(swell * .pi / 2)
    }

    /// Each ripple lives two beats, so one is always fading while the
    /// next starts.
    private func ripple(age: Double) -> some View {
        Circle()
            .stroke(WatchPalette.heart, lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(1 + age * 0.85)
            .opacity(isStill ? 0 : (1 - age) * 0.6)
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(WatchPalette.heart)
            .shadow(color: WatchPalette.heart.opacity(isLuminanceReduced ? 0 : 0.8), radius: size * 0.3)
    }
}

/// A live ECG strip that scrolls at the user's resting rate, newest beat
/// at the right edge, older trace fading out to the left. Paused, like the
/// heart, while its page is off screen.
struct ECGTrace: View {
    let bpm: Int
    /// How many beats fit across the strip.
    var beatsShown = 2.4

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchPageIsActive) private var isActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isLuminanceReduced || reduceMotion || !isActive)) { context in
            Canvas { graphics, size in
                guard size.width > 0 else { return }
                let now = Heartbeat.beats(at: context.date, bpm: bpm)
                var trace = Path()
                var lastPoint = CGPoint.zero
                for x in stride(from: 0, through: size.width, by: 1.5) {
                    let beatsAgo = Double((size.width - x) / size.width) * beatsShown
                    let voltage = Heartbeat.voltage(at: Heartbeat.fraction(now - beatsAgo))
                    let point = CGPoint(x: x, y: size.height * 0.62 - voltage * size.height * 0.55)
                    if x == 0 { trace.move(to: point) } else { trace.addLine(to: point) }
                    lastPoint = point
                }
                graphics.stroke(
                    trace,
                    with: .linearGradient(
                        Gradient(colors: [WatchPalette.heart.opacity(0), WatchPalette.heart]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                let dot = CGRect(x: lastPoint.x - 2.5, y: lastPoint.y - 2.5, width: 5, height: 5)
                graphics.fill(Path(ellipseIn: dot), with: .color(WatchPalette.heart))
            }
        }
        .accessibilityHidden(true)
    }
}
