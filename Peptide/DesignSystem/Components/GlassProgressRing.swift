import SwiftUI

struct GlassProgressRing: View {
    let progress: Double
    var size: CGFloat = 160
    var lineWidth: CGFloat = 12
    var showLabel: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0
    @State private var hasAppeared = false
    @State private var celebrationScale: CGFloat = 1.0

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

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
                        .scaleEffect(celebrationScale)

                    Text("SCORE")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .tracking(2)
                }
            }
        }
        .onAppear {
            if hasAppeared {
                animatedProgress = clampedProgress
            } else {
                hasAppeared = true
                withAnimation(AppAnimation.springGentle) {
                    animatedProgress = clampedProgress
                }
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            let clamped = min(max(newValue, 0), 1)
            withAnimation(AppAnimation.springGentle) {
                animatedProgress = clamped
            }
            // Celebrate the moment the user crosses into 100% — a calm gold
            // pulse on the score, not fireworks. Suppressed under Reduce
            // Motion since the value-text already updates.
            if oldValue < 1.0, clamped >= 1.0, !reduceMotion {
                triggerCelebration()
            }
        }
    }

    private func triggerCelebration() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            celebrationScale = 1.08
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                celebrationScale = 1.0
            }
        }
    }
}

struct GlassProgressBar: View {
    let progress: Double
    var height: CGFloat = 6

    @State private var animatedProgress: Double = 0
    @State private var hasAppeared = false

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

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
            if hasAppeared {
                animatedProgress = clampedProgress
            } else {
                hasAppeared = true
                withAnimation(AppAnimation.springGentle) {
                    animatedProgress = clampedProgress
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(AppAnimation.springGentle) {
                animatedProgress = min(max(newValue, 0), 1)
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
