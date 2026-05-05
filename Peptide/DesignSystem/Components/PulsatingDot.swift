import SwiftUI

/// Small filled dot with a soft outward pulse ring. Used as an "active /
/// connected" indicator (e.g. signed in, syncing). Honours Reduce Motion —
/// when accessibility motion is reduced, the pulse is suppressed and only
/// the static dot remains.
struct PulsatingDot: View {
    var color: Color = AppColor.accentPrimary
    var size: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(animate ? 2.4 : 1.0)
                    .opacity(animate ? 0 : 0.7)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: animate ? 4 : 2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: 32) {
            PulsatingDot()
            HStack(spacing: 8) {
                PulsatingDot(size: 8)
                Text("Signed In").foregroundStyle(AppColor.textPrimary)
            }
        }
    }
    .preferredColorScheme(.dark)
}
