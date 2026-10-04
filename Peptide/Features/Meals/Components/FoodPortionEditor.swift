import SwiftUI

enum FoodPortionInput {
    /// Decimal entry only; do not interpret grouping separators or partial input.
    static func grams(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite,
              (5...2000).contains(value) else { return nil }
        return value
    }
}

/// Local draft: typing and cancellation never alter the scan's portion.
struct FoodPortionEditor: View {
    let component: MealFoodComponent
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @FocusState private var amountFocused: Bool

    init(item: EditableFoodItem, onSave: @escaping (Double) -> Void) {
        self.init(component: item.component, onSave: onSave)
    }

    init(component: MealFoodComponent, onSave: @escaping (Double) -> Void) {
        self.component = component
        self.onSave = onSave
        _amount = State(initialValue: component.grams.formatted(.number.grouping(.never).precision(.fractionLength(0...3))))
    }

    private var preview: LoggableMeal? {
        guard let grams = FoodPortionInput.grams(amount) else { return nil }
        var result = component
        result.grams = grams
        return result.macros
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(component.name).font(AppFont.headline)
                    HStack {
                        Text("Amount")
                        TextField("Grams", text: $amount)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($amountFocused).monospacedDigit()
                            .accessibilityLabel("Portion in grams")
                        Text("g").foregroundStyle(AppColor.textSecondary)
                    }
                } footer: {
                    Text("Enter 5–2,000 g. Use a decimal point or comma, without thousands separators.")
                }
                Section("For this portion") {
                    if let preview {
                        LabeledContent("Calories", value: "\(preview.calories) kcal")
                        LabeledContent("Protein", value: "\(preview.proteinG) g")
                        LabeledContent("Carbs", value: "\(preview.carbsG) g")
                        LabeledContent("Fat", value: "\(preview.fatG) g")
                    } else {
                        Text("Enter a valid amount to preview nutrition.")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .glassFormStyle()
            .navigationTitle("Exact portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let grams = FoodPortionInput.grams(amount) else { return }
                        onSave(grams)
                        dismiss()
                    }.disabled(preview == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false }
                }
            }
        }
    }
}
