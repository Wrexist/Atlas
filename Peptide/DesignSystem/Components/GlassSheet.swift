import SwiftUI

struct GlassSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent()
                    .liquidGlassPresentation()
            }
    }
}

extension View {
    func glassSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(GlassSheetModifier(isPresented: isPresented, sheetContent: content))
    }

    /// Apply the standard liquid-glass presentation styling to a view that's
    /// already inside a `.sheet { ... }` block. Use this on sheet roots
    /// presented with `.sheet(item:)` (where there's no Bool to pass to
    /// `glassSheet`), or on any sheet you can't easily migrate to the
    /// modifier above.
    ///
    /// On iOS 26 the system already presents sheets on Liquid Glass, with a
    /// corner radius that matches the device and reshapes as the sheet is
    /// dragged. Forcing `.ultraThinMaterial` and a fixed radius there
    /// *replaces* that with a flat blur and a corner that no longer lines up
    /// with the display, so both are applied only on the older OSes that
    /// actually need them.
    @ViewBuilder
    func liquidGlassPresentation(
        detents: Set<PresentationDetent>? = nil
    ) -> some View {
        if #available(iOS 26.0, *) {
            applyingDetents(detents)
                .presentationDragIndicator(.visible)
        } else {
            applyingDetents(detents)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Spacing.cardCornerRadius)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func applyingDetents(_ detents: Set<PresentationDetent>?) -> some View {
        if let detents {
            self.presentationDetents(detents)
        } else {
            self
        }
    }
}
