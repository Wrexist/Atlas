import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Adds a tap-anywhere-outside-text-fields gesture that resigns the first
/// responder. Use on sheet roots that contain `TextField`s — without it the
/// keyboard sticks around when the user taps the surrounding card area,
/// blocking the bottom of the sheet on small devices.
struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                // contentShape on a clear color makes the entire surrounding
                // area tappable without breaking child hit-testing — taps
                // that hit a TextField, Button, or other interactive view
                // still go through to those targets.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        #if canImport(UIKit)
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                        #endif
                    }
            )
    }
}

extension View {
    /// Tap any non-interactive area to dismiss the keyboard. Pair with
    /// `.scrollDismissesKeyboard(.interactively)` on scroll views inside
    /// the same sheet for the full set of dismissal affordances.
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }
}
