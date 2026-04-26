import SwiftUI

struct HeroIcon: View {
    let symbol: String
    var color: Color = AppColor.accentPrimary
    var accent: Color = AppColor.accentLight
    var size: CGFloat = 96
    var bounceTrigger: Int = 0

    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: size * 2.0, height: size * 2.0)
                .blur(radius: 30)
                .scaleEffect(pulse ? 1.08 : 0.95)

            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [accent.opacity(0.6), color.opacity(0.0), accent.opacity(0.6)],
                        center: .center
                    ),
                    lineWidth: 1
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .rotationEffect(.degrees(rotate ? 360 : 0))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.35), color.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.25, height: size * 1.25)
                .overlay {
                    Circle()
                        .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                }

            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent, color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolEffect(.bounce, value: bounceTrigger)
                .shadow(color: color.opacity(0.6), radius: 10, x: 0, y: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                rotate = true
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HeroIcon(symbol: "flask.fill")
    }
    .preferredColorScheme(.dark)
}
