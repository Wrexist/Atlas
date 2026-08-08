import SwiftUI

/// Pins a footer — a CTA, a Continue button, an Apply bar — beneath scrolling
/// content.
///
/// This exists because the same defect shipped twice. Both surfaces wrote the
/// footer as `VStack { Spacer(); footer }` layered in a `ZStack` over a
/// `ScrollView`. That is a floating overlay: it reserves **no** layout space,
/// so the content underneath scrolls to its own natural end and the last row
/// stops permanently behind the button. In onboarding it put the Gender row
/// under the CTA with no way to scroll it clear — the field could not be
/// reached at all. On the paywall the backdrop opened at `.opacity(0)`, so the
/// tier cards showed straight through the button and the legal copy.
///
/// The fix is two things that must travel together:
///
/// 1. `safeAreaInset(edge: .bottom)` — reserves real resting space, so every
///    scroll view inside gets bottom room and its last row clears the button.
/// 2. An **opaque** backdrop whose fade ends *above* the button — scrolled
///    content still travels under an inset, so there must be solid ground
///    everywhere text is drawn, and a soft edge only where content passes.
///
/// Either one alone reproduces one of the two bugs.
struct PinnedFooterModifier<Footer: View>: ViewModifier {
    let fadeHeight: CGFloat
    let footer: Footer

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .background {
                        ZStack(alignment: .top) {
                            AppColor.background
                            LinearGradient(
                                colors: [AppColor.background.opacity(0), AppColor.background],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: fadeHeight)
                        }
                        // Both of these are load-bearing, and dropping either
                        // one killed the CTA on every screen using this.
                        //
                        // `edges: .bottom` — an unscoped `ignoresSafeArea()`
                        // grows the backdrop in *every* direction, well past
                        // the footer it is meant to sit behind.
                        //
                        // `allowsHitTesting(false)` — `AppColor.background`
                        // is a `Color`, and a Color is a hit-testable view.
                        // Expanded beyond the footer's bounds inside a
                        // `safeAreaInset`, it swallowed the taps meant for the
                        // button in front of it: "Add 3 items" rendered
                        // perfectly and did nothing. The backdrop is
                        // decoration and must never take a touch.
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
            }
    }
}

extension View {
    /// Pins `footer` to the bottom over scrolling content, reserving its space
    /// rather than floating above it.
    ///
    /// The fade completes within `fadeHeight` of the footer's top edge, so it
    /// must stay smaller than the footer's own top padding — otherwise the
    /// gradient runs under the button and content shows through it again.
    ///
    /// - Parameter fadeHeight: depth of the soft edge where content passes
    ///   under. Defaults to `Spacing.lg`.
    func pinnedFooter<Footer: View>(
        fadeHeight: CGFloat = Spacing.lg,
        @ViewBuilder _ footer: () -> Footer
    ) -> some View {
        modifier(PinnedFooterModifier(fadeHeight: fadeHeight, footer: footer()))
    }
}
