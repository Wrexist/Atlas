import SwiftUI

extension View {
    /// The app's standard "glass" treatment for `Form` / `List` editor
    /// sheets.
    ///
    /// SwiftUI's grouped `Form` ships an opaque system backdrop that reads
    /// as stock iOS gray. Hiding it and painting the canvas with
    /// `AppColor.background` — which resolves per colour scheme — leaves
    /// the inset rows reading as elevated cards in both Light and Dark, the
    /// recipe `EditBiomarkersSheet` established, and `.tint` routes every
    /// control (steppers, toggles, pickers, the cursor) through the live
    /// theme accent.
    ///
    /// Apply to the `Form`/`List` itself. The scheme follows the user's
    /// appearance setting; don't force one on the sheet.
    func glassFormStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .tint(AppColor.accentPrimary)
    }
}
