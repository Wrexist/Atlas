import SwiftUI

/// Create-or-edit a `Recipe`. Top section is name + optional note;
/// the bulk of the screen is the components list — each row is one
/// custom food + portion override + delete button. A "+ Add
/// ingredient" CTA opens an inline picker over the user's
/// `customFoods`.
///
/// The composite-macros card at the top updates live as components
/// change so the user sees what their composed meal will log as.
/// Components rendered in insertion order (the user's mental
/// model: "I added oats first, then banana") rather than
/// alphabetically.
struct RecipeEditorSheet: View {
    let initial: Recipe
    let availableCustomFoods: [CustomFood]
    let onSave: (Recipe) -> Void
    let onDelete: ((UUID) -> Void)?
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var note: String = ""
    @State private var components: [Recipe.Component] = []
    @State private var pickingFoodForAdd: Bool = false
    @State private var editingComponent: Recipe.Component?
    @State private var showDeleteConfirm: Bool = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !components.isEmpty
    }

    private var isEditing: Bool { onDelete != nil }

    private var hasChanges: Bool {
        name != initial.name || note != (initial.note ?? "") || components != initial.components
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    identityCard
                    macrosPreview
                    componentsSection
                    if isEditing {
                        deleteButton
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle(isEditing ? "Edit recipe" : "New recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardChangesCancelButton(hasChanges: hasChanges, onCancel: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $pickingFoodForAdd) {
                RecipeFoodPickerSheet(
                    foods: availableCustomFoods,
                    onPick: { food in
                        appendComponent(from: food)
                        pickingFoodForAdd = false
                    },
                    onCancel: { pickingFoodForAdd = false }
                )
            }
            .sheet(item: $editingComponent) { component in
                RecipeComponentEditorSheet(
                    initial: component,
                    onSave: { updated in
                        if let idx = components.firstIndex(where: { $0.id == updated.id }) {
                            components[idx] = updated
                        }
                        editingComponent = nil
                    },
                    onDelete: { id in
                        components.removeAll { $0.id == id }
                        editingComponent = nil
                    },
                    onCancel: { editingComponent = nil }
                )
            }
            .confirmationDialog(
                "Delete this recipe?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?(initial.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Past meal logs aren't affected — only the recipe disappears from your library.")
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onAppear { hydrate() }
    }

    private func hydrate() {
        name = initial.name
        note = initial.note ?? ""
        components = initial.components
    }

    private var identityCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("Recipe name (e.g. Morning bowl)", text: $name)
                    .font(AppFont.headline)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(AppColor.textPrimary)
                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var macrosPreview: some View {
        let totals = RecipeDataLogic.totals(
            for: livePreview,
            customFoods: availableCustomFoods
        )
        return GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                let isPartial = RecipeDataLogic.review(for: livePreview, customFoods: availableCustomFoods).totals == nil
                Text(isPartial ? "Partial" : "Logs as")
                    .font(AppFont.eyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight)
                if isPartial {
                    Text("Fix missing foods or portions before logging.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
                HStack(spacing: Spacing.lg) {
                    macroPill(value: "\(totals.calories)", label: "kcal", tint: AppColor.accentLight)
                    macroPill(value: "\(totals.proteinG) g", label: "protein", tint: AppColor.macroProtein)
                    macroPill(value: "\(totals.carbsG) g", label: "carbs", tint: AppColor.macroCarbs)
                    macroPill(value: "\(totals.fatG) g", label: "fat", tint: AppColor.macroFat)
                }
            }
        }
    }

    private func macroPill(value: String, label: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    private var livePreview: Recipe {
        Recipe(id: initial.id, name: trimmedName, note: note.isEmpty ? nil : note, components: components)
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Ingredients (\(components.count))")
                    .font(AppFont.eyebrow)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                Button {
                    pickingFoodForAdd = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(11, weight: .bold))
                        Text("Add")
                            .font(AppFont.scaled(11, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                    }
                    .minimumHitArea()
                }
                .buttonStyle(.plain)
            }

            if components.isEmpty {
                Text("Tap Add to drop in your first ingredient.")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(components) { component in
                        componentRow(component)
                    }
                }
            }
        }
    }

    private func componentRow(_ component: Recipe.Component) -> some View {
        Button {
            editingComponent = component
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "fork.knife")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.cachedName)
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(portionDescription(component.portion))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                components.removeAll { $0.id == component.id }
            } label: {
                Label("Remove ingredient", systemImage: "trash")
            }
        }
    }

    private func portionDescription(_ portion: ScannedProduct.Portion) -> String {
        switch portion {
        case .grams(let g):    return "\(Int(g.rounded())) g"
        case .servings(let s):
            return s == 1 ? String(localized: "1 serving")
                : String(localized: "\(s.formatted(.number.precision(.fractionLength(0...1)))) servings")
        case .wholePackage:    return String(localized: "Whole package")
        }
    }

    private func appendComponent(from food: CustomFood) {
        let portion = food.toScannedProduct().defaultPortion
        components.append(Recipe.Component(
            foodID: food.foodID,
            cachedName: food.name,
            portion: portion
        ))
    }

    private var deleteButton: some View {
        GlassButton(
            title: "Delete recipe",
            icon: "trash",
            style: .destructive,
            isFullWidth: true
        ) {
            showDeleteConfirm = true
        }
    }

    private func commit() {
        Haptics.success()
        let saved = Recipe(
            id: initial.id,
            name: trimmedName,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            components: components,
            updatedAt: Date()
        )
        onSave(saved)
    }
}

