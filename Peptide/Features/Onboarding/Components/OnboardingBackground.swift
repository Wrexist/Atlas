import SwiftUI

struct OnboardingBackground: View {
    let step: Int

    @State private var phase: CGFloat = 0
    @State private var appeared = false

    private var palette: [Color] {
        switch step % 4 {
        case 0: [AppColor.accentPrimary, AppColor.accentLight, OnboardingTint.muscleRecovery]
        case 1: [OnboardingTint.sleep, AppColor.accentPrimary, AppColor.accentLight]
        case 2: [AppColor.accentLight, OnboardingTint.antiAging, AppColor.accentPrimary]
        default: [AppColor.accentPrimary, OnboardingTint.muscleRecovery, AppColor.accentLight]
        }
    }

    var body: some View {
        ZStack {
            AppColor.background

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                orb(color: palette[0], size: w * 0.95)
                    .position(
                        x: w * (0.25 + sin(phase) * 0.15),
                        y: h * (0.20 + cos(phase * 0.9) * 0.08)
                    )

                orb(color: palette[1], size: w * 0.85)
                    .position(
                        x: w * (0.85 - sin(phase * 0.8) * 0.18),
                        y: h * (0.70 + cos(phase * 0.7) * 0.10)
                    )

                orb(color: palette[2], size: w * 0.7)
                    .position(
                        x: w * (0.50 + sin(phase * 1.1) * 0.20),
                        y: h * (0.50 + cos(phase * 1.3) * 0.16)
                    )
            }
            .blur(radius: 70)
            .opacity(appeared ? 0.55 : 0.0)
            .animation(.easeOut(duration: 1.4), value: appeared)
            .animation(.easeInOut(duration: 1.2), value: step)

            LinearGradient(
                colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            appeared = true
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private func orb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.95), color.opacity(0.0)],
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
