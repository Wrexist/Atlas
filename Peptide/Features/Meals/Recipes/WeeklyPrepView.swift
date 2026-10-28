import SwiftUI

/// "Weekly prep": this week's two meal-prep dishes, one shopping list for
/// both, the prep-day checklist in cooking order, and the boxes waiting in
/// the fridge and freezer with the day each should be eaten by.
struct WeeklyPrepView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.locale) private var locale
    @State private var prep = WeeklyPrepStore.shared
    @State private var pantry = PantryStore.shared
    @State private var picker: DishPickerTarget?
    @State private var loggedSlot: MealCategory?

    private var calendar: Calendar { .current }

    var body: some View {
        let now = Date()
        let plan = prep.plan(now: now, calendar: calendar)
        let boxes = prep.visibleBoxes(now: now, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header(plan: plan, now: now)
                if plan.dishes.isEmpty {
                    emptyState
                } else {
                    dishCards(plan: plan)
                    if let preppedAt = plan.preppedAt {
                        preppedNote(preppedAt)
                    } else {
                        PrepShoppingCard(
                            items: WeeklyPrepEngine.shoppingList(for: plan.dishes, recipes: prep.recipes, pantry: pantry.keys),
                            bought: plan.bought,
                            toggleBought: toggleBought,
                            toggleAtHome: toggleAtHome
                        )
                        .scrollReveal()
                        PrepDayCard(
                            tasks: WeeklyPrepEngine.prepTasks(for: plan.dishes, recipes: prep.recipes),
                            recipes: prep.recipes,
                            done: plan.doneTasks,
                            showsDish: plan.dishes.count > 1,
                            toggle: toggleTask,
                            finish: finishPrep
                        )
                        .scrollReveal()
                    }
                }
                if !boxes.isEmpty {
                    PrepBoxesCard(
                        boxes: boxes,
                        recipes: prep.recipes,
                        now: now,
                        eat: eat,
                        freeze: freeze,
                        discard: discard
                    )
                    .scrollReveal()
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxxl)
            .readableContentWidth()
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Weekly prep")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottom) { loggedToast }
        .sheet(item: $picker) { target in
            PrepDishPicker(
                recipes: prep.ranked(context: context(now: Date())),
                planned: Set(plan.recipeIDs),
                choose: { choose($0, for: target) }
            )
            .liquidGlassPresentation()
        }
    }

    // MARK: - Header

    private func header(plan: PrepWeek, now: Date) -> some View {
        HomeSectionHeader(
            eyebrow: "Week \(WeeklyPrepEngine.weekNumber(for: now, calendar: calendar))",
            title: "This week's boxes"
        ) {
            if !plan.dishes.isEmpty && plan.preppedAt == nil {
                Button(action: suggest) {
                    Label("Suggest again", systemImage: "wand.and.stars")
                        .font(AppFont.chipText)
                        .foregroundStyle(AppColor.accentLight)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .glassControl(.capsule)
                        .minimumHitArea()
                }
                .buttonStyle(ScalePressStyle(pressedScale: 0.95))
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "shippingbox",
            title: "Plan this week's prep",
            message: "Two dishes, a few boxes each, cooked in one go.",
            action: .init(title: "Suggest a week", icon: "wand.and.stars", perform: suggest),
            secondary: .init(title: "Choose dishes myself", icon: "list.bullet") {
                picker = DishPickerTarget(replacing: nil)
            }
        )
        .transition(.opacity)
    }

    private func dishCards(plan: PrepWeek) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(plan.dishes) { dish in
                if let recipe = prep.recipes[dish.recipeID] {
                    PrepDishCard(
                        recipe: recipe,
                        servings: dish.servings,
                        isLocked: plan.preppedAt != nil,
                        setServings: { setServings($0, for: dish.recipeID) },
                        swap: { picker = DishPickerTarget(replacing: dish.recipeID) }
                    )
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            if plan.dishes.count < WeeklyPrepEngine.dishesPerWeek && plan.preppedAt == nil {
                addDishCard
            }
        }
        .scrollReveal()
    }

    private var addDishCard: some View {
        Button {
            picker = DishPickerTarget(replacing: nil)
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "plus")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .accessibilityHidden(true)
                Text("Add a dish")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
    }

    private func preppedNote(_ preppedAt: Date) -> some View {
        Label {
            Text("Prepped \(preppedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))). Enjoy the week.")
        } icon: {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppColor.positive)
        }
        .font(AppFont.subheadline)
        .foregroundStyle(AppColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    @ViewBuilder
    private var loggedToast: some View {
        if let loggedSlot {
            Label("Logged to \(loggedSlot.displayName)", systemImage: "checkmark.circle.fill")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.positive)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassSurfaceCapsule()
                .padding(.bottom, Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func context(now: Date) -> RecipeLibraryEngine.Context {
        let profile = dataStore.profile
        return RecipeLibraryEngine.Context(
            favoriteFoodNames: RecipeLibraryEngine.favoriteFoodNames(
                favoriteIDs: profile.favoriteFoodIDs,
                customFoods: profile.customFoods,
                mealHistory: profile.mealHistory
            ),
            needs: nil,
            now: now,
            calendar: calendar,
            recentMealNames: RecipeLibraryEngine.recentMealNames(in: profile.mealHistory, now: now, calendar: calendar),
            pantry: pantry.keys
        )
    }

    private func suggest() {
        AppAnimation.with(AppAnimation.springSmooth) {
            prep.suggestWeek(context: context(now: Date()))
        }
        Haptics.impact(.medium)
    }

    private func choose(_ recipe: LibraryRecipe, for target: DishPickerTarget) {
        picker = nil
        AppAnimation.with(AppAnimation.springSmooth) {
            prep.replace(target.replacing, with: recipe, calendar: calendar)
        }
        Haptics.selection()
    }

    private func setServings(_ servings: Int, for recipeID: String) {
        AppAnimation.with(AppAnimation.springSnappy) {
            prep.setServings(servings, for: recipeID, calendar: calendar)
        }
        Haptics.selection()
    }

    private func toggleBought(_ item: WeeklyPrepEngine.ShoppingItem) {
        AppAnimation.with(AppAnimation.springSnappy) {
            prep.toggleBought(item.pantryKey, calendar: calendar)
        }
        Haptics.impact(.light)
    }

    private func toggleAtHome(_ item: WeeklyPrepEngine.ShoppingItem) {
        AppAnimation.with(AppAnimation.springSnappy) {
            pantry.toggle(item.pantryKey)
        }
        Haptics.impact(.light)
    }

    private func toggleTask(_ task: WeeklyPrepEngine.PrepTask) {
        AppAnimation.with(AppAnimation.springSnappy) {
            prep.toggleTask(task.id, calendar: calendar)
        }
        Haptics.impact(.light)
    }

    private func finishPrep() {
        AppAnimation.with(AppAnimation.springSmooth) {
            prep.finishPrep(calendar: calendar)
        }
        Haptics.success()
    }

    /// Logs one serving to today's diary and takes the box out of the fridge.
    private func eat(_ batch: PrepBoxBatch) {
        guard let recipe = prep.recipes[batch.recipeID] else { return }
        let entry = RecipeLibraryEngine.entry(for: recipe, locale: locale, at: Date(), calendar: calendar)
        dataStore.logMealEntry(entry)
        AppAnimation.with(AppAnimation.springSnappy) { prep.removeOne(batch.id) }
        Haptics.success()
        AppAnimation.with(AppAnimation.toast) { loggedSlot = entry.category }
        Task {
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            AppAnimation.with(AppAnimation.toast) { loggedSlot = nil }
        }
    }

    private func freeze(_ batch: PrepBoxBatch) {
        AppAnimation.with(AppAnimation.springSnappy) { prep.freezeOne(batch.id) }
        Haptics.impact(.light)
    }

    private func discard(_ batch: PrepBoxBatch) {
        AppAnimation.with(AppAnimation.springSnappy) { prep.removeOne(batch.id) }
        Haptics.impact(.light)
    }
}

/// Which dish the picker sheet replaces; nil adds one.
struct DishPickerTarget: Identifiable {
    let replacing: String?
    var id: String { replacing ?? "add" }
}

#Preview {
    NavigationStack {
        WeeklyPrepView()
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