/// Inner sheet — picks a custom food to add to a recipe. Uses the
/// same custom-food list the food library exposes; OFF favorites
/// intentionally excluded so a recipe stays composed of foods the
/// user explicitly defined (predictable macros that don't shift if
/// the OFF cache evicts an entry).
struct RecipeFoodPickerSheet: View {
    let foods: [CustomFood]
    let onPick: (CustomFood) -> Void
    let onCancel: () -> Void

    @Environment(DataStore.self) private var dataStore
    @State private var creatingFood: CustomFood?

    var body: some View {
        NavigationStack {
            Group {
                if foods.isEmpty {
                    EmptyStateView(
                        icon: "person.crop.rectangle.stack",
                        title: "No custom foods yet",
                        message: "Recipes are built from your custom foods. Create one and it's added here.",
                        action: .init(title: "Create custom food", icon: "plus") { creatingFood = .blank }
                    )
                } else {
                    List(foods) { food in
                        Button {
                            onPick(food)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text("\(Int(food.per100g.calories.rounded())) kcal / 100 g")
                                        .font(AppFont.caption2)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(AppColor.accentLight)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .sheet(item: $creatingFood) { food in
                CustomFoodEditorSheet(
                    initial: food,
                    onSave: { saved in
                        dataStore.saveCustomFood(saved)
                        creatingFood = nil
                        onPick(saved)
                    },
                    onCancel: { creatingFood = nil },
                    onDelete: nil
                )
            }
        }
    }
}

/// Quick-edit sheet for a single recipe component — change the
/// portion override or remove it from the recipe entirely.
struct RecipeComponentEditorSheet: View {
    let initial: Recipe.Component
    let onSave: (Recipe.Component) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    @State private var portion: ScannedProduct.Portion = .grams(100)
    @FocusState private var gramsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(initial.cachedName) {
                    portionSection
                }
                Section {
                    Button(role: .destructive) {
                        onDelete(initial.id)
                    } label: {
                        Label("Remove from recipe", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = initial
                        updated.portion = portion
                        onSave(updated)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { gramsFocused = false }
                }
            }
        }
        .onAppear { portion = initial.portion }
    }

    @ViewBuilder
    private var portionSection: some View {
        switch portion {
        case .grams(let g):
            HStack {
                Text("Grams")
                Spacer()
                // Type an exact weight; the stepper is for nudging it.
                Stepper(value: Binding(
                    get: { g },
                    set: { portion = .grams($0) }
                ), in: 5...2000, step: 5) {
                    HStack(spacing: Spacing.xxs) {
                        TextField("Grams", value: Binding(
                            get: { g },
                            set: { portion = .grams(min(2000, max(5, $0))) }
                        ), format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($gramsFocused)
                        .accessibilityLabel("Grams")
                        Text("g")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        case .servings(let s):
            HStack {
                Text("Servings")
                Spacer()
                Stepper(value: Binding(
                    get: { s },
                    set: { portion = .servings($0) }
                ), in: 0.5...10, step: 0.5) {
                    Text(s.formatted(.number.precision(.fractionLength(0...1))))
                        .monospacedDigit()
                }
            }
        case .wholePackage:
            Text("Whole package")
        }
    }
}
