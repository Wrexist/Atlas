import SwiftUI

/// Create-or-edit sheet for a `CustomFood`. Opens from the food library
/// when the user can't find what they're looking for (or wants to save
/// a frequently-eaten meal-prep mix for one-tap re-logs).
///
/// Inputs are per-100g so the same portion math the OFF flow uses
/// applies unmodified at log time. A second "Serving" section captures
/// the optional grams-per-serving + serving label so the review sheet
/// can show the "Serving" portion chip on this food.
///
/// Validates inline: the Save button stays disabled until the name is
/// non-empty and the calorie value is greater than zero. Everything
/// else can stay zero.
struct CustomFoodEditorSheet: View {
    let initial: CustomFood
    let onSave: (CustomFood) -> Void
    let onCancel: () -> Void
    /// Present-only when editing an existing food. Nil for the create
    /// flow — the trash button is suppressed in that case.
    let onDelete: ((UUID) -> Void)?

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var fiber: String = ""
    @State private var sugars: String = ""
    @State private var servingGrams: String = ""
    @State private var servingLabel: String = ""
    @State private var showDeleteConfirm = false

    @FocusState private var focused: Field?
    enum Field: Hashable {
        case name, brand, calories, protein, carbs, fat, fiber, sugars, servingGrams, servingLabel
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var caloriesValue: Double { Self.parseDecimal(calories) ?? 0 }
    private var canSave: Bool { !trimmedName.isEmpty && caloriesValue > 0 }
    private var isEditing: Bool { onDelete != nil }

    /// Locale-aware decimal parser. `Double("1,5")` returns nil on
    /// devices set to a comma-decimal locale (fr_FR, de_DE, es_ES,
    /// etc.), so the editor would silently log 0 calories for a user
    /// who typed "1,5". Try the locale formatter first, fall back to
    /// the C parse so a pasted "1.5" still works regardless of locale.
    private static func parseDecimal(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let n = decimalFormatter.number(from: trimmed) {
            return n.doubleValue
        }
        return Double(trimmed)
    }

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name (e.g. Mum's lasagna)", text: $name)
                        .focused($focused, equals: .name)
                        .textInputAutocapitalization(.words)
                    TextField("Brand or source (optional)", text: $brand)
                        .focused($focused, equals: .brand)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    macroField(title: "Calories", text: $calories, suffix: "kcal", focus: .calories)
                    macroField(title: "Protein",  text: $protein,  suffix: "g",    focus: .protein)
                    macroField(title: "Carbs",    text: $carbs,    suffix: "g",    focus: .carbs)
                    macroField(title: "Fat",      text: $fat,      suffix: "g",    focus: .fat)
                    macroField(title: "Fiber",    text: $fiber,    suffix: "g",    focus: .fiber, optional: true)
                    macroField(title: "Sugars",   text: $sugars,   suffix: "g",    focus: .sugars, optional: true)
                } header: {
                    Text("Per 100 g")
                } footer: {
                    Text("Enter the nutrition values per 100 grams of this food. Portion math at log time scales these up or down automatically.")
                }

                Section {
                    macroField(title: "Serving size", text: $servingGrams, suffix: "g", focus: .servingGrams, optional: true)
                    TextField("Label (e.g. \"1 cup\", \"1 slice\")", text: $servingLabel)
                        .focused($focused, equals: .servingLabel)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Default serving (optional)")
                } footer: {
                    Text("Adds a one-tap \"1 serving\" portion to the review sheet — handy if this food has a natural serving size.")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "trash")
                                Text("Delete custom food")
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit food" : "New food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .confirmationDialog(
                "Delete this food?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete?(initial.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This won't remove past logs — only the food itself disappears from your library.")
            }
        }
        .preferredColorScheme(.dark)
        // `.onAppear` fires once per presentation, where `.task` would
        // re-run on every observation cycle and clobber the user's
        // in-progress edits when DataStore publishes a change.
        .onAppear { hydrate() }
    }

    private func macroField(
        title: LocalizedStringKey,
        text: Binding<String>,
        suffix: String,
        focus: Field,
        optional: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            TextField(optional ? "Optional" : "0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: focus)
                .monospacedDigit()
                .frame(width: 90)
            Text(suffix)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 30, alignment: .leading)
        }
    }

    // MARK: - State plumbing

    /// Pull the initial values into local @State on appear. Plain
    /// assignment in `init` would force a full View-init rewrite to
    /// avoid the State-from-init pitfall.
    private func hydrate() {
        name = initial.name
        brand = initial.brand ?? ""
        calories = formatOrEmpty(initial.per100g.calories)
        protein = formatOrEmpty(initial.per100g.proteinG)
        carbs = formatOrEmpty(initial.per100g.carbsG)
        fat = formatOrEmpty(initial.per100g.fatG)
        fiber = formatOrEmptyOptional(initial.per100g.fiberG)
        sugars = formatOrEmptyOptional(initial.per100g.sugarsG)
        servingGrams = formatOrEmptyOptional(initial.servingGrams)
        servingLabel = initial.servingLabel ?? ""

        // Auto-focus the name field on a fresh food — the user almost
        // always wants to start typing immediately.
        if !isEditing && trimmedName.isEmpty {
            focused = .name
        }
    }

    private func commit() {
        let nutrients = ScannedProduct.Nutriments(
            calories: caloriesValue,
            proteinG: Self.parseDecimal(protein) ?? 0,
            carbsG: Self.parseDecimal(carbs) ?? 0,
            fatG: Self.parseDecimal(fat) ?? 0,
            fiberG: Self.parseDecimal(fiber),
            sugarsG: Self.parseDecimal(sugars)
        )
        let saved = CustomFood(
            id: initial.id,
            name: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            per100g: nutrients,
            servingGrams: Self.parseDecimal(servingGrams).flatMap { $0 > 0 ? $0 : nil },
            servingLabel: servingLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            updatedAt: Date()
        )
        onSave(saved)
    }

    private func formatOrEmpty(_ value: Double) -> String {
        guard value > 0 else { return "" }
        // Trim trailing .0 for whole numbers so the field doesn't read
        // "200.0" when the user entered "200".
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }

    private func formatOrEmptyOptional(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return formatOrEmpty(value)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
