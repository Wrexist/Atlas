import SwiftUI

/// "Lifestyle" tab — displays the calorie + macro targets pre-filled from
/// onboarding and lets the user recompute them from their current body
/// stats or override the numbers manually. Reference targets only; the
/// disclaimer makes that explicit.
struct LifestyleView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if let targets = dataStore.profile.nutritionTargets {
                        populated(targets: targets)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Lifestyle")
            .sheet(isPresented: $showEditor) {
                NutritionTargetsEditor(
                    initial: dataStore.profile.nutritionTargets ?? .zero,
                    onSave: { targets in
                        dataStore.updateNutritionTargets(targets)
                        showEditor = false
                    },
                    onCancel: { showEditor = false }
                )
            }
        }
    }

    @ViewBuilder
    private func populated(targets: NutritionTargets) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Daily targets")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            Text("For reference only. Not medical advice.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        DailyTargetsCard(targets: targets)

        VStack(spacing: Spacing.sm) {
            GlassButton(
                title: "Recompute from my stats",
                icon: "arrow.triangle.2.circlepath",
                style: .secondary,
                isFullWidth: true,
                action: recompute
            )
            .disabled(NutritionMath.dailyTargets(for: dataStore.profile.bodyMetrics) == nil)

            GlassButton(
                title: "Edit manually",
                icon: "pencil",
                style: .ghost,
                isFullWidth: true
            ) {
                showEditor = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .padding(.top, Spacing.xxl)

            Text("Set your daily targets")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Add your height, weight, age, and gender on the Profile tab to compute your calorie and macro reference targets.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            if NutritionMath.dailyTargets(for: dataStore.profile.bodyMetrics) != nil {
                GlassButton(
                    title: "Compute from my stats",
                    icon: "wand.and.stars",
                    style: .primary,
                    isFullWidth: true,
                    action: recompute
                )
                .padding(.top, Spacing.md)
            }

            GlassButton(
                title: "Enter manually",
                icon: "pencil",
                style: .secondary,
                isFullWidth: true
            ) {
                showEditor = true
            }
        }
    }

    private func recompute() {
        guard let targets = NutritionMath.dailyTargets(for: dataStore.profile.bodyMetrics) else { return }
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        dataStore.updateNutritionTargets(targets)
    }
}

private extension NutritionTargets {
    static let zero = NutritionTargets(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)
}

private struct NutritionTargetsEditor: View {
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
