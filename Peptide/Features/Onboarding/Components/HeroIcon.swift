import SwiftUI

/// Centered hero glyph used on most onboarding steps. Two concentric
/// soft-light rings + a tinted disc behind the SF Symbol — gentle ambient
/// motion (a slow breathing pulse) but no rotating gradients, which used
/// to read as "vibe-coded" against the marketing copy.
struct HeroIcon: View {
    let symbol: String
    var color: Color = AppColor.accentPrimary
    var accent: Color = AppColor.accentLight
    var size: CGFloat = 96
    var bounceTrigger: Int = 0

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: size * 1.9, height: size * 1.9)
                .blur(radius: 32)
                .scaleEffect(pulse ? 1.05 : 0.96)

            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                .frame(width: size * 1.55, height: size * 1.55)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(0.32),
                            color.opacity(0.10),
                            color.opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.65
                    )
                )
                .frame(width: size * 1.25, height: size * 1.25)
                .overlay {
                    Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }

            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent, color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.bounce, value: bounceTrigger)
                .shadow(color: color.opacity(0.45), radius: 8, x: 0, y: 3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Welcome-screen hero that drops the app's own logo into the glowing
/// disc instead of an SF Symbol. The artwork fills the circle edge-to-edge
/// (clipped), sits on the same breathing ambient rings as `HeroIcon`, and
/// carries a wide outer glow so it reads as the brand mark, not a sticker.
struct HeroLogo: View {
    var imageName: String = "AtlasLogo"
    var color: Color = AppColor.accentPrimary
    var size: CGFloat = 140
    var bounceTrigger: Int = 0

    @State private var pulse = false
    @State private var bounce = false

    var body: some View {
        ZStack {
            // Wide ambient glow — the "outglow shadow around the circle".
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: size * 1.9, height: size * 1.9)
                .blur(radius: 38)
                .scaleEffect(pulse ? 1.06 : 0.96)

            // Soft outer ring for depth, matching HeroIcon's framing.
            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
                .frame(width: size * 1.5, height: size * 1.5)

            // The logo, filled into the disc.
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                }
                .shadow(color: color.opacity(0.55), radius: 24, x: 0, y: 6)
                .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 2)
                .scaleEffect(pulse ? 1.015 : 1.0)
                .scaleEffect(bounce ? 1.06 : 1.0)
        }
        .onChange(of: bounceTrigger) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { bounce = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.18)) { bounce = false }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: 48) {
            HeroLogo()
            HeroIcon(symbol: "flask.fill")
        }
    }
    .preferredColorScheme(.dark)
}
