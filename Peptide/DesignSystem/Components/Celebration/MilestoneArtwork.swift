import SwiftUI

/// Native, resolution-independent relief artwork. Gradients describe bevels
/// and lighting on the object, not a glow behind a flat icon. All live labels
/// and numbers belong to the host so the artwork remains purely decorative.
struct MilestoneArtwork: View {
    enum Style {
        case medal
        case emblem
        case symbol
    }

    var symbol: String = "checkmark"
    var tint: Color = AppColor.accentPrimary
    var size: CGFloat = 96
    var style: Style = .medal
    var trigger: Int = 0
    var isActive: Bool = true
    var playsOnArrival: Bool = true

    var body: some View {
        artwork
            .frame(width: size, height: size)
            .milestoneMotion(trigger: trigger, isActive: isActive, playsOnArrival: playsOnArrival, style: motionStyle)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var motionStyle: MilestoneMotionStyle {
        if symbol == "flame.fill" { return .flicker }
        if style == .emblem || symbol == "trophy.fill" { return .shine }
        return .settle
    }

    @ViewBuilder
    private var artwork: some View {
        if style == .symbol {
            reliefSymbol
                .padding(size * 0.12)
        } else {
            ZStack {
                if style == .medal {
                    ribbon.rotationEffect(.degrees(22)).offset(x: -size * 0.16, y: size * 0.23)
                    ribbon.rotationEffect(.degrees(-22)).offset(x: size * 0.16, y: size * 0.23)
                }
                MedallionShape()
                    .fill(tint.gradient)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .offset(y: size * 0.025)
                MedallionShape()
                    .fill(LinearGradient(
                        colors: [AppColor.onAccent, tint, tint.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: size * 0.78, height: size * 0.78)
                MedallionShape()
                    .fill(LinearGradient(
                        colors: [AppColor.surfaceElevated, AppColor.surfaceSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: size * 0.69, height: size * 0.69)
                MedallionShape()
                    .stroke(tint.opacity(0.4), lineWidth: 1)
                    .frame(width: size * 0.59, height: size * 0.59)
                if style == .emblem {
                    Image("AtlasLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size * 0.43, height: size * 0.43)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
                } else {
                    reliefSymbol
                        .frame(width: size * 0.36, height: size * 0.36)
                }
            }
            .offset(y: style == .medal ? -size * 0.06 : 0)
            .appShadow(AppShadow.glassSubtle)
        }
    }

    private var reliefSymbol: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(LinearGradient(
                colors: [tint, tint, AppColor.accentDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .background {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint.opacity(0.45))
                    .offset(x: size * 0.012, y: size * 0.022)
            }
    }

    private var ribbon: some View {
        MedalRibbon()
            .fill(LinearGradient(
                colors: [tint, AppColor.accentDark],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: size * 0.22, height: size * 0.43)
    }
}

private struct MedallionShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.43, y: h * 0.03))
        path.addQuadCurve(to: CGPoint(x: w * 0.57, y: h * 0.03), control: CGPoint(x: w * 0.5, y: -h * 0.01))
        path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.32), control: CGPoint(x: w * 0.98, y: h * 0.25))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.68))
        path.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.78), control: CGPoint(x: w * 0.98, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.57, y: h * 0.97))
        path.addQuadCurve(to: CGPoint(x: w * 0.43, y: h * 0.97), control: CGPoint(x: w * 0.5, y: h * 1.01))
        path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.78))
        path.addQuadCurve(to: CGPoint(x: w * 0.02, y: h * 0.68), control: CGPoint(x: w * 0.02, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.02, y: h * 0.32))
        path.addQuadCurve(to: CGPoint(x: w * 0.08, y: h * 0.22), control: CGPoint(x: w * 0.02, y: h * 0.25))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct MedalRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct MilestoneArtworkPreview: View {
    @State private var trigger = 0

    var body: some View {
        VStack(spacing: Spacing.xl) {
            HStack(spacing: Spacing.lg) {
                MilestoneArtwork(trigger: trigger)
                MilestoneArtwork(symbol: "trophy.fill", tint: AppColor.achievement, trigger: trigger)
            }
            HStack(spacing: Spacing.lg) {
                MilestoneArtwork(symbol: "flame.fill", tint: AppColor.streak, style: .symbol, trigger: trigger)
                MilestoneArtwork(style: .emblem, trigger: trigger)
            }
            GlassButton(title: "Replay", style: .secondary) { trigger &+= 1 }
        }
        .padding(Spacing.xl)
        .background(AppColor.background)
    }
}

#Preview("Milestones · light") {
    MilestoneArtworkPreview().preferredColorScheme(.light)
}

#Preview("Milestones · dark") {
    MilestoneArtworkPreview().preferredColorScheme(.dark)
}

#Preview("Milestones · Reduce Motion") {
    MilestoneArtworkPreview()
        .environment(\.accessibilityReduceMotion, true)
        .preferredColorScheme(.dark)
}
