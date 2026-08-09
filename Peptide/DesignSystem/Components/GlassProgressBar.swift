import SwiftUI

/// Linear gauge counterpart to `MetricRing`. Same gradient, same appear
/// sweep — reach for the ring when the value is the point of the card, and
/// for this when it's a secondary detail inside a row.
struct GlassProgressBar: View {
    let progress: Double
    var height: CGFloat = 6
    /// Stops for the filled portion, matching `MetricRing`'s `gradient`
    /// parameter. Defaults to the brand ramp; pass a metric's own colour
    /// when the bar sits in a row that is already identified by it, so
    /// the row reads as one thing rather than a label and an accent.
    var gradient: [Color]?

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
                            colors: gradient ?? [AppColor.accentDark,
                                                 AppColor.accentPrimary,
                                                 AppColor.accentLight],
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
