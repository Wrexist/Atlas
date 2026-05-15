import SwiftUI

/// Lifesum-style food library: type a name, pick a result, dial a
/// portion, log it. Sits alongside the barcode and photo scanners as
/// the third entry point on the Lifestyle tab — covers the "I can't
/// scan this" case that the other two flows can't reach (unbranded
/// foods, restaurant items, anything packaged without a barcode the
/// user can present, plus user-defined recipes via `customFoods`).
///
/// Built as a self-contained sheet with a state-machine driving four
/// phases (search → review → logged / not-found). Mirrors the visual
/// language of `BarcodeScanFlow` so the two scanners feel like
/// siblings — same review-card layout, same portion picker, same
/// "Added to today" success screen.
///
/// Search hits the Open Food Facts `/cgi/search.pl` endpoint via the
/// extended `OpenFoodFactsService.search(...)` method. 500 ms debounce
/// + in-memory query cache keeps us well inside OFF's 10 req/min rate
/// limit during normal typing.
struct FoodLibraryFlow: View {
    @Environment(DataStore.self) private var dataStore
    let onClose: () -> Void
    /// Fired when the user picks "Scan a barcode instead" on the
    /// empty / not-found states. The parent dismisses this sheet and
    /// presents `BarcodeScanFlow` — iOS won't show two sheets
    /// concurrently, so the parent has to sequence them.
    let onRequestBarcodeScan: () -> Void
    /// Fired for the "Snap a photo instead" affordance. Same sheet-
    /// handoff dance.
    let onRequestPhotoScan: () -> Void

    @State private var phase: Phase = .browse
    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var results: [ScannedProduct] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String?
    @State private var tab: LibraryTab = .all
    @State private var selectedProduct: ScannedProduct?
    @State private var portion: ScannedProduct.Portion = .grams(100)
    @State private var category: MealCategory = MealCategory.auto(for: Date())
    @State private var loggedSnapshot: LoggedSnapshot?
    @State private var editingCustomFood: CustomFood?
    @State private var pendingDelete: CustomFood?
    /// Cached `ScannedProduct`s pulled from `BarcodeProductCache` for
    /// every favorited OFF barcode. Populated when the user lands on
    /// the Favorites tab so the list paints without a search round-
    /// trip. Refreshed on tab change so a re-favorited item from the
    /// All tab shows up immediately.
    @State private var cachedFavoriteProducts: [ScannedProduct] = []
    /// Food IDs that just got quick-logged from a row's "+" button.
    /// Drives the inline "Logged ✓" overlay + disables the button so
    /// a double-tap can't log the same food twice in the 1.5-second
    /// confirmation window. Cleared after the timeout.
    @State private var recentlyQuickLogged: Set<String> = []
    /// Top-N recently logged OFF products ranked by
    /// `BarcodeScanHistory`'s recency × frequency score, identical to
    /// the BarcodeScanFlow's "Recently scanned" row. Lets the landing
    /// page show real "what did I log lately" content instead of just
    /// custom-food creations.
    @State private var recentOFFProducts: [ScannedProduct] = []

    @FocusState private var searchFieldFocused: Bool

    enum Phase: Equatable {
        case browse        // search + tabs + result list
        case review        // chose a food → portion picker → log
        case logged        // success screen with Undo + auto-close
    }

