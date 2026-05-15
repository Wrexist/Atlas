import SwiftUI

/// Standalone NavigationStack-wrapped form for editing the user's
/// daily calorie + macro targets. Lives in /Lifestyle/Components
/// because it's still mounted from the meal-logging surface, but no
/// longer co-located with the now-deleted `LifestyleView` so the
/// Today recompose (Phase 33) could remove that file without
/// orphaning the editor.
///
/// Two preset extensions on `NutritionTargets` live alongside this
/// view because they're its closest collaborators — `.placeholder`
/// for "user hasn't computed targets yet, render with sensible
/// bounds", and `.zero` as the initial seed when the editor opens
/// without existing values.
struct NutritionTargetsEditor: View {
    let initial: NutritionTargets
    let onSave: (NutritionTargets) -> Void
    let onCancel: () -> Void

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var fiber: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Calories") {
                    numericField(title: "kcal", text: $calories)
                }
                Section("Macros") {
                    numericField(title: "Protein (g)", text: $protein)
                    numericField(title: "Carbs (g)",   text: $carbs)
                    numericField(title: "Fat (g)",     text: $fat)
                    numericField(title: "Fiber (g)",   text: $fiber)
                }
            }
            .navigationTitle("Edit targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: hydrate)
    }

    private func numericField(title: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    private func hydrate() {
        calories = String(initial.calories)
        protein = String(initial.proteinG)
        carbs = String(initial.carbsG)
        fat = String(initial.fatG)
        fiber = String(initial.fiberG)
    }

    private var isValid: Bool {
        [calories, protein, carbs, fat, fiber].allSatisfy { Int($0) != nil }
    }

    private func save() {
        guard
            let kcal = Int(calories),
            let p = Int(protein),
            let c = Int(carbs),
            let f = Int(fat),
            let fib = Int(fiber)
        else { return }
        onSave(NutritionTargets(
            calories: kcal,
            proteinG: p,
            carbsG: c,
            fatG: f,
            fiberG: fib
        ))
    }
}

extension NutritionTargets {
    /// Soft default when the user hasn't computed or entered macro
    /// targets yet — the rings still render with sensible bounds
    /// instead of dividing by zero. Consumed by the meal-logging
    /// flow's "calories remaining" math and by the macro summary row.
    static let placeholder = NutritionTargets(
        calories: 2000,
        proteinG: 120,
        carbsG: 220,
        fatG: 60,
        fiberG: 30
    )

    /// Empty seed for the editor when no existing targets are stored.
    /// `fileprivate` would be tighter, but the editor's caller (now
    /// `HomeMealsSection`) lives in a different file, so this needs
    /// internal visibility.
    static let zero = NutritionTargets(
        calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
    )
}
