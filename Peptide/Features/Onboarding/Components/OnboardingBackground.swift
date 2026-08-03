import SwiftUI

/// Ambient onboarding backdrop. Two large, very slowly drifting orbs tinted
/// with the active brand colours sit behind every step — enough light to
/// give depth to glass surfaces, never so much that text loses contrast.
/// The previous implementation used three near-opaque orbs that read as
/// "vibe-coded" on a marketing flow; this is intentionally restrained.
struct OnboardingBackground: View {
    let step: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppColor.background

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                orb(color: AppColor.accentPrimary, size: w * 1.05)
                    .position(
                        x: w * (0.18 + sin(phase) * 0.06),
                        y: h * (0.18 + cos(phase * 0.8) * 0.04)
                    )

                orb(color: AppColor.accentLight, size: w * 0.85)
                    .position(
                        x: w * (0.86 - sin(phase * 0.7) * 0.07),
                        y: h * (0.82 + cos(phase * 0.6) * 0.05)
                    )
            }
            .blur(radius: 90)
            .opacity(appeared ? 0.32 : 0.0)
            .animation(.easeOut(duration: 1.4), value: appeared)
            .animation(.easeInOut(duration: 1.2), value: step)

            // Subtle top→bottom scrim keeps copy readable regardless of where
            // the orbs drift on a given step. It's tinted with the backdrop
            // rather than plain black so it darkens in dark mode and lightens
            // in light mode instead of muddying the light palette.
            LinearGradient(
                colors: [AppColor.background.opacity(0.25), .clear, AppColor.background.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            appeared = true
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 32).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private func orb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.75), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
    }
}

#Preview {
    OnboardingBackground(step: 0)
        .preferredColorScheme(.dark)
}
