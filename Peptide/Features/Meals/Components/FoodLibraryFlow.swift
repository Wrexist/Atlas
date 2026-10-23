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
    /// Optional Spotlight deep-link payload — when set on present,
    /// the sheet resolves the referenced food and jumps directly to
    /// the review phase without forcing the user to retype their
    /// search. Single-use: parent clears it after the sheet
    /// dismisses.
    var initialDeepLink: FoodLogDeepLink? = nil
    /// Day the Meals tab is showing. Logs land on it at the current
    /// clock time, so back-filling yesterday doesn't drop into today.
    var logDay: Date = Date()

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
    @State private var lastLoggedEntry: MealEntry?
    @State private var mealSaveError: String?
    @State private var editingExactPortion = false
    @State private var loggedHistoryBarcode: String?
    @State private var historyWriteTask: Task<Void, Never>?
    @State private var editingCustomFood: CustomFood?
    /// Typed search the user asked Atlas AI to turn into a food. The
    /// editor opens already filling itself from it.
    @State private var aiFillQuery: String?
    @State private var pendingDelete: CustomFood?
    @State private var editingRecipe: Recipe?
    @State private var pendingRecipeDelete: Recipe?
    /// Recipe waiting on a category-pick before logging. Drives a
    /// quick MealCategoryPicker confirm step that defaults to the
    /// time-of-day auto-category but lets the user re-route.
    @State private var recipeToRepair: Recipe?
    @State private var pendingRecipeLog: Recipe?
    /// Cached `ScannedProduct`s pulled from `BarcodeProductCache` for
    /// every favorited OFF barcode. Populated when the user lands on
    /// the Favorites tab so the list paints without a search round-
    /// trip. Refreshed on tab change so a re-favorited item from the
    /// All tab shows up immediately.
    @State private var cachedFavoriteProducts: [ScannedProduct] = []
    /// `true` once the most recent search hit a network-unavailable
    /// error. Toggles the offline pill at the top of the list and
    /// suppresses the rate-limit / "no match" copy so the user knows
    /// they're seeing cached results only.
    @State private var isOffline: Bool = false
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
        case logged        // success screen with persistent Undo
    }

    /// Minimum number of characters before the search bar fires a
    /// network request. Matches `OpenFoodFactsService.search`'s own
    /// guard so the two layers can't drift.
    static let minimumSearchQueryLength: Int = 2

    enum LibraryTab: String, CaseIterable, Identifiable {
        case all, favorites, myFoods, recipes
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all:       "All"
            case .favorites: "Favorites"
            case .myFoods:   "My Foods"
            case .recipes:   "Recipes"
            }
        }

        var icon: String {
            switch self {
            case .all:       "magnifyingglass"
            case .favorites: "star.fill"
            case .myFoods:   "person.crop.rectangle.stack"
            case .recipes:   "list.bullet.rectangle.fill"
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Review steps back to the list; the logged screen
                    // already offers "Log another food", so its toolbar
                    // action finishes instead.
                    switch phase {
                    case .browse:
                        Button("Close", action: onClose)
                            .foregroundStyle(AppColor.textSecondary)
                    case .review:
                        Button("Back", action: backToBrowse)
                            .foregroundStyle(AppColor.textSecondary)
                    case .logged:
                        Button("Done", action: onClose)
                            .foregroundStyle(AppColor.textSecondary)
                    }
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
        .presentationSizing(.page)
        .task(id: query) { await runDebouncedSearch() }
        .task(id: debouncedQuery) { await runSearch() }
        .alert("Meal action failed", isPresented: Binding(
            get: { mealSaveError != nil }, set: { if !$0 { mealSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { mealSaveError = nil }
        } message: { Text(mealSaveError ?? "Please retry.") }
        .task(id: favoritesTaskID) {
            // Single task driving the Favorites tab's data refresh.
            // Re-fires on either tab change or favorite-set change
            // by virtue of the composite id, so two separate tasks
            // (with the same body + guard) collapse into one — no
            // redundant actor hops when both inputs move together.
            //
            // Favorites lean on the on-disk barcode cache for OFF
            // products the user hasn't re-searched recently. Custom
            // favorites resolve synchronously from `profile.customFoods`.
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
        .task(id: initialDeepLink) {
            // Spotlight deep-link path. Resolves the namespaced
            // identifier into a `ScannedProduct` and transitions
            // straight to the review phase so a tap on a Spotlight
            // tile lands the user one tap away from logging.
            //
            // task(id:) re-runs whenever initialDeepLink changes —
            // including when the user taps a second Spotlight result
            // while the library is already open. Previously the
            // .task fired only on first mount and ignored later
            // deep-links (audit Meals HIGH 1: recipe tile silently
            // dropped when library was already up).
            if let deepLink = initialDeepLink {
                await resolveDeepLink(deepLink)
            }
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
                } : nil,
                autoFillQuery: aiFillQuery
            )
            .onDisappear { aiFillQuery = nil }
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
        .sheet(item: $editingRecipe) { recipe in
            RecipeEditorSheet(
                initial: recipe,
                availableCustomFoods: profile.customFoods,
                onSave: { saved in
                    dataStore.saveRecipe(saved)
                    editingRecipe = nil
                    tab = .recipes
                },
                onDelete: profile.recipes.contains(where: { $0.id == recipe.id }) ? { id in
                    dataStore.deleteRecipe(id: id)
                    editingRecipe = nil
                } : nil,
                onCancel: { editingRecipe = nil }
            )
        }
        .confirmationDialog(
            "Delete this recipe?",
            isPresented: Binding(
                get: { pendingRecipeDelete != nil },
                set: { if !$0 { pendingRecipeDelete = nil } }
            ),
            presenting: pendingRecipeDelete
        ) { recipe in
            Button("Delete \(recipe.name)", role: .destructive) {
                dataStore.deleteRecipe(id: recipe.id)
                pendingRecipeDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingRecipeDelete = nil }
        } message: { _ in
            Text("Past meal logs aren't affected — only the recipe disappears from your library.")
        }
        .sheet(isPresented: $editingExactPortion) {
            if let product = selectedProduct, let component = product.loggable(for: portion)?.components?.first {
                FoodPortionEditor(component: component) { portion = .grams($0) }
            }
        }
        .sheet(item: $pendingRecipeLog, onDismiss: {
            if let recipeToRepair {
                editingRecipe = recipeToRepair
                self.recipeToRepair = nil
            }
        }) { recipe in
            RecipeLogConfirmSheet(
                recipe: recipe,
                customFoods: profile.customFoods,
                onLog: { category in
                    guard let entry = dataStore.logRecipe(recipe, category: category, at: logTimestamp()) else { return false }
                    showLogged(entry)
                    pendingRecipeLog = nil
                    return true
                },
                onCancel: { pendingRecipeLog = nil },
                logDate: logTimestamp(),
                onEdit: { recipeToRepair = recipe; pendingRecipeLog = nil }
            )
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
                    if isOffline {
                        offlinePill
                    }
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

    /// Compact pill shown at the top of the list while the user is
    /// offline. Lets cached results + custom foods still render below
    /// so the food library stays useful on a flight or in a deadzone,
    /// just with the freshness expectation made explicit.
    private var offlinePill: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Showing cached results and your own foods. New search hits will resume when you're back online.")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.warning.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.warning.opacity(0.3), lineWidth: 1)
                }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)

            TextField("Search foods, brands, meals…", text: $query)
                .focused($searchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentPrimary)
                .onSubmit { debouncedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppColor.textSecondary)
                    .accessibilityLabel("Searching")
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    debouncedQuery = ""
                    results = []
                    searchError = nil
                    isOffline = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
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
        .appAnimation(AppAnimation.quick, value: searchFieldFocused)
    }

    private var tabSegments: some View {
        GlassSegmentedControl(
            options: LibraryTab.allCases,
            selected: $tab,
            label: { $0.title }
        )
    }

    @ViewBuilder
    private var listBody: some View {
        switch tab {
        case .all:        allTabBody
        case .favorites:  favoritesTabBody
        case .myFoods:    myFoodsTabBody
        case .recipes:    recipesTabBody
        }
    }

    @ViewBuilder
    private var recipesTabBody: some View {
        if profile.recipes.isEmpty {
            emptyState(
                icon: "list.bullet.rectangle.fill",
                title: "No recipes yet",
                body: "Combine your custom foods into a named recipe — log a multi-ingredient meal in one tap.",
                action: .init(title: "Build a recipe", icon: "plus.circle.fill") {
                    editingRecipe = Recipe(name: "")
                }
            )
        } else {
            sectionHeader("Your recipes (\(profile.recipes.count))")
            ForEach(profile.recipes) { recipe in
                recipeRow(recipe)
            }
            GlassButton(
                title: "Add a recipe",
                icon: "plus.circle",
                style: .secondary,
                isFullWidth: true
            ) {
                editingRecipe = Recipe(name: "")
            }
            .padding(.top, Spacing.xs)
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        let review = RecipeDataLogic.review(
            for: recipe,
            customFoods: profile.customFoods
        )
        let name = recipe.name.isEmpty ? String(localized: "(unnamed)") : recipe.name
        let summary: LocalizedStringKey
        if let totals = review.totals {
            summary = "^[\(recipe.components.count) ingredient](inflect: true) · \(totals.calories) kcal"
        } else {
            summary = "Check ingredients before logging"
        }
        return Button {
            // Tap row → schedule the log (with auto-category).
            // The category picker confirms.
            pendingRecipeLog = recipe
        } label: {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.accentLight.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "list.bullet.rectangle.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(summary)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
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
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .contextMenu {
            Button {
                editingRecipe = recipe
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingRecipeDelete = recipe
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name) + Text(verbatim: ", ") + Text(summary))
        .accessibilityHint("Logs this recipe")
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
            if debouncedQuery.count < Self.minimumSearchQueryLength {
                // `runSearch` doesn't query this short, so "No results"
                // would be a claim nobody checked.
                Text("Keep typing to search Open Food Facts.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isSearching && results.isEmpty {
                searchSkeleton
            } else if let searchError, results.isEmpty {
                inlineMessage(icon: "exclamationmark.triangle", text: searchError)
            } else if results.isEmpty && customMatches.isEmpty && !isSearching {
                if isOffline {
                    // No OFF search available + nothing in custom
                    // foods matched. Be explicit about the offline
                    // gap so the user knows it's a connectivity issue
                    // they can resolve, not a missing-food issue.
                    emptyState(
                        icon: "wifi.slash",
                        title: "Offline — no cached match",
                        body: "We can't reach Open Food Facts right now. Create a custom food or try again when you're back online."
                    )
                } else {
                    emptyState(
                        icon: "questionmark.app.dashed",
                        title: "No results",
                        body: "We couldn't find a match for “\(debouncedQuery)”. Let Atlas AI add it, scan a barcode, or scan a meal photo.",
                        action: .init(title: "Add “\(debouncedQuery)” with AI", icon: "sparkles") {
                            aiFillQuery = debouncedQuery
                            editingCustomFood = .blank
                        }
                    )
                }
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
            // Spotlight deep-link failures land here, before any search.
            if let searchError {
                inlineMessage(icon: "exclamationmark.triangle", text: searchError)
            }

            let recentMeals = LifestyleDataLogic.recentDistinctMeals(in: profile.mealHistory)
            if !recentMeals.isEmpty {
                sectionHeader("Recent meals")
                ForEach(recentMeals) { meal in
                    recentMealRow(meal)
                }
            }

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

            quickActionsCard
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
                    .font(AppFont.caption2)
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
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                Text(title)
                    .font(AppFont.scaled(11, weight: .semibold))
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
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.accentLight)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Search tips")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Brand name + product works best (\"Fage 0%\", \"Chipotle bowl\"). Save your go-tos as favorites for one-tap re-logs.")
                    .font(AppFont.scaled(11))
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
                body: "Create your own foods for meals and ingredients the database doesn't have.",
                action: .init(title: "Create custom food", icon: "plus.circle.fill") {
                    editingCustomFood = .blank
                }
            )
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
                Capsule()
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .frame(height: 12)
                    .frame(maxWidth: 200)
                Capsule()
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
        .shimmer()
    }

    // MARK: - Row variants

    private func productRow(_ product: ScannedProduct) -> some View {
        let isFavorite = dataStore.isFavoriteFood(id: product.barcode)
        return Button {
            select(product)
        } label: {
            HStack(spacing: Spacing.sm) {
                FoodThumbnail(name: product.name, imageURL: product.imageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    if let brand = product.brand, brand != product.name {
                        Text(brand)
                            .font(AppFont.scaled(11))
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
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.rowAccessibilityLabel(name: product.name, brand: product.brand, n: product.per100g))
        .accessibilityHint("Opens the portion picker to log this food. The Quick log action logs your last valid amount, or the default portion if none is saved.")
        .accessibilityAction(named: Text("Quick log")) { performQuickLog(product) }
        .accessibilityAction(named: isFavorite ? Text("Remove from favorites") : Text("Add to favorites")) {
            dataStore.toggleFavoriteFood(id: product.barcode)
        }
    }

    private func customFoodRow(_ food: CustomFood) -> some View {
        let isFavorite = dataStore.isFavoriteFood(id: food.foodID)
        return Button {
            select(food.toScannedProduct())
        } label: {
            HStack(spacing: Spacing.sm) {
                FoodThumbnail(name: food.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text([food.brand ?? "Custom food", food.typicalPrice?.formatted].compactMap { $0 }.joined(separator: " · "))
                        .font(AppFont.scaled(11))
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
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.rowAccessibilityLabel(name: food.name, brand: food.brand ?? String(localized: "Custom food"), n: food.per100g))
        .accessibilityHint("Opens the portion picker to log this food. The Quick log action logs your last valid amount, or the default portion if none is saved.")
        .accessibilityAction(named: Text("Quick log")) { performQuickLog(food.toScannedProduct()) }
        .accessibilityAction(named: isFavorite ? Text("Remove from favorites") : Text("Add to favorites")) {
            dataStore.toggleFavoriteFood(id: food.foodID)
        }
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

    /// One past meal from `mealHistory` — covers photo scans and manual
    /// entries, which have no food-library record to re-open. Tapping
    /// logs it again as it was logged.
    private func recentMealRow(_ meal: MealEntry) -> some View {
        Button {
            relogMeal(meal)
        } label: {
            HStack(spacing: Spacing.sm) {
                FoodThumbnail(name: meal.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(meal.category.displayName)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                    macroPreview(calories: meal.calories, protein: meal.proteinG, carbs: meal.carbsG, fat: meal.fatG)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.clockwise")
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
                    .minimumHitArea()
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
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(meal.name), \(meal.category.displayName), \(meal.calories) kilocalories"))
        .accessibilityHint("Logs this meal again.")
    }

    private func macroPreview(_ n: ScannedProduct.Nutriments) -> some View {
        macroPreview(
            calories: FoodLibraryLogic.wholeNumber(n.calories),
            protein: FoodLibraryLogic.wholeNumber(n.proteinG),
            carbs: FoodLibraryLogic.wholeNumber(n.carbsG),
            fat: FoodLibraryLogic.wholeNumber(n.fatG)
        )
    }

    /// One line, never wrapped: a kcal pill, then protein, carbs and fat
    /// as coloured letters with grams. Narrow rows drop the letters and
    /// keep the colour dots.
    private func macroPreview(calories: Int, protein: Int, carbs: Int, fat: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            macroLine(calories: calories, protein: protein, carbs: carbs, fat: fat, lettered: true)
            macroLine(calories: calories, protein: protein, carbs: carbs, fat: fat, lettered: false)
        }
        .padding(.top, 2)
    }

    private func macroLine(calories: Int, protein: Int, carbs: Int, fat: Int, lettered: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Text("\(calories) kcal")
                .font(AppFont.scaled(11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColor.accentPrimary.opacity(0.18)))
            macroValue("P", grams: protein, tint: AppColor.macroProtein, lettered: lettered)
            macroValue("C", grams: carbs, tint: AppColor.macroCarbs, lettered: lettered)
            macroValue("F", grams: fat, tint: AppColor.macroFat, lettered: lettered)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func macroValue(_ letter: LocalizedStringKey, grams: Int, tint: Color, lettered: Bool) -> some View {
        HStack(spacing: 3) {
            if lettered {
                Text(letter)
                    .font(AppFont.scaled(11, weight: .heavy))
                    .foregroundStyle(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            }
            Text("\(grams)g")
                .font(AppFont.scaled(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    /// One-tap log shortcut on each row. Skips the portion picker and
    /// uses the last valid amount, falling back to the default (1 serving when available,
    /// else a known small package or 100 g), categorized for the logged date.
    /// A successful log moves to the success screen, whose Undo button
    /// reverses it, so a double-tap can't log twice. For everything
    /// else — multiple servings, a different category, manual macro
    /// edit — the row itself opens the full review sheet.
    private func quickLogButton(product: ScannedProduct) -> some View {
        Button {
            performQuickLog(product)
        } label: {
            Image(systemName: "plus")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.onAccent)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(AppColor.accentPrimary)
                }
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .disabled(product.loggable(for: preferredPortion(for: product)) == nil || !FoodLibraryLogic.hasUsableNutrition(product))
        .accessibilityLabel("Quick log \(product.name)")
        .accessibilityHint("Logs your last valid amount, or the default portion if none is saved. Undo is available after saving.")
    }

    /// Builds a MealEntry from the last valid or default portion + the
    /// current time-of-day category and hands it to the DataStore.
    /// Mirrors `confirmLog(for:)`'s persistence and history wiring
    /// without the review-sheet detour — the user gets identical
    /// macro effects without the extra taps.
    private func performQuickLog(_ product: ScannedProduct) {
        let chosen = preferredPortion(for: product)
        guard phase == .browse, FoodLibraryLogic.hasUsableNutrition(product),
              let meal = product.loggable(for: chosen) else { return }
        let now = Date()
        let loggedAt = logTimestamp()
        let loggedCategory = MealCategory.auto(for: loggedAt)
        let source: MealSource = product.barcode.hasPrefix("custom:") ? .custom : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: loggedCategory,
            source: source,
            sourceID: product.barcode,
            date: loggedAt
        )
        guard commitLibraryEntry(entry) else { return }
        BarcodeHaptics.logCommitted()
        let barcode = product.barcode
        if !barcode.hasPrefix("custom:") {
            recordHistory(product, portion: chosen, at: now)
        }
    }

    /// "Log again" from the Recent meals row: duplicates the entry onto
    /// the viewed day at the current clock time, keeping its category.
    private func relogMeal(_ meal: MealEntry) {
        guard phase == .browse else { return }
        guard commitLibraryEntry(LifestyleDataLogic.relogged(meal, at: logTimestamp())) else { return }
        BarcodeHaptics.logCommitted()
    }

    private func favoriteToggle(foodID: String, isFavorite: Bool) -> some View {
        Button {
            dataStore.toggleFavoriteFood(id: foodID)
            Haptics.selection()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(isFavorite ? AppColor.achievement : AppColor.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isFavorite)
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
                .font(AppFont.eyebrow)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.top, Spacing.xs)
    }

    private func emptyState(
        icon: String,
        title: LocalizedStringKey,
        body: LocalizedStringKey,
        action: EmptyStateView.Action? = nil
    ) -> some View {
        EmptyStateView(icon: icon, title: title, message: body, action: action, style: .compact)
            .padding(.vertical, Spacing.sm)
    }

    private func inlineMessage(icon: String, text: String) -> some View {
        let color: Color = AppColor.warning
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
            FoodThumbnail(
                name: product.name,
                imageURL: product.barcode.hasPrefix("custom:") ? nil : product.imageURL,
                size: 56
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let brand = product.brand, brand != product.name {
                    Text(brand)
                        .font(AppFont.caption2)
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
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text(product.barcode.hasPrefix("custom:") ? "Your custom food" : "Open Food Facts")
                .font(AppFont.caption2)
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

                PortionPicker(product: product, portion: $portion)
                Button("Enter exact grams") { editingExactPortion = true }
                    .minimumHitArea()
                if let grams = FoodLibraryLogic.previousGrams(for: product, history: profile.mealHistory) {
                    Text("Last logged amount: \(grams.formatted()) g")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func reviewMacros(_ product: ScannedProduct) -> some View {
        let meal = product.loggable(for: portion)
        let isZeroCalorieOFF = !FoodLibraryLogic.hasUsableNutrition(product)
        return VStack(spacing: Spacing.sm) {
            MealScanTotalsCard(
                calories: meal?.calories ?? 0,
                proteinG: meal?.proteinG ?? 0,
                carbsG: meal?.carbsG ?? 0,
                fatG: meal?.fatG ?? 0
            )
            if isZeroCalorieOFF {
                inlineMessage(
                    icon: "exclamationmark.triangle.fill",
                    text: String(localized: "This product has no calorie data in Open Food Facts. Save it as a custom food with the values from its label.")
                )
                GlassButton(title: "Create custom food", icon: "plus", style: .secondary, isFullWidth: true) {
                    var food = CustomFood.blank
                    food.name = product.name
                    editingCustomFood = food
                }
            }
        }
    }

    private func reviewActions(_ product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.sm) {
            GlassButton(title: "Back", style: .secondary) { backToBrowse() }

            GlassButton(title: addButtonTitle, style: .primary) {
                confirmLog(for: product)
            }
            // Block logging an OFF product without usable nutrition despite
            // the warning above — it would push zeros into today's rings.
            .disabled(product.loggable(for: portion) == nil || !FoodLibraryLogic.hasUsableNutrition(product))
        }
    }

    // MARK: - Logged phase

    @ViewBuilder
    /// Scrolls so Undo stays reachable at accessibility text sizes.
    private var loggedContent: some View {
        ScrollView {
            loggedStack
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var loggedStack: some View {
        VStack(spacing: Spacing.lg) {
            MilestoneArtwork(size: 64)
            Text(addedTitle)
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
            if let snapshot = loggedSnapshot {
                LoggedCaloriePanel(
                    productName: snapshot.foodName,
                    deltaCalories: snapshot.calories,
                    totalCalories: dataStore.consumption(for: snapshot.date).caloriesKcal,
                    targetCalories: (dataStore.profile.nutritionTargets ?? .placeholder).calories,
                    date: snapshot.date
                )
            }
            VStack(spacing: Spacing.sm) {
                GlassButton(title: "Done", style: .primary, isFullWidth: true) { onClose() }
                GlassButton(title: "Log another food", style: .secondary, isFullWidth: true) { backToBrowse() }
                GlassButton(title: "Undo", icon: "arrow.uturn.backward", style: .ghost) {
                    undoLastLog()
                }
            }
            .padding(.top, Spacing.sm)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.xxxxl)
    }

    // MARK: - Actions / helpers

    private var profile: UserProfile { dataStore.profile }

    private var isLoggingToday: Bool { Calendar.current.isDateInToday(logDay) }

    private var addButtonTitle: LocalizedStringKey {
        isLoggingToday ? "Add to today" : "Add to \(MealDaySwitcher.inlineTitle(for: logDay))"
    }

    private var addedTitle: LocalizedStringKey {
        isLoggingToday ? "Added to today" : "Added to \(MealDaySwitcher.inlineTitle(for: logDay))"
    }

    /// Timestamp for a log made now from this sheet — see `logDay`.
    private func logTimestamp() -> Date {
        LifestyleDataLogic.logTimestamp(on: logDay)
    }

    /// Composite identity for the Favorites-tab refresh task. Changes
    /// when either the active tab moves to/from `.favorites` or the
    /// favorites set itself is mutated. Hashing the tab + sorted
    /// favorites snapshot lets a single `.task(id:)` modifier
    /// observe both inputs.
    private var favoritesTaskID: Int {
        var hasher = Hasher()
        hasher.combine(tab)
        // Sort to make the hash order-stable — Sets have no
        // deterministic iteration order.
        hasher.combine(profile.favoriteFoodIDs.sorted())
        return hasher.finalize()
    }

    private func select(_ product: ScannedProduct) {
        selectedProduct = product
        portion = preferredPortion(for: product)
        // Re-evaluate the auto-category against the wall clock each
        // time we open a review — fixes the case where a user opens
        // the library at 10:55 (defaults to breakfast), browses for a
        // few minutes, then logs at 11:05 expecting lunch.
        category = MealCategory.auto(for: logTimestamp())
        phase = .review
        searchFieldFocused = false
    }

    private var navigationTitle: LocalizedStringKey {
        switch phase {
        case .browse: "Food library"
        case .review: "Review"
        case .logged: "Logged"
        }
    }

    private func backToBrowse() {
        selectedProduct = nil
        portion = .grams(100)
        phase = .browse
    }

    private func confirmLog(for product: ScannedProduct) {
        guard phase == .review, let meal = product.loggable(for: portion) else { return }
        let now = Date()
        let source: MealSource = product.barcode.hasPrefix("custom:") ? .custom : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: category,
            source: source,
            sourceID: product.barcode,
            date: logTimestamp()
        )
        guard commitLibraryEntry(entry) else { return }
        BarcodeHaptics.logCommitted()
        loggedSnapshot = LoggedSnapshot(
            foodName: product.name,
            entryID: entry.id,
            calories: meal.calories,
            date: entry.date
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
            // Write-through to the product cache too — OFF results
            // discovered via search-by-name otherwise never land in
            // `BarcodeProductCache` and don't show up in the
            // "Recently logged" row that powers both this view's
            // landing page and BarcodeScanFlow's recents strip.
            recordHistory(product, portion: chosen, at: now)
        }
        phase = .logged
    }

    private func preferredPortion(for product: ScannedProduct) -> ScannedProduct.Portion {
        FoodLibraryLogic.previousGrams(for: product, history: profile.mealHistory).map { .grams($0) }
            ?? product.defaultPortion
    }

    private func showLogged(_ entry: MealEntry) {
        lastLoggedEntry = entry
        loggedHistoryBarcode = nil
        loggedSnapshot = LoggedSnapshot(foodName: entry.name, entryID: entry.id,
                                        calories: entry.calories, date: entry.date)
        phase = .logged
    }

    private func commitLibraryEntry(_ entry: MealEntry) -> Bool {
        do {
            try dataStore.commitScannedMeals([entry])
            showLogged(entry)
            return true
        } catch {
            mealSaveError = String(localized: "Couldn't save the meal. Nothing was added. Please retry.")
            return false
        }
    }

    private func recordHistory(_ product: ScannedProduct, portion: ScannedProduct.Portion, at date: Date) {
        loggedHistoryBarcode = product.barcode
        let previous = historyWriteTask
        historyWriteTask = Task {
            await previous?.value
            await BarcodeScanHistory.shared.recordLog(barcode: product.barcode, portion: portion, at: date)
            await BarcodeProductCache.shared.write(product)
        }
    }

    private func undoLastLog() {
        guard phase == .logged, let entry = lastLoggedEntry else { return }
        do {
            try dataStore.commitScannedMeals([entry], undo: true)
            if let barcode = loggedHistoryBarcode {
                let previous = historyWriteTask
                historyWriteTask = Task {
                    await previous?.value
                    await BarcodeScanHistory.shared.undoLog(barcode: barcode)
                }
            }
            lastLoggedEntry = nil
            loggedSnapshot = nil
            loggedHistoryBarcode = nil
            backToBrowse()
            BarcodeHaptics.logUndone()
        } catch {
            mealSaveError = String(localized: "Couldn't undo. The meal is still saved. Please retry.")
        }
    }

    // MARK: - Search debouncing

    /// Debounce loop. Fired on every `query` change; waits 500 ms before
    /// promoting the value to `debouncedQuery`. The `.task(id: query)`
    /// modifier cancels the previous instance on the next keystroke so
    /// only the pause-after-last-keystroke survives.
    private func runDebouncedSearch() async {
        let snapshot = query
        try? await Task.sleep(for: AppAnimation.searchDebounceDelay)
        guard !Task.isCancelled, snapshot == query else { return }
        debouncedQuery = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fires when `debouncedQuery` actually changes — the network call.
    /// Cleared queries short-circuit so empty searches don't hit OFF.
    /// Only the current search may clear its loading indicator.
    private func runSearch() async {
        let trimmed = debouncedQuery
        defer {
            if !Task.isCancelled, trimmed == debouncedQuery { isSearching = false }
        }
        guard trimmed.count >= Self.minimumSearchQueryLength else {
            isSearching = false
            results = []
            searchError = nil
            isOffline = false
            return
        }

        isSearching = true
        searchError = nil
        do {
            let hits = try await OpenFoodFactsService.shared.search(query: trimmed)
            guard !Task.isCancelled, trimmed == debouncedQuery else { return }
            results = FoodLibraryLogic.ranked(hits, query: trimmed)
            isOffline = false
        } catch let lookupError as OpenFoodFactsService.LookupError {
            guard !Task.isCancelled, trimmed == debouncedQuery else { return }
            results = []
            // Network-down is a distinct UI state, not just an error
            // banner — the list pivots to "showing only what we have
            // cached" until the next successful search restores it.
            isOffline = (lookupError == .networkUnavailable)
            searchError = isOffline ? nil : lookupError.errorDescription
        } catch {
            guard !Task.isCancelled, trimmed == debouncedQuery else { return }
            results = []
            isOffline = false
            AppLog.diagnostics.error("Food search failed: \(error.localizedDescription, privacy: .public)")
            searchError = String(localized: "Couldn't search foods. Try again.")
        }
    }

    private func matchingCustomFoods(for query: String) -> [CustomFood] {
        let needle = FoodLibraryLogic.normalized(query)
        guard !needle.isEmpty else { return [] }
        return profile.customFoods.filter { food in
            FoodLibraryLogic.normalized(food.name).contains(needle)
                || FoodLibraryLogic.normalized(food.brand ?? "").contains(needle)
        }
    }

    /// Top-5 custom foods ranked by the most recent `MealEntry` that
    /// references them. Falls back to `customFoods.prefix(5)` (sorted
    /// by `updatedAt`) only if there's no log history yet, so a
    /// freshly-created food still shows up on the landing page until
    /// the user logs something. Reading mealHistory means "recents"
    /// reflects actual logging behavior, not editor activity.
    private func recentCustomFoods() -> [CustomFood] {
        let customByID: [String: CustomFood] = Dictionary(
            profile.customFoods.map { ($0.foodID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Walk custom logs newest-first by date (back-filled entries break
        // append order) and pluck distinct IDs. Capped at 5 entries early
        // so a long history doesn't slow the landing-page render.
        var seen: Set<String> = []
        var ranked: [CustomFood] = []
        let customLogs = profile.mealHistory.filter { $0.source == .custom }.sorted { $0.date > $1.date }
        for entry in customLogs {
            guard let id = entry.sourceID,
                  !seen.contains(id),
                  let food = customByID[id]
            else { continue }
            seen.insert(id)
            ranked.append(food)
            if ranked.count >= 5 { break }
        }
        if !ranked.isEmpty { return ranked }
        // No log history for any custom food — surface the most
        // recently edited ones so the row isn't empty for users who
        // just created their first custom food.
        return Array(profile.customFoods.prefix(5))
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
            profile.customFoods.map { ($0.foodID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let cachedByID: [String: ScannedProduct] = Dictionary(
            cachedFavoriteProducts.map { ($0.barcode, $0) },
            uniquingKeysWith: { first, _ in first }
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

    /// Resolves a Spotlight deep-link to a `ScannedProduct` and
    /// jumps the sheet to the review phase. Three resolution paths,
    /// in order:
    ///
    ///   1. Custom foods: synchronous lookup on `profile.customFoods`.
    ///   2. OFF cached: read from `BarcodeProductCache` — fast,
    ///      offline-safe.
    ///   3. OFF network: hit the API as a last resort, gated by the
    ///      same rate limiter the search flow uses.
    ///
    /// Failures surface inline on the browse landing rather than
    /// kicking the user into an error screen — the deep-link was
    /// from external state (a Spotlight tile cached when the food
    /// existed); the user can still search for the food manually.
    private func resolveDeepLink(_ link: FoodLogDeepLink) async {
        switch link {
        case .custom(let uuid):
            guard let food = profile.customFoods.first(where: { $0.id == uuid }) else {
                searchError = String(localized: "That food is no longer in your library.")
                return
            }
            select(food.toScannedProduct())

        case .openFoodFacts(let barcode):
            if let cached = await BarcodeProductCache.shared.read(barcode: barcode) {
                select(cached)
                return
            }
            // Cache miss — fetch from OFF. The fetch path writes
            // through to the cache so future deep-links to the same
            // food are instant.
            do {
                let product = try await OpenFoodFactsService.shared.fetch(barcode: barcode)
                guard !Task.isCancelled else { return }
                select(product)
            } catch let lookupError as OpenFoodFactsService.LookupError {
                guard !Task.isCancelled else { return }
                searchError = lookupError.errorDescription
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.diagnostics.error("Food fetch failed: \(error.localizedDescription, privacy: .public)")
                searchError = String(localized: "Couldn't load this food. Try again.")
            }

        case .recipe(let uuid):
            // Recipe deep-link routes to the confirm sheet rather
            // than the per-food review screen — recipes are
            // composed lists, not single products.
            guard let recipe = profile.recipes.first(where: { $0.id == uuid }) else {
                searchError = String(localized: "That recipe is no longer in your library.")
                return
            }
            tab = .recipes
            pendingRecipeLog = recipe
        }
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
            localized: "\(FoodLibraryLogic.wholeNumber(n.calories)) kilocalories",
            comment: "VoiceOver readout of calories per serving."
        )
        let protein = String(
            localized: "\(FoodLibraryLogic.wholeNumber(n.proteinG)) grams protein",
            comment: "VoiceOver readout of protein grams."
        )
        let carbs = String(
            localized: "\(FoodLibraryLogic.wholeNumber(n.carbsG)) grams carbs",
            comment: "VoiceOver readout of carbohydrate grams."
        )
        let fat = String(
            localized: "\(FoodLibraryLogic.wholeNumber(n.fatG)) grams fat",
            comment: "VoiceOver readout of fat grams."
        )
        return "\(header) \(kcal), \(protein), \(carbs), \(fat)."
    }
}

// `Portion.isServings` and `.isGrams` are defined on
// `ScannedProduct.Portion` itself in `Models/ScannedProduct.swift`.

