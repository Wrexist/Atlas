import SwiftUI

extension View {
    /// The app's standard dark "glass" treatment for `Form` / `List`
    /// editor sheets.
    ///
    /// SwiftUI's grouped `Form` ships an opaque system backdrop that reads
    /// as stock iOS gray and breaks the app's dark, premium look. Hiding
    /// it and painting the canvas with `AppColor.background` leaves the
    /// inset rows rendering as elevated dark cards — the exact recipe
    /// `EditBiomarkersSheet` established — and `.tint` routes every
    /// control (steppers, toggles, pickers, the cursor) through the live
    /// theme accent.
    ///
    /// Apply to the `Form`/`List` itself. Pair with
    /// `.preferredColorScheme(.dark)` on the sheet root so the nav bar and
    /// keyboard accessory match.
    func glassFormStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppColor.background)
            .tint(AppColor.accentPrimary)
    }
}
