import SwiftUI

/// Lightweight macro-override sheet for the barcode review card. Lets
/// the user correct Open Food Facts data (or the portion math) before
/// logging — common when OFF has stale numbers for a specific product
/// or when the user knows they ate slightly more or less than the
/// portion picker can express.
///
/// Only the four loggable macros are editable. Name and portion stay
/// on the review card so the override stays a focused correction,
/// not a free-form meal builder.
struct EditNutritionSheet: View {
    // Number fields and unit labels hold scaling text, so their widths
    // scale with Dynamic Type instead of clipping "kcal" or "2500".
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .caption2) private var unitWidth: CGFloat = 32
    let productName: String
    let initial: LoggableMeal?
    let onSave: (LoggableMeal) -> Void
    let onCancel: () -> Void
    var explanation: LocalizedStringKey = "Enter what you actually ate. Reset on the review screen to restore the original values."

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    /// The fields as hydrated, so a stray swipe can't discard edits.
    @State private var openedFields: [String] = []
    @FocusState private var isEditing: Bool

    private var hasChanges: Bool { [calories, protein, carbs, fat] != openedFields }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(productName)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                } header: {
                    Text("Product")
                }

                Section {
                    macroField(title: "Calories", unit: "kcal", text: $calories)
                    macroField(title: "Protein",  unit: "g",    text: $protein)
                    macroField(title: "Carbs",    unit: "g",    text: $carbs)
                    macroField(title: "Fat",      unit: "g",    text: $fat)
                } header: {
                    Text("Macros")
                } footer: {
                    Text(explanation)
                    if !isValid {
                        Text("Enter whole numbers from 0 to 100,000 in every field.")
                    } else if macrosDisagree {
                        Text("Protein, carbs and fat add up to \(macroCalories) kcal. Check the numbers before saving.")
                            .foregroundStyle(AppColor.warning)
                    }
                }
            }
            .navigationTitle("Edit nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardChangesCancelButton(hasChanges: hasChanges, onCancel: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditing = false }
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onAppear(perform: hydrate)
    }

    private func macroField(title: LocalizedStringKey, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .focused($isEditing)
                .accessibilityLabel(Text(title))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: fieldWidth)
                .monospacedDigit()
            Text(unit)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: unitWidth, alignment: .leading)
        }
    }

    private func hydrate() {
        calories = String(initial?.calories ?? 0)
        protein  = String(initial?.proteinG ?? 0)
        carbs    = String(initial?.carbsG ?? 0)
        fat      = String(initial?.fatG ?? 0)
        openedFields = [calories, protein, carbs, fat]
    }

    private var isValid: Bool {
        [calories, protein, carbs, fat].allSatisfy { MacroInput.parse($0) != nil }
    }

    /// Calories implied by the macros (4 / 4 / 9 kcal per gram).
    private var macroCalories: Int {
        4 * (Int(protein) ?? 0) + 4 * (Int(carbs) ?? 0) + 9 * (Int(fat) ?? 0)
    }

    /// A soft check, not a gate: labels round and fibre/alcohol skew the
    /// sum, so only a gap over 15% is worth pointing out.
    private var macrosDisagree: Bool {
        guard let kcal = Int(calories), kcal > 0 else { return false }
        return Double(abs(kcal - macroCalories)) > Double(kcal) * 0.15
    }

    private func save() {
        guard isValid else { return }
        guard
            let kcal = MacroInput.parse(calories),
            let p = MacroInput.parse(protein),
            let c = MacroInput.parse(carbs),
            let f = MacroInput.parse(fat)
        else { return }
        var result = LoggableMeal(calories: kcal, proteinG: p, carbsG: c, fatG: f)
        if var component = initial?.components?.first, initial?.components?.count == 1,
           component.grams.isFinite, component.grams > 0 {
            component.per100g = .init(calories: Double(kcal) / component.grams * 100,
                                     proteinG: Double(p) / component.grams * 100,
                                     carbsG: Double(c) / component.grams * 100,
                                     fatG: Double(f) / component.grams * 100, fiberG: nil, sugarsG: nil)
            result.components = [component]
        }
        onSave(result)
    }
}
