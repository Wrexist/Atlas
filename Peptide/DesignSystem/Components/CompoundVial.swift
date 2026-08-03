import SwiftUI

/// Symmetrical, category-aware vial visual used across the Home
/// inventory shelf, the onboarding teaser, the share card, and the
/// protocol calendar panels. Replaces the older `VialIllustration`
/// which had per-compound 1-of-14 hardcoded colours and fell back to
/// a gray "unknown" palette for everything else.
///
/// Same-category compounds share a cap finish and a base hue so a
/// glance reads as "these are all cognitive peptides"; per-compound
/// hue offsets keep individual vials distinguishable inside the family.
struct CompoundVial: View {
    let compoundName: String
    let category: PeptideCategory?
    let liquidLevel: Double
    let labelText: String?
    let size: CompoundVialSize

    init(
        compoundName: String,
        category: PeptideCategory? = nil,
        liquidLevel: Double = 1.0,
        labelText: String? = nil,
        size: CompoundVialSize = .md
    ) {
        self.compoundName = compoundName
        self.category = category
        self.liquidLevel = max(0, min(1, liquidLevel))
        self.labelText = labelText
        self.size = size
    }

    private var palette: VialPalette {
        VialPalette.colors(for: compoundName, category: category)
    }

    var body: some View {
        let m = size.metrics
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    cap(metrics: m)
                    stopper(metrics: m)
                    glass(metrics: m)
                }
                .frame(width: m.width, height: m.height)
            }
            .frame(width: m.width, height: m.height)

            contactShadow(metrics: m)
                .padding(.top, m.shadowGap)
        }
        .frame(
            width: max(m.width, m.shadowWidth),
            height: m.height + m.shadowGap + m.shadowHeight
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private func cap(metrics m: VialMetrics) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: m.capCornerRadius, style: .continuous)
                .fill(palette.capTint.gradient)
                .frame(width: m.capWidth, height: m.capHeight)
                .overlay {
                    // Edge-of-cap highlight — single hairline so the
                    // metallic gradient reads as a curved surface and
                    // not a flat-fill rectangle.
                    RoundedRectangle(cornerRadius: m.capCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
                }

            // Top-edge glint. Thin, off-centre, soft — sells the
            // "machined metal" finish without a heavy-handed shine.
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: m.capWidth * 0.55, height: 1.2)
                .offset(y: 1.5)
                .blur(radius: 0.2)
        }
    }

    private func stopper(metrics m: VialMetrics) -> some View {
        Rectangle()
            .fill(Color(white: 0.18))
            .frame(width: m.stopperWidth, height: m.stopperHeight)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.5)
            }
    }

    private func glass(metrics m: VialMetrics) -> some View {
        let bodyShape = RoundedRectangle(cornerRadius: m.bodyCornerRadius, style: .continuous)
        return ZStack(alignment: .bottom) {
            // Glass plate — always present so an empty vial still
            // looks like a vial, not a floating cap.
            bodyShape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // Liquid. Vertical gradient + alpha taper near the top
            // suggests a meniscus without drawing it explicitly.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            palette.highlight.opacity(0.55),
                            palette.highlight.opacity(0.92),
                            palette.fill,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: m.bodyHeight * liquidLevel)
                .animation(.easeInOut(duration: 0.8), value: liquidLevel)

            // Inner left highlight — full-height crisp Bézier, soft
            // alpha. Replaces the dot-shaped quadratic stroke that
            // the old illustration drew.
            verticalHighlight(metrics: m)

            // Soft inner shadow on the right edge gives the body
            // some volume without resorting to 3D clip-art.
            innerRightShadow(metrics: m)

            // Floating glass-material label inside the body. Tinted
            // to the compound colour so it reads as part of the vial
            // rather than a sticker pasted on top.
            if let labelText {
                labelChip(metrics: m, text: labelText)
                    .padding(.bottom, m.labelBottomInset)
            }

            // Body stroke last so it sits on top of every fill.
            bodyShape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
        }
        .frame(width: m.bodyWidth, height: m.bodyHeight)
        .clipShape(bodyShape)
    }

    private func verticalHighlight(metrics m: VialMetrics) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.30),
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: max(2, m.bodyWidth * 0.06), height: m.bodyHeight * 0.75)
            .blur(radius: 0.4)
            .offset(x: -m.bodyWidth * 0.34, y: -m.bodyHeight * 0.05)
            .allowsHitTesting(false)
    }

    private func innerRightShadow(metrics m: VialMetrics) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.22)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: m.bodyWidth * 0.45)
            .offset(x: m.bodyWidth * 0.275)
            .allowsHitTesting(false)
    }

    private func labelChip(metrics m: VialMetrics, text: String) -> some View {
        Text(text)
            .font(.system(size: m.labelFontSize, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, m.labelPadding)
            .padding(.vertical, m.labelPadding * 0.55)
            .frame(width: m.labelWidth)
            .glassControl(
                .rect(cornerRadius: m.labelCornerRadius),
                // The vial label is a coloured band by design, so it takes
                // more tint than a control would. `Glass.tint` saturates
                // much faster than the painted legacy wash, hence the split.
                tint: palette.fill.opacity(0.22),
                legacyTint: palette.fill.opacity(0.55),
                border: Color.white.opacity(0.35),
                interactive: false
            )
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.8)
    }

    private func contactShadow(metrics m: VialMetrics) -> some View {
        // Radial gradient ellipse — falls off cleanly instead of the
        // hard-edged ellipse the old illustration used. Two stacked
        // layers give the shadow a tight core and a soft halo.
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.45), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: m.shadowWidth * 0.5
                    )
                )
                .frame(width: m.shadowWidth, height: m.shadowHeight)
                .blur(radius: 1.5)

            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: m.shadowWidth * 0.5, height: m.shadowHeight * 0.6)
                .blur(radius: 0.8)
        }
    }

    private var accessibilityLabel: String {
        let nameSpoken = labelText ?? compoundName
        let percent = Int((liquidLevel * 100).rounded())
        return "\(nameSpoken), \(percent) percent remaining"
    }
}

