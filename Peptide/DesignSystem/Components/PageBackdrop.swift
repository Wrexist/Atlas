import SwiftUI

/// The page every tab sits on: the warm base colour plus two soft light
/// sources, a warm dawn from the top and a faint accent pool low on the
/// trailing side. A flat fill makes the cards look printed on; light with
/// a direction gives them something to rest above.
struct PageBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppColor.background
            RadialGradient(
                colors: [AppColor.paperGlow.opacity(isDark ? 0.08 : 0.16), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [AppColor.accentPrimary.opacity(isDark ? 0.07 : 0.05), .clear],
                center: UnitPoint(x: 1.0, y: 0.85),
                startRadius: 0,
                endRadius: 420
            )
        }
        .accessibilityHidden(true)
    }

    private var isDark: Bool { colorScheme == .dark }
}

extension View {
    /// Puts the screen on the shared `PageBackdrop`, full-bleed.
    func pageBackground() -> some View {
        background { PageBackdrop().ignoresSafeArea() }
    }
}

#Preview {
    PageBackdrop().ignoresSafeArea()
}
