import SwiftUI

struct PeptideCategoryBadge: View {
    let category: PeptideCategory

    var body: some View {
        Badge(category.localizedTitle, icon: category.iconName, tint: category.color)
    }
}
