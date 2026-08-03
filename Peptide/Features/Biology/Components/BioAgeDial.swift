import SwiftUI

/// Bevel-style Bio Age dial. A 240° arc spanning chronological-
/// age ±5 years, with scale markers at each integer, a left
/// label (lower bound) + right label (upper bound), and a needle
/// dot at the user's estimated bio age.
///
/// The dial draws geometry only — no number text inside, no
/// title above. Those live on `BioAgeHeroSection` so the dial
/// can host a particle cluster (locked state) or a big number
/// (unlocked state) in its centre without conditional plumbing
/// at this layer.
struct BioAgeDial: View {
    let chronologicalAge: Int
    /// Position of the needle in years. Pass `nil` to render the
    /// dial without a needle — used by the locked / building
    /// states where there's nothing to point at yet.
    let bioAge: Double?
    var size: CGFloat = 280
    /// How far the scale stretches in either direction from
    /// `chronologicalAge`. Bevel uses ±5; the dial's labels
    /// reflect this.
    var rangeHalfSpan: Int = 5

    private var lowerBound: Double { Double(chronologicalAge - rangeHalfSpan) }
    private var upperBound: Double { Double(chronologicalAge + rangeHalfSpan) }
    /// Arc sweep in degrees. 240° gives the open-mouth-up look
    /// Bevel uses (180° = exactly horizontal, 270° = too tight at
    /// the top, 240° splits the difference).
    private var sweep: Double { 240 }
    private var startAngle: Double { -90 - sweep / 2 }
    private var endAngle: Double { -90 + sweep / 2 }

    var body: some View {
        ZStack {
            arc
            tickMarks
            boundLabels
            if let bioAge { needle(at: bioAge) }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Arc

    private var arc: some View {
        Circle()
            .trim(from: trimStart, to: trimEnd)
            .stroke(
                AppColor.glassBorder.opacity(0.55),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
            .rotationEffect(.degrees(startAngle + 90))
    }

    /// Convert sweep angle to a trim range. SwiftUI's Circle
    /// trim runs 0…1 clockwise from the right; we want our arc
    /// centred at the top with a 240° sweep, so trim covers
    /// `(360 - sweep) / 720` to `1 - that`.
    private var trimStart: CGFloat { CGFloat((360 - sweep) / 720) }
    private var trimEnd: CGFloat { 1 - trimStart }

    // MARK: - Tick marks

    /// One short radial tick per year across the range. Center
    /// ticks (cohort age) get extra weight; the rest are quiet
    /// hairlines.
    private var tickMarks: some View {
        ZStack {
            ForEach(0...(rangeHalfSpan * 2), id: \.self) { offset in
                tickMark(at: Double(chronologicalAge - rangeHalfSpan + offset))
            }
        }
    }

    private func tickMark(at age: Double) -> some View {
        let isCenter = Int(age) == chronologicalAge
        let length: CGFloat = isCenter ? 14 : 8
        let opacity: Double = isCenter ? 0.85 : 0.4
        let degrees = angle(for: age)
        return Capsule()
            .fill(AppColor.textPrimary.opacity(opacity))
            .frame(width: 1.2, height: length)
            .offset(y: -(size / 2 - length / 2 - 6))
            .rotationEffect(.degrees(degrees))
    }

    // MARK: - Bound labels

    /// "21,1" / "31,1" labels at the arc's ends — comma decimal
    /// matches Bevel's screenshot (which is from a locale using
    /// comma decimal). The localized number formatter handles
    /// the right separator per user locale.
    private var boundLabels: some View {
        ZStack {
            labelAt(angle: angle(for: lowerBound), value: lowerBound)
            labelAt(angle: angle(for: upperBound), value: upperBound)
        }
    }

    private func labelAt(angle deg: Double, value: Double) -> some View {
        // Drop labels slightly outside the arc so the radial
        // tick marks don't collide with the digits.
        let radius = size / 2 + 14
        let radians = deg * .pi / 180
        // Standard polar-to-cartesian, then adjust for the fact
        // that 0° in our angle system points up (-90° in screen
        // coords).
        let x = sin(radians) * radius
        let y = -cos(radians) * radius
        return Text(formatted(value))
            .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
            .foregroundStyle(AppColor.textPrimary.opacity(0.55))
            .offset(x: x, y: y)
    }

    // MARK: - Needle

    /// Filled circle at the bioAge position, sized to read
    /// without needing a stem. Bevel just uses a dot — no stem.
    private func needle(at age: Double) -> some View {
        let clamped = max(lowerBound, min(upperBound, age))
        let degrees = angle(for: clamped)
        return Circle()
            .fill(AppColor.textPrimary)
            .frame(width: 12, height: 12)
            .overlay {
                Circle().stroke(AppColor.accentLight, lineWidth: 1)
            }
            .offset(y: -(size / 2 - 18))
            .rotationEffect(.degrees(degrees))
            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: clamped)
    }

    // MARK: - Helpers

    /// Maps a bio-age value to its angle in the dial's coordinate
    /// system. `startAngle`…`endAngle` is the sweep; we
    /// interpolate the value across it.
    private func angle(for age: Double) -> Double {
        let range = upperBound - lowerBound
        guard range > 0 else { return -90 }
        let fraction = (age - lowerBound) / range
        return startAngle + 90 + fraction * sweep
    }

    private func formatted(_ value: Double) -> String {
        // One decimal to match Bevel's "21,1" / "31,1" reading.
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private var accessibilityDescription: String {
        guard let bioAge else {
            return "Bio age range \(lowerBound) to \(upperBound)"
        }
        return "Bio age \(String(format: "%.1f", bioAge)), range \(lowerBound) to \(upperBound)"
    }
}

#Preview("Locked (no needle)") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeDial(chronologicalAge: 26, bioAge: nil)
    }
    .preferredColorScheme(.dark)
}

#Preview("Unlocked, needle at 26.1") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeDial(chronologicalAge: 26, bioAge: 26.1)
    }
    .preferredColorScheme(.dark)
}
