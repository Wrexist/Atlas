import SwiftUI

/// "Fridge": everything at home, kept track of.
///
/// The floating shelf on top shows what is in; below it what should be
/// eaten soon, then the fridge, freezer and cupboard, soonest use-by
/// first. Things go in by scanning the whole fridge or a shopping haul, by
/// a photo of one product (its background lifted away), by barcode, or by
/// searching products bought before and tapping one. Recipes that cook
/// from what is here, and what is missing to complete them, close the
/// screen.
struct FridgeView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var store = FridgeStore.shared
    @State private var pantry = PantryStore.shared
    @State private var query = ""
    @State private var editor: EditorTarget?
    @State private var showScan = false
    @State private var shelfFloating = false
    @State private var toast: LocalizedStringKey?
    @State private var toastTask: Task<Void, Never>?

    private var calendar: Calendar { .current }

    /// Saved products shown in "Buy again" when not searching.
    private static let buyAgainLimit = 12

    var body: some View {
        let now = Date()
        let products = store.productsByID
        let items = FridgeEngine.sorted(store.items, products: products)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if !query.isEmpty {
                    searchResults(items: items)
                } else if items.isEmpty {
                    emptyState
                    addActions
                    buyAgain
                } else {
                    FridgeShelf(entries: shelfEntries(items, products: products, now: now), isFloating: $shelfFloating) { id in
                        editor = .item(id)
                    }
                    .scrollReveal()
                    summary(items, now: now)
                    addActions
                    buyAgain
                    sections(items, products: products, now: now)
                    cookCard(products: products, now: now)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
            .readableContentWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Fridge")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: Text("Search saved products"))
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $editor) { target in
            editorSheet(target)
                .liquidGlassPresentation()
        }
        .sheet(isPresented: $showScan) {
            FridgeScanFlow(
                onDone: { count in
                    showScan = false
                    show(Self.putInMessage(count))
                },
                onClose: { showScan = false }
            )
            .environment(dataStore)
        }
    }

    // MARK: - Top

    private var emptyState: some View {
        EmptyStateView(
            icon: "refrigerator",
            title: "Your fridge, kept track of",
            message: "Scan the fridge or your shopping and Atlas keeps an eye on use-by dates and cooks from what you have.",
            action: .init(title: "Scan the fridge", icon: "camera.viewfinder") { showScan = true }
        )
    }

    private func shelfEntries(_ items: [FridgeItem], products: [UUID: FridgeProduct], now: Date) -> [FridgeShelf.Entry] {
        items.compactMap { item in
            guard let product = products[item.productID] else { return nil }
            let needsUse = FridgeEngine.freshness(item.expiresOn, now: now, calendar: calendar).needsUse
            return FridgeShelf.Entry(id: item.id, product: product, count: item.count, needsUse: needsUse)
        }
    }

    private func summary(_ items: [FridgeItem], now: Date) -> some View {
        let total = items.reduce(0) { $0 + $1.count }
        let soon = items.filter { FridgeEngine.freshness($0.expiresOn, now: now, calendar: calendar).needsUse }.count
        return HStack(spacing: Spacing.sm) {
            StatChip(icon: "basket.fill", text: Self.itemCount(total), tint: AppColor.accentLight)
            if soon > 0 {
                StatChip(icon: "clock.badge.exclamationmark.fill", text: "\(soon) to use soon", tint: AppColor.warning)
            }
            Spacer(minLength: 0)
            FridgeFloatToggle(isFloating: $shelfFloating)
        }
        .appAnimation(AppAnimation.settle, value: [total, soon])
    }

    /// The scan leads on its own full-width row; the three single-item ways
    /// share the row below. Four tiles across cut every label short
    /// ("Skanna kyl…") and gave the main action the same weight as typing.
    private var addActions: some View {
        VStack(spacing: Spacing.sm) {
            ScanFridgeRow { showScan = true }
            HStack(spacing: Spacing.sm) {
                AddTile(icon: "camera.fill", title: "Photo", subtitle: "One item") { editor = .new(.camera) }
                AddTile(icon: "barcode.viewfinder", title: "Barcode", subtitle: "Exact product") { editor = .new(.barcode) }
                AddTile(icon: "plus", title: "Type", subtitle: "By hand") { editor = .new(nil) }
            }
        }
    }

    // MARK: - Buy again

    @ViewBuilder
    private var buyAgain: some View {
        let inFridge = Set(store.items.map(\.productID))
        let saved = FridgeEngine.search(store.products, query: "").filter { !inFridge.contains($0.id) }.prefix(Self.buyAgainLimit)
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HomeSectionHeader(eyebrow: "Saved", title: "Bought it again?")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(Array(saved)) { product in
                            Button { quickAdd(product) } label: {
                                VStack(spacing: Spacing.xs) {
                                    FridgeProductImage(product: product, size: 64)
                                        .appShadow(AppShadow.glassSubtle)
                                    Text(product.name)
                                        .font(AppFont.caption2.weight(.semibold))
                                        .foregroundStyle(AppColor.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 80)
                                }
                                .padding(.vertical, Spacing.xs)
                            }
                            .buttonStyle(ScalePressStyle(pressedScale: 0.92))
                            .contextMenu {
                                Button { editor = .product(product.id) } label: { Label("Edit, then add", systemImage: "pencil") }
                                Button(role: .destructive) { store.forget(product.id) } label: {
                                    Label("Forget this product", systemImage: "xmark.bin")
                                }
                            }
                            .accessibilityLabel(Text(product.displayName))
                            .accessibilityHint("Puts it back in the fridge.")
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .scrollClipDisabled()
            }
            .scrollReveal()
        }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchResults(items: [FridgeItem]) -> some View {
        let matches = FridgeEngine.search(store.products, query: query)
        if matches.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "Not saved yet",
                message: "Add it once and it's here next time.",
                action: .init(title: "Add “\(query)”", icon: "plus") {
                    editor = .new(nil, name: query)
                },
                style: .compact
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, product in
                    if index > 0 {
                        Divider().overlay(AppColor.glassBorder)
                    }
                    searchRow(product, inFridge: items.filter { $0.productID == product.id }.reduce(0) { $0 + $1.count })
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
    }

    private func searchRow(_ product: FridgeProduct, inFridge: Int) -> some View {
        HStack(spacing: Spacing.md) {
            Button { editor = .product(product.id) } label: {
                HStack(spacing: Spacing.md) {
                    FridgeProductImage(product: product)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(product.displayName)
                            .font(AppFont.body.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Group {
                            if inFridge > 0 {
                                Text("\(inFridge) at home")
                            } else {
                                Text(product.place.label)
                            }
                        }
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))

            Button { quickAdd(product) } label: {
                Image(systemName: "plus")
                    .font(AppFont.scaled(16, weight: .bold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 36, height: 36)
                    .background(AppColor.accentFill, in: Circle())
            }
            .buttonStyle(ScalePressStyle())
            .minimumHitArea()
            .accessibilityLabel(Text("Add \(product.name)"))
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Lists

    @ViewBuilder
    private func sections(_ items: [FridgeItem], products: [UUID: FridgeProduct], now: Date) -> some View {
        let soon = items.filter { FridgeEngine.freshness($0.expiresOn, now: now, calendar: calendar).needsUse }
        if !soon.isEmpty {
            itemSection(eyebrow: "Use soon", title: "About to go off", items: soon, products: products, now: now)
        }
        ForEach(FridgePlace.allCases) { place in
            let kept = items.filter {
                $0.place == place && !FridgeEngine.freshness($0.expiresOn, now: now, calendar: calendar).needsUse
            }
            if !kept.isEmpty {
                itemSection(eyebrow: "In the kitchen", title: place.label, items: kept, products: products, now: now)
            }
        }
    }

    private func itemSection(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        items: [FridgeItem],
        products: [UUID: FridgeProduct],
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(eyebrow: eyebrow, title: title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if let product = products[item.productID] {
                        if index > 0 {
                            Divider().overlay(AppColor.glassBorder)
                        }
                        Button { editor = .item(item.id) } label: {
                            FridgeItemRow(
                                item: item,
                                product: product,
                                freshness: FridgeEngine.freshness(item.expiresOn, now: now, calendar: calendar)
                            )
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
                        .contextMenu { itemMenu(item) }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
            .appAnimation(AppAnimation.springSnappy, value: items)
        }
        .scrollReveal()
    }

    @ViewBuilder
    private func itemMenu(_ item: FridgeItem) -> some View {
        Button { useOne(item) } label: {
            Label(item.count > 1 ? "Used one" : "Used it up", systemImage: "fork.knife")
        }
        if item.place != .freezer {
            Button { move(item, to: .freezer) } label: { Label("Move to freezer", systemImage: "snowflake") }
        }
        Button(role: .destructive) {
            AppAnimation.with(AppAnimation.springSnappy) { store.remove(item.id) }
            Haptics.impact(.light)
        } label: {
            Label("Throw out", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func cookCard(products: [UUID: FridgeProduct], now: Date) -> some View {
        let suggestions = FridgeEngine.suggestions(
            recipes: RecipeLibraryEngine.bundled,
            have: pantry.keys,
            fridgeKeys: store.pantryKeys,
            expiringKeys: FridgeEngine.expiringKeys(items: store.items, products: products, now: now, calendar: calendar)
        )
        if !suggestions.isEmpty {
            FridgeCookCard(suggestions: suggestions)
                .scrollReveal()
        }
    }

    // MARK: - Editor

    enum EditorTarget: Identifiable {
        case new(FridgeItemEditor.Shortcut?, name: String = "")
        case item(UUID)
        case product(UUID)

        var id: String {
            switch self {
            case .new(let shortcut, let name): "new-\(String(describing: shortcut))-\(name)"
            case .item(let id): "item-\(id)"
            case .product(let id): "product-\(id)"
            }
        }
    }

    @ViewBuilder
    private func editorSheet(_ target: EditorTarget) -> some View {
        switch target {
        case .new(let shortcut, let name):
            FridgeItemEditor(
                product: name.isEmpty ? nil : FridgeProduct(name: name),
                shortcut: shortcut,
                onClose: { editor = nil }
            )
        case .item(let id):
            if let item = store.items.first(where: { $0.id == id }) {
                FridgeItemEditor(item: item, product: store.product(for: item), onClose: { editor = nil })
            }
        case .product(let id):
            FridgeItemEditor(product: store.products.first { $0.id == id }, onClose: { editor = nil })
        }
    }

    // MARK: - Actions

    /// Back in, with a use-by date from how long it kept last time.
    private func quickAdd(_ product: FridgeProduct) {
        let days = product.shelfDays ?? FridgeEngine.defaultShelfDays(place: product.place, pantryKey: product.pantryKey)
        AppAnimation.with(AppAnimation.springSnappy) {
            store.add(product, expiresOn: FridgeEngine.expiry(from: .now, shelfDays: days, calendar: calendar))
        }
        Haptics.success()
        show("\(product.name) put in")
    }

    private func useOne(_ item: FridgeItem) {
        AppAnimation.with(AppAnimation.springSnappy) { store.useOne(item.id) }
        Haptics.success()
    }

    private func move(_ item: FridgeItem, to place: FridgePlace) {
        var moved = item
        moved.place = place
        if place == .freezer {
            moved.expiresOn = FridgeEngine.expiry(from: .now, shelfDays: FridgeEngine.defaultShelfDays(place: .freezer, pantryKey: nil), calendar: calendar)
        }
        AppAnimation.with(AppAnimation.springSnappy) { store.update(moved) }
        Haptics.impact(.light)
    }

    private static func putInMessage(_ count: Int) -> LocalizedStringKey {
        if count == 1 { return "1 item put in" }
        return "\(count) items put in"
    }

    private static func itemCount(_ count: Int) -> LocalizedStringKey {
        if count == 1 { return "1 item" }
        return "\(count) items"
    }

    private func show(_ message: LocalizedStringKey) {
        AppAnimation.with(AppAnimation.toast) { toast = message }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            guard !Task.isCancelled else { return }
            AppAnimation.with(AppAnimation.toast) { toast = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.positive)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassSurfaceCapsule()
                .padding(.bottom, Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// One of the four ways in, as a small glass tile.
private struct ScanFridgeRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "camera.viewfinder")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(AppColor.accentFill, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Scan fridge")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Or a shopping bag")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.cardPadding)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius, tinted: true)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
    }
}

private struct AddTile: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 40, height: 40)
                    .background(AppColor.accentPrimary.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
    }
}

/// A count with its icon, as a soft pill.
private struct StatChip: View {
    let icon: String
    let text: LocalizedStringKey
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(AppFont.chipText)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    NavigationStack {
        FridgeView()
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
