import SwiftUI

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
                    .init(color: tint.opacity(0.55), location: 0),
                    .init(color: tint.opacity(0.14), location: 0.55),
                    .init(color: .black, location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0.05),
                startRadius: 0,
                endRadius: 230
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
        withAnimation(.snappy(duration: 0.8)) {
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
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
