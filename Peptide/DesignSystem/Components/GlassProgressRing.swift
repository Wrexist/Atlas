import SwiftUI

// `GlassProgressRing` retired — its responsibilities (gradient ring,
// appear sweep, celebration pulse, accent glow, center label) are
// now covered by `MetricRing` opt-in flags. The horizontal
// `GlassProgressBar` lives on here because there's no equivalent
// primitive for a linear gauge yet (Phase 2.4 follow-up: bring it
// under a `MetricBar` companion).

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
        GlassProgressBar(progress: 0.65)
            .padding(.horizontal, Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
