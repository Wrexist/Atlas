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
                    Button("Cancel", action: onCancel)
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
        .preferredColorScheme(.dark)
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
                Text("Logs as")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                HStack(spacing: Spacing.lg) {
                    macroPill(value: "\(totals.calories)", label: "kcal", tint: AppColor.accentLight)
                    macroPill(value: "\(totals.proteinG)g", label: "protein", tint: .green)
                    macroPill(value: "\(totals.carbsG)g", label: "carbs", tint: .blue)
                    macroPill(value: "\(totals.fatG)g", label: "fat", tint: .orange)
                }
            }
        }
    }

    private func macroPill(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                Button {
                    pickingFoodForAdd = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                    }
                }
                .buttonStyle(.plain)
            }

            if components.isEmpty {
                Text("Tap Add to drop in your first ingredient.")
                    .font(.system(size: 12))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.cachedName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(portionDescription(component.portion))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
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
        case .grams(let g):    return "\(Int(g.rounded()))g"
        case .servings(let s): return s == 1 ? "1 serving" : String(format: "%.1f servings", s)
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
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "trash")
                Text("Delete recipe")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.bordered)
        .tint(AppColor.destructive)
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

    var body: some View {
        NavigationStack {
            Group {
                if foods.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(AppColor.accentLight)
                        Text("No custom foods yet")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Create custom foods first — recipes are built from them.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.top, Spacing.xxxl)
                } else {
                    List(foods) { food in
                        Button {
                            onPick(food)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text("\(Int(food.per100g.calories.rounded())) kcal / 100g")
                                        .font(AppFont.caption)
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
        }
        .preferredColorScheme(.dark)
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
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { portion = initial.portion }
    }

    @ViewBuilder
    private var portionSection: some View {
        switch portion {
        case .grams(let g):
            HStack {
                Text("Grams")
                Spacer()
                Stepper(value: Binding(
                    get: { g },
                    set: { portion = .grams($0) }
                ), in: 5...2000, step: 5) {
                    Text("\(Int(g.rounded()))g")
                        .monospacedDigit()
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
                    Text(String(format: "%.1f", s))
                        .monospacedDigit()
                }
            }
        case .wholePackage:
            Text("Whole package")
        }
    }
}
