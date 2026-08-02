import Foundation
import SwiftUI

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let xxxxl: CGFloat = 40

    static let cardPadding: CGFloat = 16
    static let screenPadding: CGFloat = 20

    // MARK: - Corner radii
    //
    // One named role per radius. Nesting a rounded shape inside another looks
    // wrong unless the inner radius is the outer one minus the inset — use
    // `concentric(in:inset:)` rather than eyeballing a second literal.

    static let sheetCornerRadius: CGFloat = 28
    static let cardCornerRadius: CGFloat = 20
    /// Buttons, fields, and other single-line controls.
    static let controlCornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 12
    static let chipCornerRadius: CGFloat = 8
    /// Smaller than chipCornerRadius. Used for tiny icon backgrounds (≤24pt
    /// frames) where chipCornerRadius would look too round.
    static let iconCornerRadius: CGFloat = 6

    /// The inner radius that keeps a nested shape concentric with its
    /// container. A 20pt card padded by 8pt wants a 12pt inner radius; any
    /// other value leaves a visibly uneven gap at the corners.
    ///
    /// Clamped at 2pt so a deep inset degrades to "almost square" instead of
    /// inverting into a negative radius.
    static func concentric(in outerRadius: CGFloat, inset: CGFloat) -> CGFloat {
        max(2, outerRadius - inset)
    }

    // MARK: - Touch targets

    /// Apple's minimum comfortable target. Icon-only controls should reserve
    /// at least this much, even when the glyph itself is smaller.
    static let minimumHitTarget: CGFloat = 44

    // MARK: - Scroll insets

    /// Bottom padding that keeps the last row of a scroll view clear of the
    /// tab bar and the floating next-dose accessory above it.
    static let scrollBottomInset: CGFloat = 96
}

extension View {
    /// Grows the *tappable* area to the 44pt minimum without changing what's
    /// drawn: the visual keeps whatever frame it already had and sits centred
    /// in the larger hit box.
    ///
    /// Apply it last, after the fill and border — putting it earlier resizes
    /// the artwork instead of the target, which is the mistake it exists to
    /// prevent.
    func minimumHitArea() -> some View {
        frame(minWidth: Spacing.minimumHitTarget, minHeight: Spacing.minimumHitTarget)
            .contentShape(Rectangle())
    }
}
