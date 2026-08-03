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
    let productName: String
    let initial: LoggableMeal?
    let onSave: (LoggableMeal) -> Void
    let onCancel: () -> Void

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""

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
                    Text("Numbers replace whatever the portion picker would compute. Reset on the review card to go back to Open Food Facts data.")
                }
            }
            .navigationTitle("Edit nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    private func macroField(title: LocalizedStringKey, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .monospacedDigit()
            Text(unit)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, alignment: .leading)
        }
    }

    private func hydrate() {
        calories = String(initial?.calories ?? 0)
        protein  = String(initial?.proteinG ?? 0)
        carbs    = String(initial?.carbsG ?? 0)
        fat      = String(initial?.fatG ?? 0)
    }

    private var isValid: Bool {
        [calories, protein, carbs, fat].allSatisfy { Int($0) != nil }
    }

    private func save() {
        guard
            let kcal = Int(calories),
            let p = Int(protein),
            let c = Int(carbs),
            let f = Int(fat)
        else { return }
        onSave(LoggableMeal(calories: kcal, proteinG: p, carbsG: c, fatG: f))
    }
}
