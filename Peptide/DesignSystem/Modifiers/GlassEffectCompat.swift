import SwiftUI

// Backward-compatible wrappers for the iOS 26 Liquid Glass APIs.
// On iOS 17–25 views render with their existing solid/translucent background;
// on iOS 26+ the system Liquid Glass material is composited on top, with
// optional tint + interactive press response (the same effect the system
// uses for the tab bar selection pill).

enum GlassPreset {
    case circle
    case capsule
    case rect(cornerRadius: CGFloat)
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

    /// Tinted, optionally interactive Liquid Glass — mirrors the bouncy press
    /// response on the system tab bar. Tint is multiplied with the material;
    /// keep alpha low (≈0.3–0.5) so the glass still reads as glass.
    @ViewBuilder
    func liquidGlass(
        _ preset: GlassPreset,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = {
                var g: Glass = .regular
                if let tint { g = g.tint(tint) }
                if interactive { g = g.interactive() }
                return g
            }()

            switch preset {
            case .circle:
                self.glassEffect(glass, in: .circle)
            case .capsule:
                self.glassEffect(glass, in: .capsule)
            case .rect(let r):
                self.glassEffect(glass, in: .rect(cornerRadius: r))
            }
        } else {
            self
        }
    }

    /// Pair with `liquidGlassContainer` to morph a single glass shape between
    /// items that share the same id — same trick the system tab bar uses for
    /// its sliding selection pill.
    @ViewBuilder
    func liquidGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

extension View {
    /// The app's standard rounded-rect glass surface.
    ///
    /// On iOS 26+ this renders the real Liquid Glass material and
    /// nothing else. On earlier OSes it falls back to the legacy
    /// translucent-fill recipe (an opaque-ish fill + overlay tint +
    /// hairline border).
    ///
    /// The two are deliberately mutually exclusive. The previous
    /// `GlassCard` / `GlassCardModifier` painted the fake recipe
    /// *and then* composited real `glassEffect` on top — so on iOS 26
    /// every card stacked two materials and the genuine translucency
    /// never showed. Routing every card surface through this single
    /// modifier fixes that without changing the pre-iOS-26 look.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat, tinted: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = tinted ? Glass.regular.tint(AppColor.glassTint) : .regular
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tinted ? AppColor.glassTint : AppColor.cardOverlay)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    tinted ? AppColor.glassBorderActive : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Wraps content in a `GlassEffectContainer` on iOS 26+ so child glass shapes
/// can morph into one another via `liquidGlassID(_:in:)`. No-op on earlier OSes.
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
