import SwiftUI

/// A product's picture: its own cut-out when one was taken, else the
/// packshot or artwork every food row uses.
struct FridgeProductImage: View {
    let product: FridgeProduct
    var size: CGFloat = 48

    @State private var store = FridgeStore.shared

    var body: some View {
        if let photo = store.photo(for: product) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            FoodThumbnail(name: product.name, imageURL: product.imageURL, barcode: product.barcode, size: size)
        }
    }
}

/// How fresh an item is, as a small coloured pill.
struct FridgeFreshnessBadge: View {
    let freshness: FridgeEngine.Freshness

    var body: some View {
        if let text {
            Text(text)
                .font(AppFont.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(color.opacity(0.15), in: Capsule())
        }
    }

    private var text: LocalizedStringKey? {
        switch freshness {
        case .expired(let days):
            if days == 1 { return "Expired yesterday" }
            return "Expired \(days) days ago"
        case .today:
            return "Use today"
        case .soon(1):
            return "Use by tomorrow"
        case .soon(let days), .fresh(let days):
            return "\(days) days left"
        case .unknown:
            return nil
        }
    }

    private var color: Color {
        switch freshness {
        case .expired: AppColor.destructive
        case .today, .soon: AppColor.warning
        case .fresh, .unknown: AppColor.positive
        }
    }
}

/// One line in the fridge: picture, name, amount, and how long it keeps.
struct FridgeItemRow: View {
    let item: FridgeItem
    let product: FridgeProduct
    let freshness: FridgeEngine.Freshness

    var body: some View {
        HStack(spacing: Spacing.md) {
            FridgeProductImage(product: product)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(product.displayName)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: Spacing.xs) {
                    if item.count > 1 {
                        Text("\(item.count) ×")
                            .monospacedDigit()
                    }
                    if let amount = product.amount {
                        Text(amount)
                    }
                    if product.pantryKey != nil {
                        Image(systemName: "fork.knife")
                            .accessibilityLabel("Used in recipes")
                    }
                }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            FridgeFreshnessBadge(freshness: freshness)
        }
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: Spacing.minimumHitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
