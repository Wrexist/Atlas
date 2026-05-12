import SwiftUI

/// "Lifestyle" tab. Stacks the meal-logging picker (barcode + photo),
/// the macro summary row, the workout drill-in, weight tracking, and
/// progress photos. All persistence lives on `dataStore.profile` so a
/// relaunch restores the full state without a separate cache layer.
struct LifestyleView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var showMealScan = false
    @State private var showBarcodeScan = false
    @State private var showWeightLog = false
    @State private var showWorkoutLog = false
    @State private var showTargetsEditor = false

    private var targets: NutritionTargets {
        dataStore.profile.nutritionTargets ?? .placeholder
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    LogMealEntryPicker(
                        onScanBarcode: { showBarcodeScan = true },
                        onSnapPhoto: { showMealScan = true }
                    )

                    if dataStore.profile.nutritionTargets == nil {
                        targetsPrompt
                    }

                    MacroSummaryRow(
                        targets: targets,
                        consumed: dataStore.consumption(),
                        onAddWater: { oz in
                            dataStore.logWater(oz: oz)
                        }
                    )
                    .contextMenu {
                        Button("Edit targets", systemImage: "pencil") {
                            showTargetsEditor = true
                        }
                    }

                    WorkoutCard(
                        exerciseCountToday: dataStore.workoutSummary().count,
                        durationMinutesToday: dataStore.workoutSummary().minutes,
                        onTap: { showWorkoutLog = true }
                    )

                    WeightTrackingCard(
                        history: dataStore.profile.weightHistory,
                        unit: dataStore.profile.bodyMetrics.unit,
                        onLog: { showWeightLog = true }
                    )

                    ProgressPhotosCard()
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Lifestyle")
            .sheet(isPresented: $showMealScan) {
                MealScanFlow(onClose: { showMealScan = false })
                    .environment(dataStore)
            }
            .sheet(isPresented: $showBarcodeScan) {
                BarcodeScanFlow(
                    onClose: { showBarcodeScan = false },
                    onRequestPhotoFallback: handlePhotoFallback
                )
                .environment(dataStore)
            }
            .sheet(isPresented: $showWeightLog) {
                WeightLogSheet(
                    history: dataStore.profile.weightHistory,
                    unit: dataStore.profile.bodyMetrics.unit,
                    onLog: { kg in dataStore.logWeight(kg: kg) },
                    onDelete: { id in dataStore.deleteWeight(id: id) },
                    onClose: { showWeightLog = false }
                )
            }
            .sheet(isPresented: $showWorkoutLog) {
                WorkoutLogSheet(
                    history: dataStore.profile.workoutHistory,
                    onLog: { entry in dataStore.logWorkout(entry) },
                    onDelete: { id in dataStore.deleteWorkout(id: id) },
                    onClose: { showWorkoutLog = false }
                )
            }
            .sheet(isPresented: $showTargetsEditor) {
                NutritionTargetsEditor(
                    initial: dataStore.profile.nutritionTargets ?? .zero,
                    onSave: { targets in
                        dataStore.updateNutritionTargets(targets)
                        showTargetsEditor = false
                    },
                    onCancel: { showTargetsEditor = false }
                )
            }
        }
    }

    /// Dismisses the barcode sheet and presents the photo sheet a beat
    /// later. iOS won't show two sheets at the same time, so we have
    /// to wait for the dismiss animation to start before requesting
    /// the next one — 0.35 s lands cleanly after the spring settles.
    private func handlePhotoFallback() {
        showBarcodeScan = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showMealScan = true
        }
    }

    private var targetsPrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Set your daily targets first")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Add height, weight, age, and gender on Profile to compute calorie and macro reference targets, or tap Edit to set them manually.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Edit targets") { showTargetsEditor = true }
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

// MARK: - Editor target placeholders

extension NutritionTargets {
    /// Used as a soft default when the user hasn't computed or entered
    /// macro targets yet — the rings still render with sensible bounds
    /// instead of dividing by zero.
    static let placeholder = NutritionTargets(
        calories: 2000,
        proteinG: 120,
        carbsG: 220,
        fatG: 60,
        fiberG: 30
    )

    fileprivate static let zero = NutritionTargets(
        calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0
    )
}

// MARK: - Targets editor (preserved from the previous Lifestyle iteration)

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