    enum LibraryTab: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"
        case myFoods = "My Foods"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:       "magnifyingglass"
            case .favorites: "star.fill"
            case .myFoods:   "person.crop.rectangle.stack"
            }
        }
    }

    private struct LoggedSnapshot: Equatable {
        let foodName: String
        let entryID: UUID
        let calories: Int
        let date: Date
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()
                content
            }
            .navigationTitle(phase == .browse ? "Food library" : "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .browse ? "Close" : "Back") {
                        if phase == .browse {
                            onClose()
                        } else {
                            backToBrowse()
                        }
                    }
                    .foregroundStyle(AppColor.textSecondary)
                }
                if phase == .browse {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editingCustomFood = .blank
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColor.accentLight)
                        }
                        .accessibilityLabel("Create custom food")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: query) { await runDebouncedSearch() }
        .task(id: debouncedQuery) { await runSearch() }
        .task(id: phase) {
            guard phase == .logged else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            onClose()
        }
        .task(id: tab) {
            // Favorites lean on the on-disk barcode cache for OFF
            // products the user hasn't re-searched recently. Custom
            // favorites resolve synchronously from `profile.customFoods`,
            // so no cache lookup needed for those.
            guard tab == .favorites else { return }
            await refreshCachedFavorites()
        }
        .task(id: profile.favoriteFoodIDs) {
            // Re-fetch the cached side when the favorites set changes
            // (un-starring or starring inside any tab) so the
            // Favorites tab stays in sync without forcing the user
            // back to it.
            guard tab == .favorites else { return }
            await refreshCachedFavorites()
        }
        .task {
            // Single-shot on first appear: hydrate the landing page's
            // "Recently logged" row from `BarcodeProductCache` +
            // `BarcodeScanHistory`. Cheap (cache reads, no network)
            // and doesn't need re-running on every render.
            await refreshRecentOFFProducts()
        }
        .sheet(item: $editingCustomFood) { food in
            CustomFoodEditorSheet(
                initial: food,
                onSave: { saved in
                    dataStore.saveCustomFood(saved)
                    editingCustomFood = nil
                    tab = .myFoods
                },
                onCancel: { editingCustomFood = nil },
                onDelete: profile.customFoods.contains(where: { $0.id == food.id }) ? { id in
                    dataStore.deleteCustomFood(id: id)
                    editingCustomFood = nil
                } : nil
            )
        }
        .confirmationDialog(
            "Delete this food?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { food in
            Button("Delete \(food.name)", role: .destructive) {
                dataStore.deleteCustomFood(id: food.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Past logs aren't affected — only the food itself disappears from your library.")
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .browse:  browseContent
        case .review:  reviewContent
        case .logged:  loggedContent
        }
    }

    private var browseContent: some View {
        VStack(spacing: 0) {
            searchHeader
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.sm)

            tabSegments
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)

            Divider()
                .background(AppColor.glassBorder.opacity(0.5))
                .padding(.top, Spacing.md)

            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    listBody
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)

            TextField("Search foods, brands, meals…", text: $query)
                .focused($searchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentPrimary)
                .onSubmit { debouncedQuery = query }

            if !query.isEmpty {
                Button {
                    query = ""
                    debouncedQuery = ""
                    results = []
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 48)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            searchFieldFocused ? AppColor.accentPrimary.opacity(0.6) : AppColor.glassBorder,
                            lineWidth: 1
                        )
                }
        }
        .animation(.easeOut(duration: 0.18), value: searchFieldFocused)
    }

    private var tabSegments: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(LibraryTab.allCases) { entry in
                segmentChip(entry)
            }
        }
    }

    private func segmentChip(_ entry: LibraryTab) -> some View {
        let active = (tab == entry)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { tab = entry }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: entry.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(entry.rawValue)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
            }
            .foregroundStyle(active ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background {
                Capsule()
                    .fill(active ? AppColor.accentPrimary.opacity(0.22) : Color.clear)
                    .overlay {
                        Capsule().strokeBorder(
                            active ? AppColor.accentPrimary.opacity(0.55) : AppColor.glassBorder,
                            lineWidth: 1
                        )
                    }
            }
            // Extend the hit region to the 44pt HIG minimum without
            // resizing the visible pill — invisible padding around
            // the chip catches fat-finger taps.
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var listBody: some View {
        switch tab {
        case .all:        allTabBody
        case .favorites:  favoritesTabBody
        case .myFoods:    myFoodsTabBody
        }
    }

    @ViewBuilder
    private var allTabBody: some View {
        if !debouncedQuery.isEmpty {
            // Search-active: show OFF results + matching custom foods
            // (custom matches first — the user explicitly created
            // them, so they outrank a generic OFF entry).
            let customMatches = matchingCustomFoods(for: debouncedQuery)
            if !customMatches.isEmpty {
                sectionHeader("Your foods")
                ForEach(customMatches) { custom in
                    customFoodRow(custom)
                }
            }
            if isSearching && results.isEmpty {
                searchSkeleton
            } else if let searchError, results.isEmpty {
                inlineMessage(icon: "exclamationmark.triangle", text: searchError, tone: .warning)
            } else if results.isEmpty && customMatches.isEmpty && !isSearching {
                emptyState(
                    icon: "questionmark.app.dashed",
                    title: "No results",
                    body: "We couldn't find a match for \"\(debouncedQuery)\". Create a custom food, scan a barcode, or snap a photo."
                )
            } else {
                if !results.isEmpty {
                    sectionHeader("Open Food Facts")
                    ForEach(results, id: \.barcode) { product in
                        productRow(product)
                    }
                }
            }
        } else {
            // No query: empty-state with quick paths + recents.
            browseLanding
        }
    }

    @ViewBuilder
    private var browseLanding: some View {
        VStack(spacing: Spacing.md) {
            quickActionsCard

            if !recentOFFProducts.isEmpty {
                sectionHeader("Recently logged")
                ForEach(recentOFFProducts, id: \.barcode) { product in
                    productRow(product)
                }
            }

            let customRecents = recentCustomFoods()
            if !customRecents.isEmpty {
                sectionHeader(recentOFFProducts.isEmpty ? "Recently added" : "Your foods")
                ForEach(customRecents) { custom in
                    customFoodRow(custom)
                }
            }

            tipCard
        }
    }

    private var quickActionsCard: some View {
        GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Can't find it?")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Try one of these — they cover the cases search can't.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                HStack(spacing: Spacing.sm) {
                    quickActionButton(
                        icon: "barcode.viewfinder",
                        title: "Scan",
                        action: { onRequestBarcodeScan() }
                    )
                    quickActionButton(
                        icon: "camera.fill",
                        title: "Photo",
                        action: { onRequestPhotoScan() }
                    )
                    quickActionButton(
                        icon: "plus.circle.fill",
                        title: "Custom",
                        action: { editingCustomFood = .blank }
                    )
                }
                .padding(.top, 2)
            }
        }
    }

    private func quickActionButton(
        icon: String,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentLight)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Search tips")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Brand name + product works best (\"Fage 0%\", \"Chipotle bowl\"). Save your go-tos as favorites for one-tap re-logs.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.4))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private var favoritesTabBody: some View {
        let favorites = favoriteFoods()
        if favorites.isEmpty {
            emptyState(
                icon: "star.slash.fill",
                title: "No favorites yet",
                body: "Tap the star on any food you log often. Favorites show up here for one-tap re-logs."
            )
        } else {
            sectionHeader("Your favorites")
            ForEach(favorites, id: \.barcode) { product in
                productRow(product)
            }
        }
    }

    @ViewBuilder
    private var myFoodsTabBody: some View {
        if profile.customFoods.isEmpty {
            emptyState(
                icon: "person.crop.rectangle.stack.fill",
                title: "No custom foods",
                body: "Create your own foods for meals and ingredients the database doesn't have."
            )
            Button {
                editingCustomFood = .blank
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create custom food")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .padding(.top, Spacing.sm)
        } else {
            sectionHeader("Your foods (\(profile.customFoods.count))")
            ForEach(profile.customFoods) { custom in
                customFoodRow(custom)
            }
        }
    }

    private var searchSkeleton: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(0..<5, id: \.self) { _ in
                skeletonRow
            }
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.5))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .frame(height: 12)
                    .frame(maxWidth: 200)
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColor.surfaceSecondary.opacity(0.4))
                    .frame(height: 10)
                    .frame(maxWidth: 140)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.3))
        }
        .opacity(0.6)
    }

    // MARK: - Row variants

    private func productRow(_ product: ScannedProduct) -> some View {
        let isFavorite = dataStore.isFavoriteFood(id: product.barcode)
        return Button {
            select(product)
        } label: {
            HStack(spacing: Spacing.sm) {
                productThumbnail(product)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    if let brand = product.brand, brand != product.name {
                        Text(brand)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                    macroPreview(product.per100g)
                }
                Spacer(minLength: 0)
                quickLogButton(product: product)
                favoriteToggle(foodID: product.barcode, isFavorite: isFavorite)
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
            .overlay { quickLoggedOverlay(foodID: product.barcode) }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.rowAccessibilityLabel(name: product.name, brand: product.brand, n: product.per100g))
        .accessibilityHint("Opens the portion picker to log this food. Use the plus button to log instantly with the default portion.")
    }

    private func customFoodRow(_ food: CustomFood) -> some View {
        let isFavorite = dataStore.isFavoriteFood(id: food.foodID)
        return Button {
            select(food.toScannedProduct())
        } label: {
            HStack(spacing: Spacing.sm) {
                customFoodIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(food.brand ?? "Custom food")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                    macroPreview(food.per100g)
                }
                Spacer(minLength: 0)
                quickLogButton(product: food.toScannedProduct())
                favoriteToggle(foodID: food.foodID, isFavorite: isFavorite)
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.accentPrimary.opacity(0.30), lineWidth: 0.5)
                    }
            }
            .overlay { quickLoggedOverlay(foodID: food.foodID) }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.rowAccessibilityLabel(name: food.name, brand: food.brand ?? "Custom food", n: food.per100g))
        .accessibilityHint("Opens the portion picker to log this food. Use the plus button to log instantly with the default portion.")
        .contextMenu {
            Button {
                editingCustomFood = food
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            // Stage the delete instead of firing it directly — the
            // editor sheet's trash button shows a confirmation, and
            // an accidental long-press here shouldn't have looser
            // rules than the explicit edit path.
            Button(role: .destructive) {
                pendingDelete = food
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var customFoodIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.25))
                .frame(width: 44, height: 44)
            Image(systemName: "fork.knife")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
        }
    }

    private func productThumbnail(_ product: ScannedProduct) -> some View {
        AsyncImage(url: product.imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(width: 44, height: 44)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        }
    }

    private func macroPreview(_ n: ScannedProduct.Nutriments) -> some View {
        HStack(spacing: Spacing.xs) {
            macroChip(label: "kcal", value: Int(n.calories.rounded()), tint: AppColor.accentLight)
            macroChip(label: "P", value: Int(n.proteinG.rounded()), tint: .green)
            macroChip(label: "C", value: Int(n.carbsG.rounded()), tint: .blue)
            macroChip(label: "F", value: Int(n.fatG.rounded()), tint: .orange)
        }
        .padding(.top, 2)
    }

    private func macroChip(label: LocalizedStringKey, value: Int, tint: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tint.opacity(0.85))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(tint.opacity(0.18))
        }
    }

    /// One-tap log shortcut on each row. Skips the portion picker and
    /// logs the product's default portion (1 serving when available,
    /// else 100 g) tagged with `MealCategory.auto(for: Date())`. The
    /// 1.5-second "Logged ✓" overlay disables the button + gives
    /// visual feedback so a fat-fingered double-tap can't log twice.
    /// For everything else — multiple servings, a different category,
    /// manual macro edit — the row itself still opens the full
    /// review sheet, so this is purely additive UX.
    private func quickLogButton(product: ScannedProduct) -> some View {
        let inFlight = recentlyQuickLogged.contains(product.barcode)
        return Button {
            performQuickLog(product)
        } label: {
            Image(systemName: inFlight ? "checkmark" : "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(inFlight ? AppColor.accentLight : Color.white)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: inFlight
                                    ? [AppColor.accentLight.opacity(0.35), AppColor.accentLight.opacity(0.20)]
                                    : [AppColor.accentPrimary, AppColor.accentLight],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: AppColor.accentPrimary.opacity(inFlight ? 0 : 0.35), radius: 5, y: 2)
                .contentShape(Rectangle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(inFlight || product.loggable(for: product.defaultPortion) == nil)
        .accessibilityLabel("Quick log \(product.name)")
        .accessibilityHint("Logs the default portion immediately without opening the portion picker.")
    }

    /// Semi-transparent "Logged ✓" wash drawn on top of the row's
    /// background while it's in the confirmation window. Hugs the
    /// row's corners via the parent's background shape so the
    /// rounded edges align visually with the underlying card.
    @ViewBuilder
    private func quickLoggedOverlay(foodID: String) -> some View {
        if recentlyQuickLogged.contains(foodID) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.18))
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accentLight)
                    Text("Logged")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(AppColor.surfaceSecondary.opacity(0.9))
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    /// Builds a MealEntry from the product's default portion + the
    /// current time-of-day category and hands it to the DataStore.
    /// Mirrors `confirmLog(for:)`'s persistence and history wiring
    /// without the review-sheet detour — the user gets identical
    /// macro effects without the extra taps. Animation + haptic +
    /// timed dismissal of the "Logged ✓" overlay live here so the
    /// row knows when to come back to its idle look.
    private func performQuickLog(_ product: ScannedProduct) {
        guard !recentlyQuickLogged.contains(product.barcode),
              let meal = product.loggable(for: product.defaultPortion) else { return }
        let now = Date()
        let source: MealSource = product.barcode.hasPrefix("custom:") ? .custom : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: MealCategory.auto(for: now),
            source: source,
            sourceID: product.barcode,
            date: now
        )
        dataStore.logMealEntry(entry)
        if dataStore.profile.hapticFeedbackEnabled {
            BarcodeHaptics.logCommitted()
        }
        let barcode = product.barcode
        let chosen = product.defaultPortion
        if !barcode.hasPrefix("custom:") {
            Task { await BarcodeScanHistory.shared.recordLog(barcode: barcode, portion: chosen, at: now) }
        }
        withAnimation(.easeOut(duration: 0.18)) {
            recentlyQuickLogged.insert(product.barcode)
        }
        // Clear the badge after 1.5 s so the row returns to its
        // tap-to-log idle state — but keep the in-flight set so a
        // rapid second tap during the window is dropped.
        let foodID = product.barcode
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeIn(duration: 0.18)) {
                recentlyQuickLogged.remove(foodID)
            }
        }
    }

    private func favoriteToggle(foodID: String, isFavorite: Bool) -> some View {
        Button {
            dataStore.toggleFavoriteFood(id: foodID)
            if dataStore.profile.hapticFeedbackEnabled {
                BarcodeHaptics.lookupSuccess()
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFavorite ? AppColor.accentLight : AppColor.textSecondary.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    // MARK: - Section header + states

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, Spacing.xs)
    }

    private func emptyState(
        icon: String,
        title: LocalizedStringKey,
        body: LocalizedStringKey
    ) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppColor.accentLight)
                .padding(.top, Spacing.lg)
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(body)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    private enum InlineTone { case warning, info }

    private func inlineMessage(icon: String, text: String, tone: InlineTone) -> some View {
        let color: Color = (tone == .warning) ? AppColor.warning : AppColor.accentLight
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(color.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(0.35), lineWidth: 1)
                }
        }
    }

    // MARK: - Review phase

    @ViewBuilder
    private var reviewContent: some View {
        if let product = selectedProduct {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    reviewHeader(product)
                    reviewSourceBadge(product)
                    reviewPortionPicker(product)
                    MealCategoryPicker(selection: $category)
                    reviewMacros(product)
                    reviewActions(product)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
        } else {
            EmptyView()
        }
    }

    private func reviewHeader(_ product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.md) {
            if product.barcode.hasPrefix("custom:") {
                customFoodIcon
                    .frame(width: 56, height: 56)
            } else {
                AsyncImage(url: product.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(width: 56, height: 56)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let brand = product.brand, brand != product.name {
                    Text(brand)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
            favoriteToggle(
                foodID: product.barcode,
                isFavorite: dataStore.isFavoriteFood(id: product.barcode)
            )
        }
    }

    private func reviewSourceBadge(_ product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: product.barcode.hasPrefix("custom:") ? "person.crop.rectangle.stack" : "globe")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text(product.barcode.hasPrefix("custom:") ? "Your custom food" : "Open Food Facts")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func reviewPortionPicker(_ product: ScannedProduct) -> some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("How much did you have?")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                HStack(spacing: Spacing.sm) {
                    if product.servingGrams != nil {
                        portionChip(title: "Serving", isActive: portion.isServingsCase) {
                            portion = .servings(1)
                        }
                    }
                    if product.packageGrams != nil {
                        portionChip(title: "Whole pack", isActive: portion == .wholePackage) {
                            portion = .wholePackage
                        }
                    }
                    portionChip(title: "Grams", isActive: portion.isGramsCase) {
                        portion = .grams(100)
                    }
                }

                portionDetail(for: product)
            }
        }
    }

    @ViewBuilder
    private func portionDetail(for product: ScannedProduct) -> some View {
        switch portion {
        case .servings(let count):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Stepper(
                        value: Binding(
                            get: { count },
                            set: { portion = .servings($0) }
                        ),
                        in: 0.5...10,
                        step: 0.5
                    ) {
                        HStack(spacing: 4) {
                            Text(formatServings(count))
                                .font(AppFont.title2)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.textPrimary)
                            Text(count == 1 ? "serving" : "servings")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .tint(AppColor.accentPrimary)
                }
                if let label = product.servingSizeText {
                    Text("1 serving = \(label)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

        case .wholePackage:
            HStack {
                Text("Entire package")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if let g = product.packageGrams {
                    Text("\(Int(g.rounded())) g")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
            }

        case .grams(let g):
            VStack(spacing: Spacing.sm) {
                HStack(spacing: 4) {
                    Text("\(Int(g.rounded()))")
                        .font(AppFont.title2)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text("g")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                }
                Slider(
                    value: Binding(
                        get: { g },
                        set: { portion = .grams($0) }
                    ),
                    in: 10...2000,
                    step: 5
                )
                .tint(AppColor.accentPrimary)
                HStack(spacing: Spacing.xs) {
                    ForEach([50.0, 100.0, 200.0, 500.0], id: \.self) { quick in
                        Button("\(Int(quick))g") { portion = .grams(quick) }
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentLight)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background {
                                Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                            }
                    }
                }
            }
        }
    }

    private func portionChip(title: LocalizedStringKey, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? AppColor.textPrimary : AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .background {
                    Capsule()
                        .fill(isActive ? AppColor.accentPrimary.opacity(0.25) : Color.clear)
                        .overlay {
                            Capsule().strokeBorder(
                                isActive ? AppColor.accentPrimary.opacity(0.55) : AppColor.glassBorder,
                                lineWidth: 1
                            )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func reviewMacros(_ product: ScannedProduct) -> some View {
        let meal = product.loggable(for: portion)
        // OFF entries with incomplete data report 0 kcal/100g for the
        // whole product — distinct from a legitimate zero-calorie
        // item like black coffee. Surface the ambiguity instead of
        // silently logging zeros: a user expecting macros to land
        // would otherwise wonder why their rings didn't move.
        let zeroCaloriesPer100g = product.per100g.calories <= 0
            && !product.barcode.hasPrefix("custom:")
        return VStack(spacing: Spacing.sm) {
            GlassCard(tinted: true, padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Nutrition")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    Divider().background(AppColor.glassBorder)
                    macroRow(label: "Calories", value: "\(meal?.calories ?? 0) kcal")
                    macroRow(label: "Protein",  value: "\(meal?.proteinG ?? 0) g")
                    macroRow(label: "Carbs",    value: "\(meal?.carbsG ?? 0) g")
                    macroRow(label: "Fat",      value: "\(meal?.fatG ?? 0) g")
                }
            }
            if zeroCaloriesPer100g {
                inlineMessage(
                    icon: "exclamationmark.triangle.fill",
                    text: "This product has no calorie data in Open Food Facts. Snap the nutrition label or save it as a custom food.",
                    tone: .warning
                )
            }
        }
    }

    private func macroRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func reviewActions(_ product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.sm) {
            Button("Back") { backToBrowse() }
                .buttonStyle(.bordered)
                .tint(AppColor.textSecondary)

            Button("Add to today") {
                confirmLog(for: product)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .disabled(product.loggable(for: portion) == nil)
        }
    }

    // MARK: - Logged phase

    @ViewBuilder
    private var loggedContent: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text("Added to today")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
            if let snapshot = loggedSnapshot {
                LoggedCaloriePanel(
                    productName: snapshot.foodName,
                    deltaCalories: snapshot.calories,
                    totalCalories: dataStore.consumption().caloriesKcal,
                    targetCalories: (dataStore.profile.nutritionTargets ?? .placeholder).calories
                )
            }
            VStack(spacing: Spacing.sm) {
                Button {
                    undoLastLog()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.destructive.opacity(0.85))

                Button("Done") { onClose() }
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, Spacing.sm)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.xxxxl)
    }

    // MARK: - Actions / helpers

    private var profile: UserProfile { dataStore.profile }

    private func select(_ product: ScannedProduct) {
        selectedProduct = product
        portion = product.defaultPortion
        // Re-evaluate the auto-category against the wall clock each
        // time we open a review — fixes the case where a user opens
        // the library at 10:55 (defaults to breakfast), browses for a
        // few minutes, then logs at 11:05 expecting lunch.
        category = MealCategory.auto(for: Date())
        phase = .review
        searchFieldFocused = false
        if dataStore.profile.hapticFeedbackEnabled {
            BarcodeHaptics.lookupSuccess()
        }
    }

    private func backToBrowse() {
        selectedProduct = nil
        portion = .grams(100)
        phase = .browse
    }

    private func confirmLog(for product: ScannedProduct) {
        guard let meal = product.loggable(for: portion) else { return }
        let now = Date()
        let source: MealSource = product.barcode.hasPrefix("custom:") ? .custom : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: category,
            source: source,
            sourceID: product.barcode,
            date: now
        )
        dataStore.logMealEntry(entry)
        if dataStore.profile.hapticFeedbackEnabled {
            BarcodeHaptics.logCommitted()
        }
        loggedSnapshot = LoggedSnapshot(
            foodName: product.name,
            entryID: entry.id,
            calories: meal.calories,
            date: now
        )
        // Record the choice in scan history so this food shows up in
        // the barcode recents row too — keeps the two scanners' notion
        // of "recently logged" consistent. Fire-and-forget.
        //
        // Custom foods carry a synthetic `custom:<uuid>` barcode that
        // `BarcodeScanHistory.normalize` would throw on (it expects
        // 8-14 digits). Skip them — their own recents path lives on
        // `profile.customFoods.updatedAt`, not the scan-history actor.
        let barcode = product.barcode
        let chosen = portion
        if !barcode.hasPrefix("custom:") {
            Task { await BarcodeScanHistory.shared.recordLog(barcode: barcode, portion: chosen, at: now) }
        }
        phase = .logged
    }

    private func undoLastLog() {
        guard let snapshot = loggedSnapshot else {
            onClose()
            return
        }
        // Transition out of `.logged` *first* so the auto-close task
        // (`.task(id: phase)`) is cancelled by SwiftUI before its
        // sleep resolves — otherwise the timer fires `onClose()`
        // again after the undo path already called it.
        phase = .browse
        // Removing the entry rolls back the aggregate in one step,
        // so we don't need to keep the macro values around for an
        // explicit `unlogMeal` call.
        dataStore.unlogMealEntry(id: snapshot.entryID)
        if dataStore.profile.hapticFeedbackEnabled {
            BarcodeHaptics.logUndone()
        }
        onClose()
    }

    // MARK: - Search debouncing

    /// Debounce loop. Fired on every `query` change; waits 500 ms before
    /// promoting the value to `debouncedQuery`. The `.task(id: query)`
    /// modifier cancels the previous instance on the next keystroke so
    /// only the pause-after-last-keystroke survives.
    private func runDebouncedSearch() async {
        let snapshot = query
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, snapshot == query else { return }
        debouncedQuery = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fires when `debouncedQuery` actually changes — the network call.
    /// Cleared queries short-circuit so empty searches don't hit OFF.
    /// `defer` reliably clears the spinner even when the task is
    /// cancelled mid-await — without it, fast typists would see the
    /// skeleton loader hang until the next non-cancelled search.
    private func runSearch() async {
        defer { isSearching = false }

        let trimmed = debouncedQuery
        guard trimmed.count >= 2 else {
            results = []
            searchError = nil
            return
        }

        isSearching = true
        searchError = nil
        do {
            let hits = try await OpenFoodFactsService.shared.search(query: trimmed)
            guard !Task.isCancelled, trimmed == debouncedQuery else { return }
            results = hits
        } catch let lookupError as OpenFoodFactsService.LookupError {
            guard !Task.isCancelled, trimmed == debouncedQuery else { return }
            results = []
            searchError = lookupError.errorDescription
        } catch {
            guard !Task.isCancelled, trimmed == debouncedQuery else { return }
            results = []
            searchError = error.localizedDescription
        }
    }

    private func matchingCustomFoods(for query: String) -> [CustomFood] {
        let needle = query.lowercased()
        return profile.customFoods.filter { food in
            food.name.lowercased().contains(needle)
                || (food.brand?.lowercased().contains(needle) ?? false)
        }
    }

    private func recentCustomFoods() -> [CustomFood] {
        Array(profile.customFoods.prefix(5))
    }

    /// Reconstructs `ScannedProduct`s for the favorites tab. Custom
    /// favorites resolve synchronously from `profile.customFoods`; OFF
    /// favorites come from the in-memory cache populated by
    /// `refreshCachedFavorites()`, with the current search results as
    /// a fallback. Missing OFF entries (favorited then evicted from
    /// every cache) are silently dropped — we can't show macros for a
    /// product we no longer have data for, and re-fetching N IDs would
    /// burn the rate limit.
    private func favoriteFoods() -> [ScannedProduct] {
        let ids = profile.favoriteFoodIDs
        guard !ids.isEmpty else { return [] }

        let customByID: [String: CustomFood] = Dictionary(
            uniqueKeysWithValues: profile.customFoods.map { ($0.foodID, $0) }
        )
        let cachedByID: [String: ScannedProduct] = Dictionary(
            uniqueKeysWithValues: cachedFavoriteProducts.map { ($0.barcode, $0) }
        )

        var out: [ScannedProduct] = []
        for id in ids {
            if let custom = customByID[id] {
                out.append(custom.toScannedProduct())
            } else if let cached = cachedByID[id] {
                out.append(cached)
            } else if let hit = results.first(where: { $0.barcode == id }) {
                out.append(hit)
            }
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Loads the top-N recently logged OFF products into the landing
    /// page's "Recently logged" row. Mirrors `BarcodeScanFlow.loadRecentlyScanned`
    /// — pulls candidates from the on-disk product cache and re-ranks
    /// by the scan-history actor's recency × frequency score so a
    /// daily product outranks a one-off scan from yesterday.
    private func refreshRecentOFFProducts() async {
        let candidates = await OpenFoodFactsService.shared.recent(limit: 20)
        guard !candidates.isEmpty else {
            recentOFFProducts = []
            return
        }
        let scores = await BarcodeScanHistory.shared.scores(for: candidates.map(\.barcode))
        guard !Task.isCancelled else { return }
        recentOFFProducts = candidates
            .sorted { (scores[$0.barcode] ?? 0) > (scores[$1.barcode] ?? 0) }
            .prefix(5)
            .map { $0 }
    }

    /// Pulls cached `ScannedProduct`s for every favorited OFF barcode
    /// off the `BarcodeProductCache` actor. Skips `custom:` IDs (those
    /// resolve from `profile.customFoods` instead). Runs on the
    /// favorites-tab task hook so the list paints without a search.
    /// Per-iteration cancellation check matters because a user
    /// flipping tabs mid-loop shouldn't keep hammering the cache —
    /// each actor hop is cheap but pointless once the work has been
    /// invalidated.
    private func refreshCachedFavorites() async {
        let offIDs = profile.favoriteFoodIDs.filter { !$0.hasPrefix("custom:") }
        guard !offIDs.isEmpty else {
            cachedFavoriteProducts = []
            return
        }
        var pulled: [ScannedProduct] = []
        pulled.reserveCapacity(offIDs.count)
        for id in offIDs {
            if Task.isCancelled { return }
            if let product = await BarcodeProductCache.shared.read(barcode: id) {
                pulled.append(product)
            }
        }
        guard !Task.isCancelled else { return }
        cachedFavoriteProducts = pulled
    }

    private func formatServings(_ count: Double) -> String {
        count.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", count)
            : String(format: "%.1f", count)
    }

    /// Single canonical VoiceOver label for both OFF and custom-food
    /// rows. Spells the macro letters out ("grams protein" instead of
    /// "P") so the screen-reader voice reads naturally instead of
    /// stuttering "pee see eff" through the abbreviations the visible
    /// chips use.
    ///
    /// Each interpolated segment is wrapped in `String(localized:)`
    /// so the catalog can hold localizations for "kilocalories",
    /// "grams protein", etc. without forcing the whole sentence to
    /// be re-translated for every product name.
    private static func rowAccessibilityLabel(
        name: String,
        brand: String?,
        n: ScannedProduct.Nutriments
    ) -> String {
        let header: String
        if let brand, !brand.isEmpty {
            header = String(
                localized: "\(name), \(brand), per 100 grams:",
                comment: "Accessibility row header with brand."
            )
        } else {
            header = String(
                localized: "\(name), per 100 grams:",
                comment: "Accessibility row header without brand."
            )
        }
        let kcal = String(
            localized: "\(Int(n.calories.rounded())) kilocalories",
            comment: "VoiceOver readout of calories per serving."
        )
        let protein = String(
            localized: "\(Int(n.proteinG.rounded())) grams protein",
            comment: "VoiceOver readout of protein grams."
        )
        let carbs = String(
            localized: "\(Int(n.carbsG.rounded())) grams carbs",
            comment: "VoiceOver readout of carbohydrate grams."
        )
        let fat = String(
            localized: "\(Int(n.fatG.rounded())) grams fat",
            comment: "VoiceOver readout of fat grams."
        )
        return "\(header) \(kcal), \(protein), \(carbs), \(fat)."
    }
}

// MARK: - Portion case helpers (kept private to avoid colliding with the
// equivalent file-private extension in BarcodeScanFlow.swift)

private extension ScannedProduct.Portion {
    var isServingsCase: Bool {
        if case .servings = self { return true }
        return false
    }
    var isGramsCase: Bool {
        if case .grams = self { return true }
        return false
    }
}

