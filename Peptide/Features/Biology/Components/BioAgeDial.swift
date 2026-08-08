import SwiftUI

/// Bio Age dial. A 240° arc spanning chronological-age ±5 years, with a
/// bound label at each end and a marker at the user's estimated bio age.
///
/// Two strokes, not one. The full sweep is a hairline track — the scale
/// the number is read against. On top of it, from the younger bound up to
/// the user's value, sits the accent arc: a progress stroke, the one place
/// the craft rules sanction a gradient, because the fade *is* the reading.
/// The marker rides its head.
///
/// The dial draws geometry only — no number text inside, no title above.
/// Those live on `BioAgeHeroSection` so the dial can host a particle
/// cluster (locked state) or a big number (unlocked state) in its centre
/// without conditional plumbing at this layer.
struct BioAgeDial: View {
    let chronologicalAge: Int
    /// Position of the marker in years. Pass `nil` to render the dial
    /// without one — used by the locked / building states where there's
    /// nothing to point at yet.
    let bioAge: Double?
    var size: CGFloat = 280
    /// How far the scale stretches in either direction from
    /// `chronologicalAge`. The dial's bound labels reflect this.
    var rangeHalfSpan: Int = 5

    private var lowerBound: Double { Double(chronologicalAge - rangeHalfSpan) }
    private var upperBound: Double { Double(chronologicalAge + rangeHalfSpan) }
    /// Arc sweep in degrees. 240° gives the open-mouth-up look (180° =
    /// exactly horizontal, 270° = too tight at the top, 240° splits the
    /// difference).
    private var sweep: Double { 240 }
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
            if bioAge != nil {
                progressArc
                marker
            }
            boundLabels
        }
        .frame(width: size, height: size)
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
            .rotationEffect(.degrees(startAngle + 90))
    }

    private var progressArc: some View {
        Circle()
            .trim(from: trimStart, to: trimStart + (trimEnd - trimStart) * CGFloat(progress))
            .stroke(
                AngularGradient(
                    colors: [AppColor.accentPrimary, AppColor.accentLight],
                    center: .center,
                    startAngle: .degrees(startAngle),
                    endAngle: .degrees(startAngle + sweep)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(startAngle + 90))
            .animation(AppAnimation.springSmooth, value: progress)
    }

    /// Convert sweep angle to a trim range. SwiftUI's Circle trim runs 0…1
    /// clockwise from the right; we want our arc centred at the top with a
    /// 240° sweep, so trim covers `(360 - sweep) / 720` to `1 - that`.
    private var trimStart: CGFloat { CGFloat((360 - sweep) / 720) }
    private var trimEnd: CGFloat { 1 - trimStart }

    // MARK: - Marker

    /// A disc at the head of the progress arc, ringed in the app
    /// background so it stays legible where it overlaps the track. The
    /// coloured drop is elevation under a filled shape, which is how every
    /// accent medallion in the app reads as floating — not a halo behind a
    /// glyph.
    @ViewBuilder
    private var marker: some View {
        if let markerValue {
            Circle()
                .fill(AppColor.accentLight)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().strokeBorder(AppColor.background, lineWidth: 2)
                }
                .shadow(color: AppColor.accentGlow, radius: 8)
                .offset(y: -(size / 2))
                .rotationEffect(.degrees(angle(for: markerValue)))
                .animation(AppAnimation.springSmooth, value: markerValue)
        }
    }

    // MARK: - Bound labels

    /// The two ends of the scale, so the number in the middle has something
    /// to be read against. The localized number formatter picks the right
    /// decimal separator per locale.
    private var boundLabels: some View {
        ZStack {
            labelAt(angle: angle(for: lowerBound), value: lowerBound)
            labelAt(angle: angle(for: upperBound), value: upperBound)
        }
    }

    private func labelAt(angle deg: Double, value: Double) -> some View {
        // Drop labels outside the arc so the stroke doesn't collide with
        // the digits.
        let radius = size / 2 + 16
        let radians = deg * .pi / 180
        // Standard polar-to-cartesian, then adjust for the fact that 0° in
        // our angle system points up (-90° in screen coords).
        let x = sin(radians) * radius
        let y = -cos(radians) * radius
        return Text(Self.boundFormatter.string(from: NSNumber(value: value))
                    ?? String(format: "%.1f", value))
            .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
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

    private static let boundFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()

    private var accessibilityDescription: String {
        let low = String(format: "%.1f", lowerBound)
        let high = String(format: "%.1f", upperBound)
        guard let bioAge else {
            return String(format: String(localized: "Bio age scale, %@ to %@ years"), low, high)
        }
        return String(format: String(localized: "Bio age %@, on a scale from %@ to %@ years"),
                      String(format: "%.1f", bioAge), low, high)
    }
}

#Preview("Locked (no marker)") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeDial(chronologicalAge: 26, bioAge: nil)
    }
}

#Preview("Unlocked, marker at 24.5") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeDial(chronologicalAge: 26, bioAge: 24.5)
    }
}
