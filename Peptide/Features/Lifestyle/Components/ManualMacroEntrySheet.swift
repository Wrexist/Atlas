import SwiftUI

/// Manual macro entry for foods the meal scanner can't see — drinks,
/// hand-prepped meals, or anything the user wants to log from packaging
/// off-camera. Hits `DataStore.logMeal(calories:proteinG:carbsG:fatG:date:)`
/// once saved, so the macros land in the same daily bucket the
/// scanner-based path writes to and the rings on the Lifestyle card pick
/// them up immediately.
///
/// Validation is intentionally permissive: any non-negative integer in
/// any of the four macro fields counts as a valid entry. The meal
/// name is optional — it isn't persisted today (DailyConsumption only
/// tracks totals) but is exposed in the form so it doesn't feel like
/// a blank-shaped entry surface. Hooking it into a per-entry log is
/// tracked as a separate work item.
struct ManualMacroEntrySheet: View {
    let onLog: (Int, Int, Int, Int, Date) -> Void
    let onClose: () -> Void

    @State private var mealName: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var date: Date = Date()
    @FocusState private var caloriesFocused: Bool

    private var caloriesValue: Int { Int(calories) ?? 0 }
    private var proteinValue: Int { Int(protein) ?? 0 }
    private var carbsValue: Int { Int(carbs) ?? 0 }
    private var fatValue: Int { Int(fat) ?? 0 }

    /// Allow save when any of the four fields holds a positive integer.
    /// All-zero entries would just add a noise row that's indistinguishable
    /// from the empty state, so block them at the button.
    private var canSave: Bool {
        let total = caloriesValue + proteinValue + carbsValue + fatValue
        let allParseable = [calories, protein, carbs, fat]
            .allSatisfy { $0.isEmpty || Int($0) != nil }
        return total > 0 && allParseable
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Optional name (e.g. Lunch)", text: $mealName)
                        .textInputAutocapitalization(.sentences)
                    DatePicker(
                        "When",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Macros") {
                    numericField(label: "Calories", unit: "kcal", text: $calories)
                        .focused($caloriesFocused)
                    numericField(label: "Protein", unit: "g", text: $protein)
                    numericField(label: "Carbs", unit: "g", text: $carbs)
                    numericField(label: "Fat", unit: "g", text: $fat)
                }

                Section {
                    HStack {
                        Text("Total")
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer()
                        Text(totalLine)
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textPrimary)
                    }
                } footer: {
                    Text("These macros add to today's totals on the Lifestyle tab. Targets stay unchanged.")
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { caloriesFocused = true }
    }

    private func numericField(
        label: LocalizedStringKey,
        unit: String,
        text: Binding<String>
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 32, alignment: .leading)
        }
    }

    private var totalLine: String {
        "\(caloriesValue) kcal · \(proteinValue)P · \(carbsValue)C · \(fatValue)F"
    }

    private func save() {
        guard canSave else { return }
        onLog(caloriesValue, proteinValue, carbsValue, fatValue, date)
        onClose()
    }
}

#Preview {
    ManualMacroEntrySheet(
        onLog: { c, p, ca, f, d in
            print("logged \(c)/\(p)/\(ca)/\(f) at \(d)")
        },
        onClose: {}
    )
    .preferredColorScheme(.dark)
}
