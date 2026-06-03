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
    @State private var editingRecipe: Recipe?
    @State private var pendingRecipeDelete: Recipe?
    /// Recipe waiting on a category-pick before logging. Drives a
    /// quick MealCategoryPicker confirm step that defaults to the
    /// time-of-day auto-category but lets the user re-route.
    @State private var pendingRecipeLog: Recipe?
    /// Cached `ScannedProduct`s pulled from `BarcodeProductCache` for
    /// every favorited OFF barcode. Populated when the user lands on
    /// the Favorites tab so the list paints without a search round-
    /// trip. Refreshed on tab change so a re-favorited item from the
    /// All tab shows up immediately.
    @State private var cachedFavoriteProducts: [ScannedProduct] = []
    /// Food IDs that just got quick-logged from a row's "+" button,
    /// keyed to the exact category the entry was logged under. The
    /// "Logged as Breakfast" overlay reads this map so a tap landing
    /// on a meal-boundary (10:59:59 → 11:00:00) shows the category
    /// the entry actually got rather than re-running `auto(for:)` at
    /// render time and surfacing a different bucket. Cleared on the
    /// row's 1.5-second timeout or on sheet dismiss.
    @State private var recentlyQuickLogged: [String: MealCategory] = [:]
    /// Outstanding "Logged ✓" timeout Tasks, keyed by food ID. One
    /// task per food at a time — a second quick-log of the same
    /// food inside the window cancels the in-flight clear and
    /// reschedules, so the badge timing always reflects the latest
    /// log. Cancelled in bulk on sheet dismiss.
    @State private var quickLogClearTasks: [String: Task<Void, Never>] = [:]
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
        case logged        // success screen with Undo + auto-close
    }

    // MARK: - Portion picker tuning

    /// Min/max grams the slider exposes. 10 g lower bound rules out
    /// noise (the user probably means to log nothing rather than
    /// half a gram of garlic powder); 2,000 g upper bound covers a
    /// realistic single-sitting maximum without giving the slider
    /// useless resolution at the top end.
    static let gramsSliderRange: ClosedRange<Double> = 10...2000

    /// 5 g granularity matches what people actually measure with —
    /// kitchen scales typically display 1 g resolution but most
    /// foods are accurate to ~5 g anyway given a label tolerance of
    /// ±10–20%.
    static let gramsSliderStep: Double = 5

    /// One-tap shortcut weights. Picked to cover the four common
    /// portion shapes: a snack (50 g), a single ingredient or
    /// reference panel (100 g), a typical bowl/plate (200 g), and
    /// a "whole serving for two" (500 g).
    static let gramsQuickPicks: [Double] = [50, 100, 200, 500]

    /// Minimum number of characters before the search bar fires a
    /// network request. Matches `OpenFoodFactsService.search`'s own
    /// guard so the two layers can't drift.
    static let minimumSearchQueryLength: Int = 2

    enum LibraryTab: String, CaseIterable, Identifiable {
        case all = "All"
        case favorites = "Favorites"
        case myFoods = "My Foods"
        case recipes = "Recipes"
        var id: String { rawValue }

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
        .onDisappear {
            // Cancel outstanding "Logged ✓" timeouts so they can't
            // fire into a re-presented sheet and surface stale
            // confirmation badges.
            for task in quickLogClearTasks.values { task.cancel() }
            quickLogClearTasks.removeAll()
            recentlyQuickLogged.removeAll()
        }
        .task(id: query) { await runDebouncedSearch() }
        .task(id: debouncedQuery) { await runSearch() }
        .task(id: phase) {
            guard phase == .logged else { return }
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            // Re-check phase after the sleep — a user tap on Undo or
            // Done that lands in the final window before the timer
            // fires would otherwise let both paths call `onClose()`,
            // which is a no-op today but a foot-gun the moment
            // `onClose` does anything non-idempotent.
            guard !Task.isCancelled, phase == .logged else { return }
            onClose()
        }
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
        .sheet(item: $pendingRecipeLog) { recipe in
            RecipeLogConfirmSheet(
                recipe: recipe,
                customFoods: profile.customFoods,
                onLog: { category in
                    dataStore.logRecipe(recipe, category: category, at: Date())
                    pendingRecipeLog = nil
                    onClose()
                },
                onCancel: { pendingRecipeLog = nil }
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're offline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Showing cached results and your own foods. New search hits will resume when you're back online.")
                    .font(.system(size: 11))
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
        // Horizontal scroller keeps each chip on a single line at its
        // natural width, so "Favorites" / "My Foods" never wrap to two
        // lines on narrower phones. On wide devices the four chips fit
        // without scrolling; on an SE they scroll instead of squashing.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(LibraryTab.allCases) { entry in
                    segmentChip(entry)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(active ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.horizontal, Spacing.md)
            .frame(height: 36)
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
            .contentShape(Capsule())
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
        case .recipes:    recipesTabBody
        }
    }

    @ViewBuilder
    private var recipesTabBody: some View {
        if profile.recipes.isEmpty {
            emptyState(
                icon: "list.bullet.rectangle.fill",
                title: "No recipes yet",
                body: "Combine your custom foods into a named recipe — log a multi-ingredient meal in one tap."
            )
            Button {
                editingRecipe = Recipe(name: "")
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("Build a recipe")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .padding(.top, Spacing.sm)
        } else {
            sectionHeader("Your recipes (\(profile.recipes.count))")
            ForEach(profile.recipes) { recipe in
                recipeRow(recipe)
            }
            Button {
                editingRecipe = Recipe(name: "")
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus.circle")
                    Text("Add a recipe")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(AppColor.accentLight)
            .padding(.top, Spacing.xs)
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        let totals = RecipeDataLogic.totals(
            for: recipe,
            customFoods: profile.customFoods
        )
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name.isEmpty ? "(unnamed)" : recipe.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text("\(recipe.components.count) item\(recipe.components.count == 1 ? "" : "s") · \(totals.calories) kcal")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
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
        .accessibilityLabel("\(recipe.name), \(recipe.components.count) ingredients, \(totals.calories) calories. Tap to log.")
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
                        body: "We couldn't find a match for \"\(debouncedQuery)\". Create a custom food, scan a barcode, or snap a photo."
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
        .shimmer()
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
        let inFlight = recentlyQuickLogged[product.barcode] != nil
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
    ///
    /// `allowsHitTesting(true)` on the wash blocks the underlying
    /// row's tap-to-review gesture during the confirmation window —
    /// otherwise a quick-logger could tap the row by accident
    /// immediately after the "+" and find themselves inside the
    /// portion picker for the same food they just logged.
    ///
    /// Category text is read from `recentlyQuickLogged` (set at
    /// log-commit time), NOT re-computed via `auto(for: Date())` at
    /// render time. The two `Date()` values could otherwise diverge
    /// at a meal-boundary tap — surfacing "Logged as Breakfast"
    /// while the entry actually landed in lunch.
    @ViewBuilder
    private func quickLoggedOverlay(foodID: String) -> some View {
        if let category = recentlyQuickLogged[foodID] {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.accentPrimary.opacity(0.18))
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accentLight)
                    Text("Logged as \(category.displayName)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(AppColor.surfaceSecondary.opacity(0.9))
                }
            }
            .allowsHitTesting(true)
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
        guard recentlyQuickLogged[product.barcode] == nil,
              let meal = product.loggable(for: product.defaultPortion) else { return }
        let now = Date()
        // Auto-category captured once at log time and reused for
        // both the persisted entry and the overlay readout — see
        // `quickLoggedOverlay` for the meal-boundary bug this
        // prevents.
        let loggedCategory = MealCategory.auto(for: now)
        let source: MealSource = product.barcode.hasPrefix("custom:") ? .custom : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: loggedCategory,
            source: source,
            sourceID: product.barcode,
            date: now
        )
        dataStore.logMealEntry(entry)
        BarcodeHaptics.logCommitted()
        let barcode = product.barcode
        let chosen = product.defaultPortion
        if !barcode.hasPrefix("custom:") {
            let productSnapshot = product
            Task {
                await BarcodeScanHistory.shared.recordLog(barcode: barcode, portion: chosen, at: now)
                await BarcodeProductCache.shared.write(productSnapshot)
            }
        }
        withAnimation(.easeOut(duration: 0.18)) {
            recentlyQuickLogged[product.barcode] = loggedCategory
        }
        // Clear the badge after the confirmation window so the row
        // returns to its tap-to-log idle state. Keying tasks by
        // food ID means each food has at most one in-flight clear
        // (memory bounded by distinct logged foods, not log count)
        // and a rapid second log of the same food cancels the old
        // timer before scheduling the new one — so the badge
        // duration always reflects the most recent log.
        let foodID = product.barcode
        quickLogClearTasks[foodID]?.cancel()
        let task = Task { @MainActor in
            try? await Task.sleep(for: AppAnimation.quickLogConfirmationDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                recentlyQuickLogged.removeValue(forKey: foodID)
            }
            quickLogClearTasks.removeValue(forKey: foodID)
        }
        quickLogClearTasks[foodID] = task
    }

    private func favoriteToggle(foodID: String, isFavorite: Bool) -> some View {
        Button {
            dataStore.toggleFavoriteFood(id: foodID)
            BarcodeHaptics.lookupSuccess()
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
                        portionChip(title: "Serving", isActive: portion.isServings) {
                            portion = .servings(1)
                        }
                    }
                    if product.packageGrams != nil {
                        portionChip(title: "Whole pack", isActive: portion == .wholePackage) {
                            portion = .wholePackage
                        }
                    }
                    portionChip(title: "Grams", isActive: portion.isGrams) {
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
                    in: Self.gramsSliderRange,
                    step: Self.gramsSliderStep
                )
                .tint(AppColor.accentPrimary)
                HStack(spacing: Spacing.xs) {
                    ForEach(Self.gramsQuickPicks, id: \.self) { quick in
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
                    text: "This product has no calorie data in Open Food Facts. Snap the nutrition label or save it as a custom food."
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
        portion = product.defaultPortion
        // Re-evaluate the auto-category against the wall clock each
        // time we open a review — fixes the case where a user opens
        // the library at 10:55 (defaults to breakfast), browses for a
        // few minutes, then logs at 11:05 expecting lunch.
        category = MealCategory.auto(for: Date())
        phase = .review
        searchFieldFocused = false
        BarcodeHaptics.lookupSuccess()
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
        BarcodeHaptics.logCommitted()
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
            // Write-through to the product cache too — OFF results
            // discovered via search-by-name otherwise never land in
            // `BarcodeProductCache` and don't show up in the
            // "Recently logged" row that powers both this view's
            // landing page and BarcodeScanFlow's recents strip.
            let productSnapshot = product
            Task {
                await BarcodeScanHistory.shared.recordLog(barcode: barcode, portion: chosen, at: now)
                await BarcodeProductCache.shared.write(productSnapshot)
            }
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
        BarcodeHaptics.logUndone()
        onClose()
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
    /// `defer` reliably clears the spinner even when the task is
    /// cancelled mid-await — without it, fast typists would see the
    /// skeleton loader hang until the next non-cancelled search.
    private func runSearch() async {
        defer { isSearching = false }

        let trimmed = debouncedQuery
        guard trimmed.count >= Self.minimumSearchQueryLength else {
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

    /// Top-5 custom foods ranked by the most recent `MealEntry` that
    /// references them. Falls back to `customFoods.prefix(5)` (sorted
    /// by `updatedAt`) only if there's no log history yet, so a
    /// freshly-created food still shows up on the landing page until
    /// the user logs something. Reading mealHistory means "recents"
    /// reflects actual logging behavior, not editor activity.
    private func recentCustomFoods() -> [CustomFood] {
        let customByID: [String: CustomFood] = Dictionary(
            uniqueKeysWithValues: profile.customFoods.map { ($0.foodID, $0) }
        )
        // Walk mealHistory newest-first and pluck distinct custom IDs.
        // Capped at 5 entries early so a long history doesn't slow
        // the landing-page render.
        var seen: Set<String> = []
        var ranked: [CustomFood] = []
        for entry in profile.mealHistory.reversed() where entry.source == .custom {
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
                searchError = error.localizedDescription
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

// `Portion.isServings` and `.isGrams` are defined on
// `ScannedProduct.Portion` itself in `Models/ScannedProduct.swift`.

