import SwiftUI

/// One product the fridge scan found, before it is put in.
struct ReviewGrocery: Identifiable {
    let id: UUID
    let sticker: UIImage
    /// Where it sat in the photo, 0…1.
    let frame: CGRect
    var include = true
    var name: String
    var count: Int
    var place: FridgePlace
    var expiresOn: Date?
    let brand: String?
    let amount: String?
    let pantryKey: String?
    let per100g: ScannedProduct.Nutriments?

    /// A date printed on the pack wins; then how long the same product
    /// kept last time; then the scan's typical shelf life.
    init(_ found: FridgeScanService.Found, sticker: UIImage, saved: FridgeProduct?, now: Date = .now, calendar: Calendar = .current) {
        id = found.id
        self.sticker = sticker
        frame = found.box
        name = found.name
        count = found.count
        place = found.place
        brand = found.brand
        amount = found.amount
        pantryKey = found.pantryKey ?? saved?.pantryKey
        per100g = found.per100g
        expiresOn = found.printedExpiry
            ?? FridgeEngine.expiry(from: now, shelfDays: saved?.shelfDays ?? found.shelfDays, calendar: calendar)
    }

    var product: FridgeProduct {
        FridgeProduct(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Item") : name,
            brand: brand,
            pantryKey: pantryKey,
            amount: amount,
            place: place,
            per100g: per100g
        )
    }
}

/// Grid cell on the fridge scan review: the floating cut-out with its keep
/// tick, an editable name, and how many, where and until when.
struct FridgeScanCell: View {
    @Binding var grocery: ReviewGrocery
    /// False while the cut-out is still flying out of the photo.
    let isLanded: Bool
    let namespace: Namespace.ID

    @Environment(\.locale) private var locale

    static let stickerHeight: CGFloat = 110

    var body: some View {
        VStack(spacing: Spacing.sm) {
            sticker
            TextField("Name", text: $grocery.name)
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassControl(.capsule, interactive: false)
                .accessibilityLabel("Item name")
            HStack(spacing: Spacing.xs) {
                countMenu
                placeMenu
                dateMenu
            }
        }
        .opacity(grocery.include ? 1 : 0.45)
        .appAnimation(AppAnimation.springSnappy, value: grocery.include)
    }

    private var sticker: some View {
        Button {
            grocery.include.toggle()
            Haptics.selection()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isLanded {
                        Image(uiImage: grocery.sticker)
                            .resizable()
                            .scaledToFit()
                            .frame(height: Self.stickerHeight)
                            .matchedGeometryEffect(id: grocery.id, in: namespace)
                            .appShadow(AppShadow.glassSubtle)
                            .saturation(grocery.include ? 1 : 0)
                            .scaleEffect(grocery.include ? 1 : 0.9)
                    } else {
                        Color.clear.frame(height: Self.stickerHeight)
                    }
                }
                .frame(maxWidth: .infinity)

                Image(systemName: grocery.include ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(grocery.include ? AppColor.accentPrimary : AppColor.textTertiary)
                    .background(Circle().fill(AppColor.background).padding(Spacing.xxs))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: grocery.include)
                    .opacity(isLanded ? 1 : 0)
                    .scaleEffect(isLanded ? 1 : 0.4)
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.96))
        .accessibilityLabel(Text(grocery.name))
        .accessibilityAddTraits(grocery.include ? .isSelected : [])
        .accessibilityHint("Keeps or leaves out this item.")
    }

    private var countMenu: some View {
        Menu {
            ForEach(1...12, id: \.self) { value in
                Button("\(value)") { grocery.count = value }
            }
        } label: {
            chip(Text("\(grocery.count)×").monospacedDigit())
        }
        .accessibilityLabel(Text("How many: \(grocery.count)"))
    }

    private var placeMenu: some View {
        Menu {
            ForEach(FridgePlace.allCases) { place in
                Button { grocery.place = place } label: { Label(place.label, systemImage: place.icon) }
            }
        } label: {
            chip(Image(systemName: grocery.place.icon))
        }
        .accessibilityLabel(Text(grocery.place.label))
    }

    private var dateMenu: some View {
        Menu {
            Button("Tomorrow") { setDays(1) }
            Button("3 days") { setDays(3) }
            Button("1 week") { setDays(7) }
            Button("2 weeks") { setDays(14) }
            Button("1 month") { setDays(30) }
            Button("No date") { grocery.expiresOn = nil }
        } label: {
            chip(dateText)
        }
        .accessibilityLabel(Text("Use by"))
    }

    private var dateText: Text {
        guard let expiresOn = grocery.expiresOn else { return Text("No date") }
        return Text(expiresOn.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
    }

    private func setDays(_ days: Int) {
        let calendar = Calendar.current
        grocery.expiresOn = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: .now))
    }

    private func chip(_ content: some View) -> some View {
        content
            .font(AppFont.caption2.weight(.semibold))
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 32)
            .glassControl(.capsule)
            .minimumHitArea()
    }
}
