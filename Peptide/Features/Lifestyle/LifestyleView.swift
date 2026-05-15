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
    @Environment(AppState.self) private var appState

    @State private var showMealScan = false
    @State private var showBarcodeScan = false
    @State private var showFoodLibrary = false
    @State private var editingMealEntry: MealEntry?
    @State private var showOutcomeCheckIn = false
    @State private var pendingPhotoFallback = false
    /// Carried into the food library when opened via Spotlight deep-
    /// link — the library reads this once on appear and pre-selects
    /// the food on the review screen. Cleared as soon as the sheet
    /// presents so a re-open without a fresh deep-link doesn't
    /// re-trigger.
    @State private var pendingFoodLogID: FoodLogDeepLink?
    /// Pending sheet hand-off requested from inside the food library.
    /// One of these is non-nil while the library sheet is mid-dismiss;
    /// `.onChange(of: showFoodLibrary)` consumes it after the dismiss
    /// completes, then opens the requested follow-up sheet.
    @State private var pendingFromLibrary: PendingLibraryHandoff?
    @State private var showWeightLog = false
    @State private var showWorkoutDetail = false
    @State private var showTargetsEditor = false

    private enum PendingLibraryHandoff {
        case barcode
        case photo
    }

    private var targets: NutritionTargets {
        dataStore.profile.nutritionTargets ?? .placeholder
    }

    /// Most recent outcome entry from before today, used to pre-fill
    /// the check-in sheet so the user nudges yesterday's values
    /// instead of starting from a neutral 3 across the board.
    private var yesterdayOutcome: OutcomeEntry? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return dataStore.profile.outcomeHistory
            .filter { !calendar.isDate($0.date, inSameDayAs: today) }
            .max { $0.date < $1.date }
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

                    FoodLibraryEntryCard(onTap: { showFoodLibrary = true })
                        .sectionAppear(index: 1)

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

                    let dailyBreakdown = dataStore.mealsByCategory()
                    MacroSummaryRow(
                        targets: targets,
                        consumed: dataStore.consumption(),
                        breakdown: dailyBreakdown,
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

                    MealStreakBadge(
                        currentStreak: dataStore.mealLoggingStreak,
                        bestStreak: dataStore.bestMealLoggingStreak
                    )
                    .sectionAppear(index: 3)

                    sectionHeader(eyebrow: "Wellness", title: "How you're feeling")
                        .sectionAppear(index: 4)

                    DailyCheckInCard(
                        todayEntry: dataStore.outcome(),
                        onTap: { showOutcomeCheckIn = true }
                    )
                    .sectionAppear(index: 4)

                    if let headline = OutcomeCorrelationEngine.headline(
                        outcomes: dataStore.profile.outcomeHistory,
                        entries: dataStore.entries
                    ) {
                        OutcomeCorrelationCard(
                            headline: headline,
                            sampleSize: dataStore.profile.outcomeHistory.count
                        )
                        .sectionAppear(index: 4)
                    }

                    let todaysEntries = dataStore.mealEntries()
                    if dataStore.consumption().caloriesKcal > 0 || !todaysEntries.isEmpty {
                        MealCategoriesCard(breakdown: dailyBreakdown)
                            .sectionAppear(index: 3)

                        TodaysMealsCard(
                            entries: todaysEntries,
                            onEdit: { entry in editingMealEntry = entry },
                            onDelete: { id in dataStore.unlogMealEntry(id: id) }
                        )
                        .sectionAppear(index: 3)
                    }

                    sectionHeader(eyebrow: "Movement", title: "Training")
                        .sectionAppear(index: 4)

                    WorkoutCard(
                        exerciseCountToday: dataStore.workoutSummary().count,
                        durationMinutesToday: dataStore.workoutSummary().minutes,
                        onTap: { showWorkoutDetail = true }
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
            .sheet(isPresented: $showFoodLibrary) {
                FoodLibraryFlow(
                    onClose: { showFoodLibrary = false },
                    onRequestBarcodeScan: { handleLibraryHandoff(.barcode) },
                    onRequestPhotoScan: { handleLibraryHandoff(.photo) },
                    initialDeepLink: pendingFoodLogID
                )
                .environment(dataStore)
                .onDisappear {
                    // Single-use — clear after the sheet consumed it
                    // (or after the user dismissed without using it).
                    pendingFoodLogID = nil
                }
            }
            .onChange(of: appState.pendingFoodLogID) { _, deepLink in
                guard let deepLink else { return }
                // Stash locally + clear the app-state slot so a
                // second tap on the same Spotlight result re-triggers.
                pendingFoodLogID = deepLink
                appState.pendingFoodLogID = nil
                showFoodLibrary = true
            }
            .onChange(of: showFoodLibrary) { _, isPresented in
                // Sheet handoff: when the library dismisses with a
                // pending follow-up, open the requested sheet after
                // the dismiss animation settles. Same pattern as the
                // barcode → photo handoff below.
                guard !isPresented, let handoff = pendingFromLibrary else { return }
                pendingFromLibrary = nil
                Task { @MainActor in
                    try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                    switch handoff {
                    case .barcode: showBarcodeScan = true
                    case .photo:   showMealScan = true
                    }
                }
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
            .navigationDestination(isPresented: $showWorkoutDetail) {
                WorkoutDetailView()
                    .environment(dataStore)
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
            .sheet(item: $editingMealEntry) { entry in
                MealEntryEditorSheet(
                    initial: entry,
                    onSave: { updated in
                        dataStore.updateMealEntry(updated)
                        editingMealEntry = nil
                    },
                    onDelete: { id in
                        dataStore.unlogMealEntry(id: id)
                        editingMealEntry = nil
                    },
                    onCancel: { editingMealEntry = nil }
                )
            }
            .sheet(isPresented: $showOutcomeCheckIn) {
                // `previousEntry` pre-fills with yesterday's values
                // when today is fresh — most days move only a point
                // or two, so the user's first interaction is a
                // confirmation, not five resets.
                OutcomeCheckInSheet(
                    date: Date(),
                    initial: dataStore.outcome(),
                    previousEntry: yesterdayOutcome,
                    onSave: { entry in
                        dataStore.logOutcome(entry)
                        showOutcomeCheckIn = false
                    },
                    onCancel: { showOutcomeCheckIn = false }
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

    /// Records the library's requested follow-up and starts the
    /// dismiss; `.onChange(of: showFoodLibrary)` opens the second
    /// sheet once the first has actually gone away.
    private func handleLibraryHandoff(_ next: PendingLibraryHandoff) {
        pendingFromLibrary = next
        showFoodLibrary = false
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
