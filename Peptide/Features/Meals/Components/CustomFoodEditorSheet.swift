import SwiftUI
import PhotosUI

/// Create-or-edit sheet for a `CustomFood`. Opens from the food library
/// when the user can't find what they're looking for (or wants to save
/// a frequently-eaten meal-prep mix for one-tap re-logs).
///
/// Inputs are per-100g so the same portion math the OFF flow uses
/// applies unmodified at log time. A second "Serving" section captures
/// the optional grams-per-serving + serving label so the review sheet
/// can show the "Serving" portion chip on this food.
///
/// "Fill with AI" fills every field from a typed name ("Oatly Barista
/// 1 l") or a photo of the package, so adding a food is a sentence or a
/// snap instead of copying a nutrition panel by hand.
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
    /// When set, the editor starts by filling itself from these words —
    /// the library's "Add … with AI" path.
    var autoFillQuery: String? = nil

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
    @State private var pricePer100g: FoodPriceEstimate?
    @State private var aiQuery = ""
    @State private var aiPhoto: PhotosPickerItem?
    @State private var isFilling = false
    @State private var fillError: String?
    /// A fill held on the device until the user allows sending it to the
    /// AI (Guideline 5.1.2(i)).
    @State private var pendingFill: PendingFill?

    private enum PendingFill {
        case text(String)
        case photo(UIImage)
    }

    @FocusState private var focused: Field?
    enum Field: Hashable {
        case aiQuery, name, brand, calories, protein, carbs, fat, fiber, sugars, servingGrams, servingLabel
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
                aiFillSection

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

                if let typicalPrice = draftFood.typicalPrice {
                    Section {
                        HStack {
                            Text("Typical price")
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Text(typicalPrice.formatted)
                                .foregroundStyle(AppColor.textSecondary)
                                .monospacedDigit()
                        }
                        Button("Remove price", role: .destructive) { pricePer100g = nil }
                    } footer: {
                        Text(priceFootnote)
                    }
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
            .glassFormStyle()
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
        // `.onAppear` fires once per presentation, where `.task` would
        // re-run on every observation cycle and clobber the user's
        // in-progress edits when DataStore publishes a change.
        .onAppear {
            hydrate(from: initial, showZeros: isEditing)
            if let autoFillQuery {
                aiQuery = autoFillQuery
                Task { await fill(fromText: autoFillQuery) }
            }
        }
        .onChange(of: aiPhoto) { _, item in
            guard let item else { return }
            Task { await fill(fromPhoto: item) }
        }
        .sheet(isPresented: Binding(get: { pendingFill != nil && !AIDataConsent.isGranted },
                                    set: { if !$0 { resumePendingFill() } })) {
            AIConsentSheet(whatIsSent: "The food you type, or the photo of its package.")
        }
    }

    private var aiFillSection: some View {
        Section {
            HStack(spacing: Spacing.sm) {
                TextField("e.g. Oatly Barista 1 l, a banana", text: $aiQuery)
                    .focused($focused, equals: .aiQuery)
                    .submitLabel(.go)
                    .onSubmit { Task { await fill(fromText: aiQuery) } }
                if isFilling {
                    ProgressView()
                } else {
                    Button {
                        Task { await fill(fromText: aiQuery) }
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .minimumHitArea()
                    .disabled(aiQuery.nilIfEmpty == nil)
                    .accessibilityLabel("Fill in with AI")
                }
            }
            PhotosPicker(selection: $aiPhoto, matching: .images, photoLibrary: .shared()) {
                Label("Fill from a photo of the package", systemImage: "camera.viewfinder")
            }
            .disabled(isFilling)
            if let fillError {
                Text(fillError)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
            }
        } header: {
            Text("Fill with AI")
        } footer: {
            Text("Type a food or product, or pick a photo of its label. Atlas fills in nutrition, a serving and a typical price — check them before saving.")
        }
    }

    private var priceFootnote: LocalizedStringKey {
        draftFood.servingGrams == nil ? "Estimated per 100 g by Atlas AI." : "Estimated per serving by Atlas AI."
    }

    /// The food as currently typed, for live previews like the price row.
    private var draftFood: CustomFood {
        CustomFood(id: initial.id, name: trimmedName, per100g: initial.per100g,
                   servingGrams: Self.parseDecimal(servingGrams).flatMap { $0 > 0 ? $0 : nil },
                   pricePer100g: pricePer100g)
    }

    private func resumePendingFill() {
        guard let pending = pendingFill else { return }
        pendingFill = nil
        guard AIDataConsent.isGranted else { return }
        Task {
            switch pending {
            case .text(let query): await fill(fromText: query)
            case .photo(let image): await fill(fromImage: image)
            }
        }
    }

    private func fill(fromText text: String) async {
        guard let query = text.nilIfEmpty, !isFilling else { return }
        guard AIDataConsent.isGranted else {
            pendingFill = .text(query)
            return
        }
        startFill()
        do {
            applyFill(try await MealScannerService.shared.describeProduct(.init(query: query),
                                                                      corrections: ScanCorrectionMemory.shared.recent))
        } catch {
            failFill(error)
        }
    }

    private func fill(fromPhoto item: PhotosPickerItem) async {
        defer { aiPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            failFill(MealScannerService.ScanError.invalidResponse)
            return
        }
        guard AIDataConsent.isGranted else {
            pendingFill = .photo(image)
            return
        }
        await fill(fromImage: image)
    }

    private func fill(fromImage image: UIImage) async {
        guard !isFilling else { return }
        startFill()
        do {
            applyFill(try await MealScannerService.shared.smartScan(
                image: image, hint: "A packaged food or its nutrition label, being added to the user's food library.",
                corrections: ScanCorrectionMemory.shared.recent))
        } catch {
            failFill(error)
        }
    }

    private func startFill() {
        isFilling = true
        fillError = nil
        focused = nil
    }

    private func applyFill(_ scan: MealScannerService.SmartScan) {
        isFilling = false
        guard let food = SmartFoodLogic.customFood(from: scan, id: initial.id) else {
            failFill(MealScannerService.ScanError.parseFailure)
            return
        }
        hydrate(from: food, showZeros: true)
        Haptics.success()
    }

    private func failFill(_ error: Error) {
        isFilling = false
        fillError = error.localizedDescription
        Haptics.error()
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
                .accessibilityLabel(Text(title))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: focus)
                .monospacedDigit()
                .frame(width: 90)
            Text(suffix)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 30, alignment: .leading)
        }
    }

    // MARK: - State plumbing

    /// Pull the initial values into local @State on appear. Plain
    /// assignment in `init` would force a full View-init rewrite to
    /// avoid the State-from-init pitfall.
    private func hydrate(from food: CustomFood, showZeros: Bool) {
        name = food.name
        brand = food.brand ?? ""
        // For required macro fields, show "0" rather than "" so a
        // legitimate zero-fat food (e.g. plain whey isolate) reads
        // as "0g fat" instead of empty-with-placeholder. Optional
        // fields (fiber, sugars, servingGrams) still collapse to ""
        // so a "Optional" placeholder hint can guide the user.
        let format = showZeros ? formatRequired : formatOrEmpty
        calories = format(food.per100g.calories)
        protein = format(food.per100g.proteinG)
        carbs = format(food.per100g.carbsG)
        fat = format(food.per100g.fatG)
        fiber = formatOrEmptyOptional(food.per100g.fiberG)
        sugars = formatOrEmptyOptional(food.per100g.sugarsG)
        servingGrams = formatOrEmptyOptional(food.servingGrams)
        servingLabel = food.servingLabel ?? ""
        pricePer100g = food.pricePer100g

        // Auto-focus the name field on a fresh food — the user almost
        // always wants to start typing immediately.
        if !isEditing && trimmedName.isEmpty {
            focused = .name
        }
    }

    /// Like `formatOrEmpty` but renders zero as `"0"` so a legitimate
    /// zero-macro field on an existing food reads as the actual value
    /// instead of a misleading empty placeholder.
    private func formatRequired(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
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
            pricePer100g: pricePer100g,
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

