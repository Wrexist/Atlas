import SwiftUI

/// Indeterminate progress for a wait whose length nobody knows.
///
/// The meal scan is one network round-trip to a vision model. There is no
/// percentage to report, so this does not invent one — a bar that creeps to
/// 90% and stalls is a lie the user learns to distrust. Instead a highlight
/// travels the track continuously: motion says "still working" without
/// claiming a position.
///
/// `GlassProgressBar` is the token for a *known* fraction and stays that.
/// This is its indeterminate sibling, and they share the accent ramp so the
/// two read as the same family.
struct ScanProgressBar: View {
    var height: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width
            Capsule(style: .continuous)
                .fill(AppColor.surfaceElevated)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentDark,
                                    AppColor.accentPrimary,
                                    AppColor.accentLight,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: travel * 0.4)
                        // Reduce Motion gets a still bar at rest rather than a
                        // travelling one — the label carries the meaning, and
                        // an endlessly moving element is exactly what that
                        // setting exists to stop.
                        .offset(x: isSweeping ? travel * 0.6 : -travel * 0.4)
                        .opacity(reduceMotion ? 0.55 : 1)
                }
                .clipShape(Capsule(style: .continuous))
                .onAppear {
                    guard !reduceMotion else { return }
                    // 1.3s, not the 0.8s that first felt right. A fast sweep
                    // reads as urgency and pulls the eye; at this pace it
                    // reads as steady work, which is what a wait should feel
                    // like. It also clears the design-lint threshold for a
                    // loop being decorative rather than ambient.
                    withAnimation(
                        .easeInOut(duration: 1.3).repeatForever(autoreverses: true)
                    ) {
                        isSweeping = true
                    }
                }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
