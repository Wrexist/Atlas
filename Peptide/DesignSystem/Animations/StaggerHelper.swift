import SwiftUI

struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.98)
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
            .offset(y: appeared || reduceMotion ? 0 : 14)
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
///
/// A press sinks the control into the page: it shrinks and its top edge
/// tips a few degrees away under perspective, the way a physical key goes
/// down, rather than just fading.
struct ScalePressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.95
    /// How far the top edge tips back on press.
    private static let pressedTilt: Double = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let sinks = configuration.isPressed && !reduceMotion
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(sinks ? pressedScale : 1.0)
            .rotation3DEffect(.degrees(sinks ? Self.pressedTilt : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .appAnimation(AppAnimation.press, value: configuration.isPressed)
    }
}
