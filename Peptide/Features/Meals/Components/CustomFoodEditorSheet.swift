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
/// non-empty and calories are filled in. Zero is a real value (black
/// coffee, water), but nothing passes 900 kcal or 100 g of macros per
/// 100 g.
struct CustomFoodEditorSheet: View {
    @Environment(DataStore.self) private var dataStore
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
    @State private var showScanLimitPaywall = false
    @State private var storeService = StoreService.shared
    /// The fields as the editor opened, so only real edits ask before
    /// being discarded.
    @State private var openedFields: [String] = []

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

    private var caloriesValue: Double? { Self.parseDecimal(calories) }
    private var canSave: Bool { !trimmedName.isEmpty && caloriesValue != nil && rangeProblem == nil }

    /// Pure fat is about 900 kcal per 100 g, and 100 g of food can't hold
    /// more than 100 g of protein, carbs and fat.
    private var rangeProblem: LocalizedStringKey? {
        let entered = [calories, protein, carbs, fat, fiber, sugars].compactMap { Self.parseDecimal($0) }
        if entered.contains(where: { $0 < 0 }) {
            return "Values can't be negative."
        }
        if (caloriesValue ?? 0) > 900 {
            return "Calories can't be more than 900 kcal per 100 g."
        }
        let macros = [protein, carbs, fat].compactMap { Self.parseDecimal($0) }.reduce(0, +)
        if macros > 100 {
            return "Protein, carbs and fat can't add up to more than 100 g per 100 g."
        }
        return nil
    }
    private var isEditing: Bool { onDelete != nil }

    private var fields: [String] {
        [name, brand, calories, protein, carbs, fat, fiber, sugars, servingGrams, servingLabel]
    }

    private var hasChanges: Bool { fields != openedFields || pricePer100g != initial.pricePer100g }

    /// Locale-aware decimal parser. `Double("1,5")` returns nil on
    /// devices set to a comma-decimal locale (fr_FR, de_DE, es_ES,
    /// etc.), so the editor would silently log 0 calories for a user
    /// who typed "1,5".
    ///
    /// The decimal pad never types a grouping separator, so a string
    /// holding one is a pasted C-style decimal: in de_DE the formatter
    /// would read "1.5" as 15. Those skip the formatter.
    static func parseDecimal(_ input: String, locale: Locale = .current) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = decimalFormatter(locale)
        if let grouping = formatter.groupingSeparator, !grouping.isEmpty, trimmed.contains(grouping) {
            return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }
        return formatter.number(from: trimmed)?.doubleValue ?? Double(trimmed)
    }

    /// Renders with the same locale `parseDecimal` reads with, so opening
    /// and re-saving a food never changes its values.
    static func formatDecimal(_ value: Double, locale: Locale = .current) -> String {
        decimalFormatter(locale).string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func decimalFormatter(_ locale: Locale) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        return f
    }

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
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Enter the nutrition values per 100 grams of this food. Portion math at log time scales these up or down automatically.")
                        if let rangeProblem {
                            Text(rangeProblem)
                                .foregroundStyle(AppColor.warning)
                        }
                    }
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
                    DiscardChangesCancelButton(hasChanges: hasChanges, onCancel: onCancel)
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
        .interactiveDismissDisabled(hasChanges)
        .onAppear {
            hydrate(from: initial, showZeros: isEditing)
            openedFields = fields
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
        .sheet(isPresented: $showScanLimitPaywall) {
            PaywallView(source: .mealScanLimit)
                .environment(dataStore)
                .liquidGlassPresentation()
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

    /// A photo fill is a paid vision scan, so it spends the same weekly
    /// allowance as a meal photo.
    private func fill(fromPhoto item: PhotosPickerItem) async {
        defer { aiPhoto = nil }
        guard MealScanQuota.remainingThisWeek(isPro: storeService.isProUser) != 0 else {
            showScanLimitPaywall = true
            return
        }
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
            let scan = try await MealScannerService.shared.smartScan(
                image: image, hint: "A packaged food or its nutrition label, being added to the user's food library.",
                corrections: ScanCorrectionMemory.shared.recent, metered: true)
            if !scan.items.isEmpty, !storeService.isProUser { MealScanQuota.recordSuccessfulScan() }
            applyFill(scan)
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
        // The proxy's count outlives a reinstall; agree with it.
        if case .scanAllowanceSpent = error as? MealScannerService.ScanError {
            MealScanQuota.recordAllowanceExhausted()
            showScanLimitPaywall = !storeService.isProUser
        }
        fillError = (error as? LocalizedError)?.errorDescription
            ?? String(localized: "Couldn't fill this food in. Check your connection and try again.")
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
        Self.formatDecimal(value)
    }

    private func commit() {
        let nutrients = ScannedProduct.Nutriments(
            calories: caloriesValue ?? 0,
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
        return Self.formatDecimal(value)
    }

    private func formatOrEmptyOptional(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return formatOrEmpty(value)
    }
}

