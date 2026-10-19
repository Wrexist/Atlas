import SwiftUI

/// Prominent search-shaped entry that opens the food library. Sits
/// above the barcode/photo tile picker as the headline path —
/// covers the everyday "I know what I ate, just need to type it" flow
/// that the two scanners require physical artifacts (a barcode, a
/// plate) to handle.
///
/// A standard `GlassEntryRow` with a magnifier glyph. Not a real
/// TextField — tapping anywhere on the row opens the full sheet, where
/// the actual search field auto-focuses.
struct FoodLibraryEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        GlassEntryRow(
            icon: "magnifyingglass",
            title: "Search the food library",
            subtitle: Text("Type a food, brand, or meal — log without scanning"),
            action: onTap
        )
        .accessibilityLabel("Search the food library")
        .accessibilityHint("Opens a searchable list of foods you can log without scanning a barcode.")
    }
}
