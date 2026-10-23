import SwiftUI

enum FoodPortionInput {
    /// The weights a food portion may take, everywhere it can be set.
    static let gramsRange: ClosedRange<Double> = 5...2000

    /// Decimal entry only; do not interpret grouping separators or partial input.
    static func grams(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite,
              gramsRange.contains(value) else { return nil }
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
                    factorChips
                } footer: {
                    Text("\(FoodPortionInput.gramsRange.lowerBound.formatted())–\(FoodPortionInput.gramsRange.upperBound.formatted()) g")
                }
                Section("For this portion") {
                    if let preview {
                        previewRow("Calories", value: preview.calories, unit: "kcal")
                        previewRow("Protein", value: preview.proteinG, unit: "g")
                        previewRow("Carbs", value: preview.carbsG, unit: "g")
                        previewRow("Fat", value: preview.fatG, unit: "g")
                    } else {
                        Text("Enter a valid amount to preview nutrition.")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .glassFormStyle()
            .appAnimation(AppAnimation.quick, value: preview?.calories)
            .onAppear { amountFocused = true }
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

    /// "Half of it" or "twice that" is how a portion usually gets
    /// corrected, so those are one tap instead of mental arithmetic.
    private static let factors: [Double] = [0.5, 1, 1.5, 2]

    private var factorChips: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Self.factors, id: \.self) { factor in
                factorChip(factor)
            }
        }
    }

    private func factorChip(_ factor: Double) -> some View {
        let grams = (component.grams * factor).rounded()
        let label = "×" + factor.formatted(.number.precision(.fractionLength(0...1)))
        let isActive = FoodPortionInput.grams(amount) == grams
        return Button {
            Haptics.selection()
            amount = grams.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
        } label: {
            Text(verbatim: label)
                .font(AppFont.scaled(13, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? AppColor.accentPrimary : AppColor.textSecondary)
        .minimumHitArea()
        .disabled(!FoodPortionInput.gramsRange.contains(grams))
        .accessibilityLabel(Text("\(label) portion"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func previewRow(_ title: LocalizedStringKey, value: Int, unit: String) -> some View {
        LabeledContent {
            Text("\(value) \(unit)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        } label: {
            Text(title)
        }
    }
}
