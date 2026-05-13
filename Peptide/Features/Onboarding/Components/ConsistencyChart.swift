import SwiftUI

/// Two-curve "consistency" chart used by the notifications onboarding step.
/// Curve A ("With PeptideX") rises steeply; curve B ("Without tracking")
/// peaks early then drifts down. Both paths animate their `pathLength`
/// (SwiftUI `trim(from:to:)`) on appear with a small stagger so the eye
/// follows curve A first — same effect as Framer Motion's pathLength
/// keyframes.
///
/// Curve A picks up the active brand accent so the chart never clashes
/// with the user's chosen theme; curve B stays neutral grey.
struct ConsistencyChart: View {
    @State private var drawA: CGFloat = 0
    @State private var drawB: CGFloat = 0
    @State private var endpointsVisible = false

    private var lineColorA: Color { AppColor.accentPrimary }
    private let lineColorB = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF

    var body: some View {
        VStack(spacing: Spacing.sm) {
            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    // Soft fill under curve A — a closed version of the same
                    // path so the gradient hugs the line. Trimmed in lock-step
                    // with curve A's stroke.
                    fillUnderA(in: size)
                        .fill(
                            LinearGradient(
                                colors: [lineColorA.opacity(0.10), lineColorA.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(drawA)

                    curveB(in: size)
                        .trim(from: 0, to: drawB)
                        .stroke(lineColorB, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    curveA(in: size)
                        .trim(from: 0, to: drawA)
                        .stroke(lineColorA, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                    endpointDot(at: pointA(at: 0, in: size))
                        .opacity(endpointsVisible ? 1 : 0)
                    endpointDot(at: pointA(at: 1, in: size))
                        .opacity(endpointsVisible ? 1 : 0)

                    seriesLabel("With PeptideX", color: lineColorA)
                        .position(x: size.width * 0.22, y: size.height * 0.18)
                        .opacity(drawA)

                    seriesLabel("Without tracking", color: lineColorB)
                        .position(x: size.width * 0.72, y: size.height * 0.92)
                        .opacity(drawB)
                }
            }
            .frame(height: 180)

            HStack {
                Text("Month 1")
                Spacer()
                Text("Month 6")
            }
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.textSecondary)
        }
        .onAppear(perform: animate)
        .onDisappear(perform: reset)
    }

    private func animate() {
        // Reset before scheduling so a recycled view (e.g. inside a
        // List or LazyVStack that re-uses cells) re-runs the draw
        // animation each time it scrolls back into view rather than
        // staying frozen at its fully-drawn end state.
        guard drawA == 0 else { return }
        withAnimation(.easeOut(duration: 1.2)) {
            drawA = 1
        }
        withAnimation(.easeOut(duration: 1.2).delay(0.25)) {
            drawB = 1
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(1.1)) {
            endpointsVisible = true
        }
    }

    private func reset() {
        // Snap (no animation) so the next .onAppear can run a fresh
        // grow-in pass instead of seeing drawA == 1 and bailing.
        drawA = 0
        drawB = 0
        endpointsVisible = false
    }

    // MARK: - Path geometry

    /// "With PeptideX" — fast initial rise, slight easing toward the top
    /// right. Bezier control points keep it convex (always above its chord)
    /// so the trim animation looks like growth, not a spike.
    private func curveA(in size: CGSize) -> Path {
        Path { path in
            let start = pointA(at: 0, in: size)
            let end = pointA(at: 1, in: size)
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.55),
                control2: CGPoint(x: size.width * 0.55, y: size.height * 0.10)
            )
        }
    }

    /// Closed version of curve A for the area fill — drops to the baseline
    /// at the right edge and walks back along the bottom.
    private func fillUnderA(in size: CGSize) -> Path {
        Path { path in
            let start = pointA(at: 0, in: size)
            let end = pointA(at: 1, in: size)
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.55),
                control2: CGPoint(x: size.width * 0.55, y: size.height * 0.10)
            )
            path.addLine(to: CGPoint(x: end.x, y: size.height))
            path.addLine(to: CGPoint(x: start.x, y: size.height))
            path.closeSubpath()
        }
    }

    /// "Without tracking" — peaks around the 40 % mark and drifts back down
    /// without ever leaving the visible frame (control points stay ≤ 0.95
    /// of size.height so the stroke doesn't paint outside its bounds).
    private func curveB(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height * 0.78))
            path.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.82),
                control1: CGPoint(x: size.width * 0.30, y: size.height * 0.42),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.95)
            )
        }
    }

    private func pointA(at t: CGFloat, in size: CGSize) -> CGPoint {
        switch t {
        case 0: CGPoint(x: 0, y: size.height * 0.95)
        default: CGPoint(x: size.width, y: size.height * 0.10)
        }
    }

    private func endpointDot(at point: CGPoint) -> some View {
        Circle()
            .strokeBorder(lineColorA, lineWidth: 2.5)
            .background(Circle().fill(AppColor.background))
            .frame(width: 12, height: 12)
            .position(point)
    }

    /// Series label with a leading colour dot. Reads as a tiny inline
    /// legend rather than free-floating coloured text the eye has to
    /// visually associate with the right curve.
    private func seriesLabel(_ text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(AppColor.background.opacity(0.85))
                .overlay {
                    Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ConsistencyChart()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
