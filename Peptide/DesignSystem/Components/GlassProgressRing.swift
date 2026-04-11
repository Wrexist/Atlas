import SwiftUI

struct GlassProgressRing: View {
    let progress: Double
    var size: CGFloat = 160
    var lineWidth: CGFloat = 12
    var showLabel: Bool = true

    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            // Track
            Circle()
                .strokeBorder(AppColor.surfaceElevated, lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * animatedProgress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .rotationEffect(.degrees(-90))
                .appShadow(AppShadow.accentGlow)

            // Center label
            if showLabel {
                VStack(spacing: Spacing.xxs) {
                    Text("\(Int(animatedProgress * 100))")
                        .font(AppFont.scoreLarge)
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())

                    Text("SCORE")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .tracking(2)
                }
            }
        }
        .onAppear {
            withAnimation(AppAnimation.springGentle) {
                animatedProgress = progress
            }
        }
    }
}

struct GlassProgressBar: View {
    let progress: Double
    var height: CGFloat = 6
    var tinted: Bool = true

    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(AppColor.surfaceElevated)

                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentDark, AppColor.accentPrimary, AppColor.accentLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * animatedProgress)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(AppAnimation.springGentle) {
                animatedProgress = progress
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.xxxl) {
            GlassProgressRing(progress: 0.87)
            GlassProgressBar(progress: 0.65)
                .padding(.horizontal, Spacing.screenPadding)
        }
    }
    .preferredColorScheme(.dark)
}
