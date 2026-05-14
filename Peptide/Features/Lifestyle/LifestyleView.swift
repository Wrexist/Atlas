import SwiftUI

/// "Lifestyle" section of the Home tab. Stacks the meal-logging picker
/// (barcode + photo), the nutrition rings hero, the workout drill-in,
/// weight tracking, and progress photos. All persistence lives on
/// `dataStore.profile` so a relaunch restores the full state without a
/// separate cache layer.
///
/// Lives under `HomeContainerView`, which provides the floating top
/// tab bar via `safeAreaInset`. The view intentionally omits a
/// navigation title since the top pill already labels it as
/// "Lifestyle" — a system nav title would duplicate that.
struct LifestyleView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var showMealScan = false
    @State private var showBarcodeScan = false
    @State private var pendingPhotoFallback = false
    @State private var showWeightLog = false
    @State private var showWorkoutLog = false
    @State private var showTargetsEditor = false

    private var targets: NutritionTargets {
        dataStore.profile.nutritionTargets ?? .placeholder
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    sectionHeader(
                        eyebrow: "Today",
                        title: "Capture a meal"
                    )
                    .sectionAppear(index: 0)

                    LogMealEntryPicker(
                        onScanBarcode: { showBarcodeScan = true },
                        onSnapPhoto: { showMealScan = true }
                    )
                    .sectionAppear(index: 1)

                    if dataStore.profile.nutritionTargets == nil {
                        targetsPrompt
                            .sectionAppear(index: 2)
                    }

                    sectionHeader(
                        eyebrow: "Daily Rings",
                        title: "Nutrition",
                        trailing: {
                            Button {
                                showTargetsEditor = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Edit targets")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColor.accentLight)
                            }
                            .buttonStyle(.plain)
                        }
                    )
                    .sectionAppear(index: 2)

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
                    .sectionAppear(index: 3)

                    sectionHeader(eyebrow: "Movement", title: "Training")
                        .sectionAppear(index: 4)

                    WorkoutCard(
                        exerciseCountToday: dataStore.workoutSummary().count,
                        durationMinutesToday: dataStore.workoutSummary().minutes,
                        onTap: { showWorkoutLog = true }
                    )
                    .sectionAppear(index: 4)

                    sectionHeader(eyebrow: "Body", title: "Trends")
                        .sectionAppear(index: 4)

                    WeightTrackingCard(
                        history: dataStore.dedupedWeightHistory,
                        unit: dataStore.profile.bodyMetrics.unit,
                        onLog: { showWeightLog = true }
                    )
                    .sectionAppear(index: 4)

                    ProgressPhotosCard()
                        .sectionAppear(index: 4)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(lifestyleBackground.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
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
            .onChange(of: showBarcodeScan) { _, isPresented in
                // Sheet handoff: when the barcode sheet dismisses with
                // a pending fallback, present the photo sheet. The
                // brief sleep lets SwiftUI finish the dismiss animation
                // — iOS otherwise silently drops a second presentation
                // that races with the first. The canonical delay lives
                // on AppAnimation so every sheet-chain site agrees.
                guard !isPresented, pendingPhotoFallback else { return }
                pendingPhotoFallback = false
                Task { @MainActor in
                    try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                    showMealScan = true
                }
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

    /// Sets a flag and dismisses the barcode sheet — the .onChange on
    /// `showBarcodeScan` above presents the photo sheet once the dismiss
    /// has actually completed. iOS won't show two sheets at the same
    /// time, and chaining on real state is more robust than guessing
    /// at the dismiss animation duration.
    private func handlePhotoFallback() {
        pendingPhotoFallback = true
        showBarcodeScan = false
    }

    @ViewBuilder
    private func sectionHeader<Trailing: View>(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, Spacing.xs)
    }

    private func sectionHeader(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey
    ) -> some View {
        sectionHeader(eyebrow: eyebrow, title: title) { EmptyView() }
    }

    private var lifestyleBackground: some View {
        ZStack {
            AppColor.background

            // Soft top-of-page accent glow so the floating tab pill sits
            // on a surface that subtly references the brand gradient
            // without overpowering the content underneath.
            RadialGradient(
                colors: [
                    AppColor.accentPrimary.opacity(0.20),
                    Color.clear,
                ],
                center: .init(x: 0.85, y: 0.05),
                startRadius: 0,
                endRadius: 360
            )
            .blendMode(.plusLighter)
            .opacity(0.7)

            RadialGradient(
                colors: [
                    AppColor.accentLight.opacity(0.12),
                    Color.clear,
                ],
                center: .init(x: 0.1, y: 0.0),
                startRadius: 0,
                endRadius: 280
            )
            .blendMode(.plusLighter)
            .opacity(0.6)
        }
    }

    private var targetsPrompt: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Set your daily targets first")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Add height, weight, age, and gender on Profile to compute calorie and macro targets, or tap Edit to set them manually.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Edit targets") { showTargetsEditor = true }
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 1)
                }
        }
        .liquidGlass(.rect(cornerRadius: Spacing.cardCornerRadius))
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
