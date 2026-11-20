import SwiftUI

/// Bio Age dial. A 240° arc spanning chronological age ± the estimate's
/// largest possible drift (`PerformanceAgeEngine.maxDriftYears`), with a
/// bound label at each end and a marker at the user's estimated bio age.
///
/// Two strokes, not one. The full sweep is a hairline track — the scale
/// the number is read against. On top of it, from the younger bound up to
/// the user's value, sits the accent arc: a progress stroke, the one place
/// the craft rules sanction a gradient, because the fade *is* the reading.
/// The marker rides its head.
///
/// The dial draws geometry only — no number text inside, no title above.
/// Those live on `BioAgeHeroSection` so the dial can host a placeholder
/// (locked state) or a big number (unlocked state) in its centre
/// without conditional plumbing at this layer.
struct BioAgeDial: View {
    let chronologicalAge: Int
    /// Position of the marker in years. Pass `nil` to render the dial
    /// without one — used by the locked / building states where there's
    /// nothing to point at yet.
    let bioAge: Double?
    var size: CGFloat = 280
    /// How far the scale stretches in either direction from
    /// `chronologicalAge`. The dial's bound labels reflect this. Matches
    /// the engine's cap, so no estimate ever parks at an end it isn't at.
    var rangeHalfSpan: Int = Int(PerformanceAgeEngine.maxDriftYears)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pulse clock stops while the dial is scrolled out of view.
    @State private var isOnScreen = true

    private var lowerBound: Double { Double(chronologicalAge - rangeHalfSpan) }
    private var upperBound: Double { Double(chronologicalAge + rangeHalfSpan) }
    /// Arc sweep in degrees. 240° leaves the opening at the bottom, with
    /// the bound labels at its two ends (180° = exactly horizontal, 270° =
    /// too tight, 240° splits the difference).
    private var sweep: Double { Self.sweepDegrees }
    private static let sweepDegrees: Double = 240
    /// How far outside the arc the bound labels sit, so the stroke
    /// doesn't collide with the digits.
    private static let labelGap: CGFloat = 16
    /// Vertical room kept for a bound label below its centre, enough for
    /// the label at large text sizes.
    private static let boundLabelHeightAllowance: CGFloat = 26

    /// The empty strip at the bottom of a dial of `size`, under its bound
    /// labels. Derived from the same sweep and label radius `labelAt`
    /// uses, so a layout that tucks content into the opening follows any
    /// change to the label geometry.
    static func openBandHeight(size: CGFloat) -> CGFloat {
        let labelRadius = size / 2 + labelGap
        let labelCentreBelowMiddle = CGFloat(-cos(sweepDegrees / 2 * .pi / 180)) * labelRadius
        return size / 2 - labelCentreBelowMiddle - boundLabelHeightAllowance
    }
    private var startAngle: Double { -90 - sweep / 2 }

    /// Where the marker actually sits, clamped into the dial's range so an
    /// out-of-scale estimate parks at the end rather than off the arc.
    private var markerValue: Double? {
        bioAge.map { max(lowerBound, min(upperBound, $0)) }
    }

    /// The value's position along the sweep, 0…1 from the younger bound.
    private var progress: Double {
        guard let markerValue, upperBound > lowerBound else { return 0 }
        return (markerValue - lowerBound) / (upperBound - lowerBound)
    }

    private var lineWidth: CGFloat { 3 }

