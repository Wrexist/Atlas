import SwiftUI

// Backward-compatible wrappers for the iOS 26 Liquid Glass APIs.
// On iOS 18–25 views render with their existing solid/translucent background;
// on iOS 26+ the system Liquid Glass material is composited on top.

enum GlassPreset {
    case circle
    case capsule
    case rect(cornerRadius: CGFloat)

    /// The same silhouette as a plain `Shape`, for the pre-iOS-26 fallback
    /// recipe which has to draw the fill, wash, and hairline itself.
    var shape: AnyShape {
        switch self {
        case .circle: AnyShape(Circle())
        case .capsule: AnyShape(Capsule(style: .continuous))
        case .rect(let radius): AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    @ViewBuilder
    func liquidGlass(_ preset: GlassPreset) -> some View {
        if #available(iOS 26.0, *) {
            switch preset {
            case .circle:
                self.glassEffect(in: .circle)
            case .capsule:
                self.glassEffect(in: .capsule)
            case .rect(let r):
                self.glassEffect(in: .rect(cornerRadius: r))
            }
        } else {
            self
        }
    }
}

/// The legacy recipe's base fill. Opaque under Reduce Transparency, which
/// iOS 26's material honours on its own but a hand-painted 60% fill doesn't:
/// without this, the backdrop, photos or camera feed show through for users
/// who asked for solid surfaces.
private struct LegacyGlassFill<S: Shape>: View {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        shape.fill(AppColor.surfaceSecondary.opacity(reduceTransparency ? 1 : 0.6))
    }
}

extension View {
    /// The app's standard rounded-rect card surface: solid, in both schemes.
    ///
    /// A near-white card with a soft drop on the warm light page; a
    /// charcoal card on the warm near-black dark page. Both carry a barely
    /// visible edge that firms up under Increase Contrast. Cards used to be
    /// Liquid Glass, which on a flat backdrop reads as grey frosting and
    /// made every card look the same as every control; solid cards let the
    /// glass stay where it means something, on controls and bars.
    ///
    /// The surface doesn't clip its content, so a badge or shadow that
    /// overflows the card looks the same everywhere. Callers that need
    /// clipping add their own `clipShape`.
    func glassSurface(cornerRadius: CGFloat, tinted: Bool = false) -> some View {
        modifier(CardSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tinted: tinted))
    }

    /// The app's one glass **control** surface — buttons, icon buttons,
    /// segmented controls, chips.
    ///
    /// Like `glassSurface`, the real material and the legacy recipe are
    /// mutually exclusive: `GlassButton` and `GlassSegmentedControl` used to
    /// paint a 60%-opaque fake capsule *and then* composite `glassEffect` over
    /// it, so on iOS 26 every control stacked two materials and read as muddy
    /// grey rather than glass.
    ///
    /// - Parameters:
    ///   - tint: the accent wash the control carries. Keep it low —
    ///     ~0.15–0.20 — or the tint stops reading as glass and starts reading
    ///     as a flat coloured button.
    ///   - legacyTint: the wash for the pre-iOS-26 recipe, when it needs to be
    ///     stronger than the real material's tint. The two are not
    ///     interchangeable: the legacy path *paints* the colour over an opaque
    ///     fill, so it needs more alpha to read at all, while `Glass.tint`
    ///     multiplies into the material and saturates fast. Defaults to `tint`.
    ///   - border: hairline colour for the legacy recipe. Ignored on iOS 26+,
    ///     where the material provides its own edge.
    ///   - interactive: opt into the system's bouncy press response.
    @ViewBuilder
    func glassControl(
        _ preset: GlassPreset,
        tint: Color? = nil,
        legacyTint: Color? = nil,
        border: Color = AppColor.glassBorder,
        interactive: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = {
                var value: Glass = .regular
                if let tint { value = value.tint(tint) }
                if interactive { value = value.interactive() }
                return value
            }()

            switch preset {
            case .circle:
                self.glassEffect(glass, in: .circle)
            case .capsule:
                self.glassEffect(glass, in: .capsule)
            case .rect(let radius):
                self.glassEffect(glass, in: .rect(cornerRadius: radius))
            }
        } else {
            let shape = preset.shape
            let wash = legacyTint ?? tint ?? AppColor.cardOverlay
            self
                .background {
                    LegacyGlassFill(shape: shape)
                        .overlay { shape.fill(wash) }
                        // 1pt centred on the edge, half of it clipped away
                        // below: the same 0.5pt inside hairline that
                        // `strokeBorder` draws on `glassSurface`. `AnyShape`
                        // isn't insettable, so it can't use `strokeBorder`.
                        .overlay { shape.stroke(border, lineWidth: 1) }
                        .clipShape(shape)
                }
        }
    }

    /// Capsule-shaped companion to `glassSurface`, for pills, search
    /// fields, and capsule buttons.
    func glassSurfaceCapsule(tinted: Bool = false) -> some View {
        modifier(CardSurface(shape: Capsule(style: .continuous), tinted: tinted))
    }
}

/// See `glassSurface`.
private struct CardSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tinted: Bool

    func body(content: Content) -> some View {
        content.background { PaperFill(shape: shape, tinted: tinted) }
    }
}

/// The card itself: a top-lit fill, a lit rim along the upper edge, a
/// hairline, and a two-layer drop (a tight contact edge plus a wide
/// ambient lift). Together they read as an object resting on the page
/// rather than a flat panel printed on it. A tinted card takes a faint
/// accent wash so it reads as a pastel card, not a coloured slab.
private struct PaperFill<S: InsettableShape>: View {
    let shape: S
    let tinted: Bool

    var body: some View {
        shape.fill(
            LinearGradient(
                colors: [AppColor.surfaceElevated, AppColor.surfaceElevatedLow],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay { if tinted { shape.fill(AppColor.paperTint) } }
        .overlay {
            shape.strokeBorder(tinted ? AppColor.glassBorderActive : AppColor.paperEdge, lineWidth: 0.5)
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [AppColor.cardRim, .clear],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 1
            )
        }
        .appShadow(AppShadow.paperContact)
        .appShadow(AppShadow.paperAmbient)
    }
}

/// The backdrop for a full-bleed docked bar — the AI composer, the Home
/// sticky header, any rail pinned to a screen edge.
///
/// Bars can't go through `glassSurface`: they have no corner radius, and its
/// legacy recipe strokes a hairline all the way round, which on a full-width
/// bar draws a line down both screen edges. A bar owns its own divider on the
/// single edge that faces content.
///
/// It is also the one place outside this file allowed to reach for
/// `.ultraThinMaterial`. Pre-iOS-26 the bar sits over live scrolling content,
/// where the flat `surfaceSecondary` wash the card recipe uses would read as
/// an opaque slab. Keeping the material here means feature code still has a
/// single call to make, and `rule_raw_material` can stay an error everywhere
/// else.
///
/// `opacity` exists for scroll-driven bars that fade in as content passes
/// under them.
struct GlassBarBackground: View {
    var opacity: Double = 1

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 0))
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay { Rectangle().fill(AppColor.background.opacity(0.55)) }
            }
        }
        .opacity(opacity)
    }
}

/// Wraps content in a `GlassEffectContainer` on iOS 26+ so neighbouring glass
/// shapes render and blend as one group. No-op on earlier OSes.
struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
