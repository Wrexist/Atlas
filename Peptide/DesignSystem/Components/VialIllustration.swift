import SwiftUI

/// Stylised 3-D vial used on the medication-preview onboarding step,
/// the Home-tab inventory shelf, and (eventually) the medication detail
/// hero. Pure SwiftUI — no SVG / image assets — so the illustration
/// scales cleanly across the three documented sizes.
///
/// `liquidLevel` is a 0…1 fraction of the body height. Implicit animation
/// is wired so callers only need to mutate the value with
/// `withAnimation { … }` and the liquid drains over the spec's 800 ms.
struct VialIllustration: View {
    let compoundName: String
    let liquidLevel: Double
    let labelText: String?
    let size: VialSize

    init(
        compoundName: String,
        liquidLevel: Double = 1.0,
        labelText: String? = nil,
        size: VialSize = .md
    ) {
        self.compoundName = compoundName
        self.liquidLevel = max(0, min(1, liquidLevel))
        self.labelText = labelText
        self.size = size
    }

    private var palette: VialPalette { VialPalette.colors(for: compoundName) }

    var body: some View {
        let metrics = size.metrics
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear

                VStack(spacing: 0) {
                    cap(metrics: metrics)
                    stopper(metrics: metrics)
                    glassWithLiquid(metrics: metrics)
                }
                .frame(width: metrics.width, height: metrics.height)
            }
            .frame(width: metrics.width, height: metrics.height)

            surface(metrics: metrics)
                .padding(.top, metrics.surfaceGap)
        }
        .frame(width: metrics.width, height: metrics.height + metrics.surfaceGap + metrics.surfaceHeight)
    }

    // MARK: - Pieces

    private func cap(metrics: VialMetrics) -> some View {
        RoundedRectangle(cornerRadius: metrics.capCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.92), Color(white: 0.74)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: metrics.capWidth, height: metrics.capHeight)
            .overlay {
                RoundedRectangle(cornerRadius: metrics.capCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            }
    }

    private func stopper(metrics: VialMetrics) -> some View {
        Rectangle()
            .fill(Color(white: 0.32))
            .frame(width: metrics.stopperWidth, height: metrics.stopperHeight)
    }

    private func glassWithLiquid(metrics: VialMetrics) -> some View {
        let bodyShape = RoundedRectangle(cornerRadius: metrics.bodyCornerRadius, style: .continuous)
        return ZStack(alignment: .bottom) {
            // Liquid fill — drawn first so the glass wash and shine sit on top.
            bodyShape
                .fill(Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [palette.highlight.opacity(0.95), palette.fill],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: metrics.bodyHeight * liquidLevel)
                        .animation(.easeInOut(duration: 0.8), value: liquidLevel)
                }
                .clipShape(bodyShape)

            // Glass wash — gives the vial body its translucent tint even when
            // the liquid level is low.
            bodyShape
                .fill(Color.white.opacity(0.05))

            // Shine — short curved highlight on the upper-left quadrant.
            shine(metrics: metrics)

            // Label — white rounded card with compound name + amount.
            if let labelText {
                labelCard(metrics: metrics, text: labelText)
            }

            // Stroke last so it sits on top of every fill.
            bodyShape
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
        }
        .frame(width: metrics.bodyWidth, height: metrics.bodyHeight)
    }

    private func shine(metrics: VialMetrics) -> some View {
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width
                let h = proxy.size.height
                let topX = w * 0.18
                path.move(to: CGPoint(x: topX, y: h * 0.10))
                path.addQuadCurve(
                    to: CGPoint(x: topX + w * 0.06, y: h * 0.55),
                    control: CGPoint(x: topX - w * 0.05, y: h * 0.30)
                )
            }
            .stroke(Color.white.opacity(0.30), style: StrokeStyle(lineWidth: max(1, metrics.bodyWidth * 0.04), lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    private func labelCard(metrics: VialMetrics, text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.labelFontSize, weight: .bold))
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, metrics.labelPadding)
            .padding(.vertical, metrics.labelPadding * 0.6)
            .frame(width: metrics.labelWidth)
            .background {
                RoundedRectangle(cornerRadius: metrics.labelCornerRadius, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
    }

    private func surface(metrics: VialMetrics) -> some View {
        Ellipse()
            .fill(Color.white.opacity(0.08))
            .frame(width: metrics.surfaceWidth, height: metrics.surfaceHeight)
            .blur(radius: 0.5)
    }
}

// MARK: - Sizes

