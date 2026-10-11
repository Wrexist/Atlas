import SwiftUI

/// The Watch app's whole motion vocabulary. Every entrance, value change
/// and press draws from these, so the app moves as one system: eased,
/// no overshoot on data, and a fixed rhythm between elements.
enum WatchMotion {
    /// A hero (ring, gauge, bar) arriving on screen.
    static let entrance = Animation.smooth(duration: 0.9)
    /// A number rolling to its value.
    static let count = Animation.smooth(duration: 1.0)
    /// A value changing while its page is already on screen.
    static let update = Animation.smooth(duration: 0.5)
    /// A control answering a touch.
    static let press = Animation.snappy(duration: 0.18)
    /// Gap between elements that arrive in sequence.
    static let stagger = 0.08
    /// Supporting text waits for the hero to start moving first.
    static let contentDelay = 0.18
}

private struct WatchPageIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True while this page is the one on screen. `WatchRootView` sets it
    /// per page so rings and numbers replay their entrance each time the
    /// Crown lands on a page, instead of once when the pager preloads it.
    var watchPageIsActive: Bool {
        get { self[WatchPageIsActiveKey.self] }
        set { self[WatchPageIsActiveKey.self] = newValue }
    }
}

extension View {
    /// The page's colour as a bloom from the top edge over true black.
    /// Clean on OLED, and the system cross-fades it as the Crown moves
    /// between pages, the way the watchOS 10 apps change colour.
    func pageBackground(_ tint: Color) -> some View {
        containerBackground(
            RadialGradient(
                stops: [
                    .init(color: tint.opacity(0.34), location: 0),
                    .init(color: tint.opacity(0.1), location: 0.5),
                    .init(color: .black, location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 260
            ),
            for: .tabView
        )
    }
}

/// A number that rolls up from zero when its page comes on screen and
/// rolls between values when the phone sends a new one.
struct RollingNumber: View {
    let value: Int

    @Environment(\.watchPageIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text(shown, format: .number)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear(perform: update)
            .onChange(of: isActive) { update() }
            .onChange(of: value) { update() }
    }

    private func update() {
        guard !reduceMotion else {
            shown = value
            return
        }
        withAnimation(isActive ? WatchMotion.count : nil) {
            shown = isActive ? value : 0
        }
    }
}

/// Shrinks a control slightly while it's held, so a tap on the wrist has
/// a physical answer before the haptic lands.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(WatchMotion.press, value: configuration.isPressed)
    }
}

/// Supporting content settles in, a short rise and fade, just after the
/// page's hero starts to move. `order` sets its place in the sequence.
private struct Entrance: ViewModifier {
    let order: Int

    @Environment(\.watchPageIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear(perform: update)
            .onChange(of: isActive) { update() }
    }

    private func update() {
        let target = isActive || reduceMotion
        guard target, !reduceMotion else {
            shown = target
            return
        }
        let delay = WatchMotion.contentDelay + Double(order) * WatchMotion.stagger
        withAnimation(WatchMotion.entrance.delay(delay)) { shown = true }
    }
}

extension View {
    func entrance(_ order: Int) -> some View {
        modifier(Entrance(order: order))
    }
}