// MARK: - Sizes

enum CompoundVialSize: Sendable {
    case sm, md, lg

    fileprivate var metrics: VialMetrics {
        switch self {
        case .sm: VialMetrics(scale: 0.5)
        case .md: VialMetrics(scale: 1.0)
        case .lg: VialMetrics(scale: 1.5)
        }
    }
}

fileprivate struct VialMetrics {
    let width: CGFloat
    let height: CGFloat
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat
    let bodyCornerRadius: CGFloat
    let capWidth: CGFloat
    let capHeight: CGFloat
    let capCornerRadius: CGFloat
    let stopperWidth: CGFloat
    let stopperHeight: CGFloat
    let labelWidth: CGFloat
    let labelFontSize: CGFloat
    let labelPadding: CGFloat
    let labelCornerRadius: CGFloat
    let labelBottomInset: CGFloat
    let shadowWidth: CGFloat
    let shadowHeight: CGFloat
    let shadowGap: CGFloat

    init(scale: CGFloat) {
        // Slimmer + taller proportions than the previous vial — sells
        // "premium" better than the squat 70×92 box the old metrics
        // used.
        self.width = 72 * scale
        self.height = 132 * scale
        self.bodyWidth = 60 * scale
        self.bodyHeight = 108 * scale
        self.bodyCornerRadius = 11 * scale
        self.capWidth = 48 * scale
        self.capHeight = 18 * scale
        self.capCornerRadius = 4 * scale
        self.stopperWidth = 52 * scale
        self.stopperHeight = 5 * scale
        self.labelWidth = 52 * scale
        self.labelFontSize = max(7, 9.5 * scale)
        self.labelPadding = 4.5 * scale
        self.labelCornerRadius = 5 * scale
        self.labelBottomInset = 10 * scale
        self.shadowWidth = 84 * scale
        self.shadowHeight = 10 * scale
        self.shadowGap = 4 * scale
    }
}

#Preview("By category") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.lg) {
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                CompoundVial(compoundName: "Semax", category: .cognitive, liquidLevel: 0.85, labelText: "SEMAX")
                CompoundVial(compoundName: "Selank", category: .cognitive, liquidLevel: 0.62, labelText: "SELANK")
                CompoundVial(compoundName: "Cerebrolysin", category: .cognitive, liquidLevel: 0.40, labelText: "CEREB")
            }
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                CompoundVial(compoundName: "BPC-157", category: .growth, liquidLevel: 0.85, labelText: "BPC-157")
                CompoundVial(compoundName: "CJC-1295", category: .growth, liquidLevel: 0.45, labelText: "CJC-1295")
                CompoundVial(compoundName: "Sermorelin", category: .growth, liquidLevel: 0.70, labelText: "SERM")
            }
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                CompoundVial(compoundName: "Retatrutide", category: .metabolic, liquidLevel: 0.78, labelText: "RETA")
                CompoundVial(compoundName: "Tirzepatide", category: .metabolic, liquidLevel: 0.55, labelText: "TIRZ")
                CompoundVial(compoundName: "Epitalon",   category: .antiAging, liquidLevel: 0.80, labelText: "EPI")
            }
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Sizes") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HStack(alignment: .bottom, spacing: Spacing.lg) {
            CompoundVial(compoundName: "BPC-157", liquidLevel: 0.7, labelText: "BPC-157", size: .sm)
            CompoundVial(compoundName: "BPC-157", liquidLevel: 0.7, labelText: "BPC-157\n5 mg", size: .md)
            CompoundVial(compoundName: "BPC-157", liquidLevel: 0.7, labelText: "BPC-157\n5 mg", size: .lg)
        }
    }
    .preferredColorScheme(.dark)
}
