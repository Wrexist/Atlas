import SwiftUI

struct GlassSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                sheetContent()
                    .presentationBackground(.ultraThinMaterial)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(Spacing.cardCornerRadius)
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
    @ViewBuilder
    func liquidGlassPresentation(
        detents: Set<PresentationDetent>? = nil
    ) -> some View {
        let view = self
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Spacing.cardCornerRadius)
            .presentationBackground(.ultraThinMaterial)
        if let detents {
            view.presentationDetents(detents)
        } else {
            view
        }
    }
}