enum VialSize {
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
    let surfaceWidth: CGFloat
    let surfaceHeight: CGFloat
    let surfaceGap: CGFloat

    init(scale: CGFloat) {
        self.width = 80 * scale
        self.height = 120 * scale
        self.bodyWidth = 70 * scale
        self.bodyHeight = 92 * scale
        self.bodyCornerRadius = 12 * scale
        self.capWidth = 56 * scale
        self.capHeight = 16 * scale
        self.capCornerRadius = 4 * scale
        self.stopperWidth = 60 * scale
        self.stopperHeight = 4 * scale
        self.labelWidth = 56 * scale
        self.labelFontSize = max(7, 9 * scale)
        self.labelPadding = 5 * scale
        self.labelCornerRadius = 3 * scale
        self.surfaceWidth = 90 * scale
        self.surfaceHeight = 8 * scale
        self.surfaceGap = 4 * scale
    }
}

// MARK: - Colour map

struct VialPalette: Equatable {
    let fill: Color
    let highlight: Color

    static let unknown = VialPalette(
        fill:      Color(hex: 0x888780),
        highlight: Color(hex: 0xB4B2A9)
    )

    /// Case-insensitive, punctuation-tolerant lookup. "BPC-157", "bpc 157",
    /// and "BPC157" all match the same palette.
    static func colors(for compoundName: String) -> VialPalette {
        Self.mapping[normalize(compoundName)] ?? .unknown
    }

    /// Strips dashes / spaces / dots and lowercases so cosmetic variants
    /// of the same compound name don't fall through to the unknown
    /// palette. Exposed for tests; not API surface.
    static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let mapping: [String: VialPalette] = [
        "bpc157":      VialPalette(fill: Color(hex: 0x5DCAA5), highlight: Color(hex: 0x9FE1CB)),
        "tb500":       VialPalette(fill: Color(hex: 0xEF9F27), highlight: Color(hex: 0xFAC775)),
        "ghkcu":       VialPalette(fill: Color(hex: 0x378ADD), highlight: Color(hex: 0x85B7EB)),
        "ipamorelin":  VialPalette(fill: Color(hex: 0x7F77DD), highlight: Color(hex: 0xAFA9EC)),
        "cjc1295":     VialPalette(fill: Color(hex: 0x534AB7), highlight: Color(hex: 0x7F77DD)),
        "semaglutide": VialPalette(fill: Color(hex: 0x639922), highlight: Color(hex: 0x97C459)),
        "retatrutide": VialPalette(fill: Color(hex: 0x3B6D11), highlight: Color(hex: 0x639922)),
        "tirzepatide": VialPalette(fill: Color(hex: 0xD4537E), highlight: Color(hex: 0xED93B1)),
        // Two aliases for the same compound — spec lists "Melanotan / MT-1".
        "melanotan":   VialPalette(fill: Color(hex: 0xD85A30), highlight: Color(hex: 0xF0997B)),
        "mt1":         VialPalette(fill: Color(hex: 0xD85A30), highlight: Color(hex: 0xF0997B)),
        "epitalon":    VialPalette(fill: Color(hex: 0x0F6E56), highlight: Color(hex: 0x1D9E75)),
        "selank":      VialPalette(fill: Color(hex: 0x185FA5), highlight: Color(hex: 0x378ADD)),
        "semax":       VialPalette(fill: Color(hex: 0x0C447C), highlight: Color(hex: 0x185FA5)),
        "pt141":       VialPalette(fill: Color(hex: 0x993556), highlight: Color(hex: 0xD4537E)),
    ]
}

#Preview("Trio") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HStack(alignment: .bottom, spacing: Spacing.lg) {
            VialIllustration(compoundName: "Retatrutide", liquidLevel: 0.7, labelText: "Retatrutide\n5 mg")
            VialIllustration(compoundName: "Ipamorelin", liquidLevel: 0.5, labelText: "KLOW\n10 mg")
            VialIllustration(compoundName: "BPC-157", liquidLevel: 0.85, labelText: "BPC-157\n5 mg")
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Sizes") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HStack(alignment: .bottom, spacing: Spacing.lg) {
            VialIllustration(compoundName: "BPC-157", liquidLevel: 0.7, labelText: "BPC-157", size: .sm)
            VialIllustration(compoundName: "BPC-157", liquidLevel: 0.7, labelText: "BPC-157\n5 mg", size: .md)
            VialIllustration(compoundName: "BPC-157", liquidLevel: 0.7, labelText: "BPC-157\n5 mg", size: .lg)
        }
    }
    .preferredColorScheme(.dark)
}