    var body: some View {
        ZStack {
            track
            chronologicalTick
            if bioAge != nil {
                progressArc
                if !reduceMotion { markerPulse }
                marker
            }
            boundLabels
        }
        .frame(width: size, height: size)
        .onScrollVisibilityChange { isOnScreen = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Arcs

    private var track: some View {
        Circle()
            .trim(from: trimStart, to: trimEnd)
            .stroke(
                AppColor.glassBorder,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(Self.arcRotation))
    }

    private var progressArc: some View {
        Circle()
            .trim(from: trimStart, to: trimStart + (trimEnd - trimStart) * CGFloat(progress))
            .stroke(
                AngularGradient(
                    colors: [AppColor.accentPrimary, AppColor.accentLight],
                    center: .center,
                    startAngle: .degrees(Double(trimStart) * 360),
                    endAngle: .degrees(Double(trimEnd) * 360)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(Self.arcRotation))
            .appAnimation(AppAnimation.springSmooth, value: progress)
    }

    /// Convert sweep angle to a trim range. SwiftUI's Circle trim runs 0…1
    /// clockwise from the right; we want a 240° arc with a 120° gap, so trim covers `(360 - sweep) / 720` to `1 - that`.
    /// That leaves the gap facing right, and `arcRotation` turns it to face
    /// down. The marker, tick and labels place themselves with `angle(for:)`
    /// in the same frame, so the stroke and the marker always agree.
    private static let arcRotation: Double = 90
    private var trimStart: CGFloat { CGFloat((360 - sweep) / 720) }
    private var trimEnd: CGFloat { 1 - trimStart }

    // MARK: - Marker

    /// A disc at the head of the progress arc, ringed in the app
    /// background so it stays legible where it overlaps the track. A
    /// neutral drop lifts it; emphasis never comes from a coloured glow.
    @ViewBuilder
    private var marker: some View {
        if let markerValue {
            Circle()
                .fill(AppColor.accentLight)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().strokeBorder(AppColor.background, lineWidth: 2)
                }
                .appShadow(AppShadow.glassSubtle)
                .offset(y: -(size / 2))
                .rotationEffect(.degrees(angle(for: markerValue)))
                .appAnimation(AppAnimation.springSmooth, value: markerValue)
        }
    }

    /// A hairline ring that leaves the marker and fades every few seconds,
    /// so the reading reads as live rather than printed. Driven by the
    /// timeline clock rather than a looping animation, and not drawn at
    /// all under Reduce Motion.
    @ViewBuilder
    private var markerPulse: some View {
        if let markerValue {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isOnScreen)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.pulsePeriod) / Self.pulsePeriod
                Circle()
                    .strokeBorder(AppColor.accentLight, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .scaleEffect(1 + phase * 1.6)
                    .opacity(0.6 * (1 - phase))
            }
            .offset(y: -(size / 2))
            .rotationEffect(.degrees(angle(for: markerValue)))
            .appAnimation(AppAnimation.springSmooth, value: markerValue)
            .accessibilityHidden(true)
        }
    }

    /// Seconds per pulse — slow enough to read as breathing, not alerting.
    private static let pulsePeriod: Double = 2.8

    // MARK: - Chronological age

    /// A tick at the user's actual age — the dial's centre — so the marker
    /// reads as younger or older against something on the scale itself.
    /// Uncaptioned: a label here stacked a second caption under the hero's
    /// eyebrow, and the line under the dial already names the age.
    private var chronologicalTick: some View {
        Capsule()
            .fill(AppColor.textSecondary)
            .frame(width: 1.5, height: 12)
            .offset(y: -(size / 2))
            .rotationEffect(.degrees(angle(for: Double(chronologicalAge))))
            .accessibilityHidden(true)
    }

    // MARK: - Bound labels

    /// The two ends of the scale, so the number in the middle has something
    /// to be read against.
    private var boundLabels: some View {
        ZStack {
            labelAt(angle: angle(for: lowerBound), value: lowerBound)
            labelAt(angle: angle(for: upperBound), value: upperBound)
        }
    }

    private func labelAt(angle deg: Double, value: Double) -> some View {
        let radius = size / 2 + Self.labelGap
        let radians = deg * .pi / 180
        // Standard polar-to-cartesian, then adjust for the fact that 0° in
        // our angle system points up (-90° in screen coords).
        let x = sin(radians) * radius
        let y = -cos(radians) * radius
        return Text(Self.yearLabel(value))
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.textSecondary)
            .offset(x: x, y: y)
    }

    // MARK: - Helpers

    /// Maps a bio-age value to its angle in the dial's coordinate system.
    /// `startAngle` + the sweep is the arc; we interpolate the value across
    /// it.
    private func angle(for age: Double) -> Double {
        let range = upperBound - lowerBound
        guard range > 0 else { return -90 }
        let fraction = (age - lowerBound) / range
        return startAngle + 90 + fraction * sweep
    }

    /// The scale only. The value itself is announced by the number in the
    /// dial's centre, so repeating it here would read it twice.
    private var accessibilityDescription: String {
        String(localized: "Biological age scale, \(Self.yearLabel(lowerBound)) to \(Self.yearLabel(upperBound)) years")
    }

    /// The bounds are chronological age ± a whole number of years, so they
    /// print without a decimal ("30", not "30.0").
    private static func yearLabel(_ value: Double) -> String {
        Int(value).formatted()
    }
}

#Preview("Locked (no marker)") {
    ZStack {
        PageBackdrop().ignoresSafeArea()
        BioAgeDial(chronologicalAge: 26, bioAge: nil)
    }
}

#Preview("Unlocked, marker at 24.5") {
    ZStack {
        PageBackdrop().ignoresSafeArea()
        BioAgeDial(chronologicalAge: 26, bioAge: 24.5)
    }
}
