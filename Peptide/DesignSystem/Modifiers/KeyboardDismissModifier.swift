import SwiftUI
import UIKit

/// A "Done" button above the keyboard that resigns the first responder.
/// Use on sheet roots that contain `TextField`s — without it the keyboard
/// sticks around and blocks the bottom of the sheet on small devices.
///
/// A tap catcher behind the content can't do this job: the full-screen
/// scroll view these sheets use takes every tap, so a background gesture
/// never fires. Must sit inside a `NavigationStack`.
struct KeyboardDoneButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                .fontWeight(.semibold)
            }
        }
    }
}

extension View {
    /// Adds a keyboard "Done" button. Pair with
    /// `.scrollDismissesKeyboard(.interactively)` on scroll views inside
    /// the same sheet for the full set of dismissal affordances.
    func keyboardDoneButton() -> some View {
        modifier(KeyboardDoneButtonModifier())
    }
}
