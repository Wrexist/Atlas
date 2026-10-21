import SwiftUI

struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 20)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.95)
            .onAppear {
                guard !appeared else { return }
                AppAnimation.with(AppAnimation.staggered(index: index)) {
                    appeared = true
                }
            }
    }
}

struct SectionAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 30)
            .onAppear {
                guard !appeared else { return }
                AppAnimation.with(AppAnimation.sectionStaggered(index: index)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }

    func sectionAppear(index: Int) -> some View {
        modifier(SectionAppear(index: index))
    }
}

/// Subtle press feedback for buttons that aren't `GlassButton` or `GlassIconButton`
/// — used on inline toggles, chips, and rows so taps feel tactile without a
/// full glass-press treatment.
///
/// The label's whole frame is hit-testable, not just its glyphs: a custom
/// `ButtonStyle` otherwise drops transparent padding, so surface-less labels
/// (ghost buttons, plain rows) only responded where the text was drawn.
struct ScalePressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.85
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? pressedScale : 1.0))
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .appAnimation(AppAnimation.press, value: configuration.isPressed)
    }
}
