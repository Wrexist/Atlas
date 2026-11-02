import SwiftUI

/// Content of the Meals tab, mounted by `MealsContainerView`.
///
/// Owns every meal-related sheet (food library, barcode, photo,
/// targets editor, meal entry edit) because each one is paired
/// to its own state. SwiftUI bubbles `.sheet(...)` up through the
/// view hierarchy, so attaching them here works identically to
/// attaching them on the container's NavigationStack.
struct HomeMealsSection: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    @State private var showMealScan = false
    @State private var showBarcodeScan = false
    @State private var showTableScan = false
    @State private var openTable: TableRoute?
    @State private var showFoodLibrary = false
    @State private var showTargetsEditor = false
    @State private var editingMealEntry: MealEntry?
    @State private var pendingPhotoFallback = false
    /// Local copy of the Spotlight deep-link so the food library
    /// sheet can read it on first present. Cleared on dismiss so a
    /// re-open without a fresh tap doesn't re-trigger.
    @State private var pendingFoodLogID: FoodLogDeepLink?
    /// Sheet hand-off requested from inside the food library —
    /// `.barcode` or `.photo` so the library can hand the user off
    /// to the right next sheet after dismissing itself.
    @State private var pendingFromLibrary: PendingLibraryHandoff?
    /// Day being viewed, as an offset from today (0 = today). An offset
    /// rather than a Date so the tab still means "today" after midnight.
    @State private var dayOffset = 0
    /// Most recent water quick-add, kept briefly so it can be undone.
    @State private var lastWaterLog: WaterLog?
    /// Open day picker for copying one meal, or the whole day.
    @State private var copyRequest: CopyRequest?
    /// The entries the last copy logged, kept so its toast can undo it.
    @State private var lastCopiedMeals: [MealEntry] = []
    @State private var showCopyToast = false
    @State private var copyToastMessage: LocalizedStringResource = ""
    @State private var copyToastID = 0

    private struct TableRoute: Identifiable {
        let id: UUID
    }

    private struct CopyRequest: Identifiable {
        let id = UUID()
        let category: MealCategory?
    }

    private enum PendingLibraryHandoff {
        case barcode
        case photo
    }

    private struct WaterLog: Equatable {
        let id = UUID()
        let fluidOunces: Double
        let date: Date
    }

    private var selectedDay: Date {
        LifestyleDataLogic.mealDay(offset: dayOffset)
    }

    private var previousDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
    }

    private var targets: NutritionTargets {
        dataStore.profile.nutritionTargets ?? .placeholder
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            HomeSectionHeader(
                eyebrow: "Meals",
                title: "Capture what you ate"
            )
            .sectionAppear(index: 0)

            MealDaySwitcher(offset: $dayOffset)
                .sectionAppear(index: 1)

            FoodLibraryEntryCard(onTap: { showFoodLibrary = true })
                .sectionAppear(index: 2)

            LogMealEntryPicker(
                onScanBarcode: { showBarcodeScan = true },
                onSnapPhoto: { showMealScan = true },
                onScanTable: { showTableScan = true }
            )
            .sectionAppear(index: 3)

            let dayEntries = dataStore.mealEntries(for: selectedDay)
            if let table = latestTable(in: dayEntries) {
                LatestTableCard(moment: table.moment, dishes: table.dishes) {
                    openTable = TableRoute(id: table.moment.id)
                }
                .scrollReveal()
            }

            if dataStore.profile.nutritionTargets == nil {
                targetsPrompt
            }

            HomeSectionHeader(
                eyebrow: "Daily rings",
                title: "Nutrition",
                trailing: {
                    Button {
                        showTargetsEditor = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(AppFont.scaled(11, weight: .semibold))
                            Text("Edit targets")
                                .font(AppFont.scaled(11, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.accentLight)
                        .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                }
            )

            let dailyBreakdown = dataStore.mealsByCategory(for: selectedDay)
            let dailyConsumption = dataStore.consumption(for: selectedDay)
            MacroSummaryRow(
                targets: targets,
                consumed: dailyConsumption,
                breakdown: dailyBreakdown,
                unit: dataStore.profile.bodyMetrics.unit,
                onAddWater: logWater,
                onUndoWater: lastWaterLog == nil ? nil : { undoWater() }
            )
            .contextMenu {
                Button("Edit targets", systemImage: "pencil") {
                    showTargetsEditor = true
                }
            }
            .sectionAppear(index: 4)

            MealStreakBadge(
                currentStreak: dataStore.mealLoggingStreak,
                bestStreak: dataStore.bestMealLoggingStreak
            )
            .scrollReveal()

            if !dayEntries.isEmpty {
                DailyMealNutrientsCard(entries: dayEntries, fiberTargetG: dataStore.profile.nutritionTargets?.fiberG)
                    .scrollReveal()
                DailyMicronutrientsCard(entries: dayEntries)
                    .scrollReveal()
            }
            if dailyConsumption.caloriesKcal > 0 || !dayEntries.isEmpty {
                MealCategoriesCard(
                    breakdown: dailyBreakdown,
                    dayTitle: dayOffset == 0 ? nil : MealDaySwitcher.title(for: selectedDay)
                )
                    .scrollReveal()
            }

            // Always shown: its empty state is the "nothing logged" answer
            // when the user steps back to an empty day.
            TodaysMealsCard(
                entries: dayEntries,
                dayTitle: dayOffset == 0 ? nil : MealDaySwitcher.title(for: selectedDay),
                onEdit: { entry in editingMealEntry = entry },
                onLogAgain: logAgain,
                onDelete: { id in dataStore.unlogMealEntry(id: id) },
                previousDayCategories: Set(dataStore.mealEntries(for: previousDay).map(\.category)),
                previousDayName: MealDaySwitcher.inlineTitle(for: previousDay),
                onCopyFromPreviousDay: { category in copyMeals(from: previousDay, category: category) },
                onCopyFromAnotherDay: { category in copyRequest = CopyRequest(category: category) }
            )
            .overlay(alignment: .top) {
                SyncToast(
                    isShowing: $showCopyToast,
                    message: copyToastMessage,
                    autoDismissAfter: AppAnimation.logSuccessAutoCloseDelay,
                    action: .init(label: "Undo", perform: undoCopy),
                    presentationID: copyToastID
                )
                .padding(.top, Spacing.sm)
            }
            .scrollReveal()
        }
        .onAppear { dataStore.refreshAdaptiveTargets() }
        .sheet(isPresented: $showMealScan) {
            MealScanFlow(onClose: { showMealScan = false }, logDay: selectedDay)
                .environment(dataStore)
        }
        #if DEBUG
        .task {
            if TableScanFixture.isRequested, await TableScanFixture.seedTable(in: dataStore) {
                showTableScan = true
            }
        }
        #endif
        .sheet(isPresented: $showTableScan) {
            TableScanFlow(
                logDay: selectedDay,
                onKeep: keepTable,
                onClose: { showTableScan = false }
            )
            .environment(dataStore)
        }
        .fullScreenCover(item: $openTable) { route in
            PlateTableView(momentID: route.id, onClose: { openTable = nil })
                .environment(dataStore)
        }
        .sheet(isPresented: $showBarcodeScan) {
            BarcodeScanFlow(
                onClose: { showBarcodeScan = false },
                onRequestPhotoFallback: handlePhotoFallback,
                logDay: selectedDay
            )
            .environment(dataStore)
        }
        .sheet(isPresented: $showFoodLibrary) {
            FoodLibraryFlow(
                onClose: { showFoodLibrary = false },
                onRequestBarcodeScan: { handleLibraryHandoff(.barcode) },
                onRequestPhotoScan: { handleLibraryHandoff(.photo) },
                initialDeepLink: pendingFoodLogID,
                logDay: selectedDay
            )
            .environment(dataStore)
            .liquidGlassPresentation()
            .onDisappear {
                // Single-use deep link — once the library sheet has
                // either consumed it or been dismissed, clear so a
                // re-open without a fresh tap starts cleanly.
                pendingFoodLogID = nil
            }
        }
        .sheet(isPresented: $showTargetsEditor) {
            NutritionTargetsEditor(
                initial: dataStore.profile.nutritionTargets ?? .zero,
                bodyMetrics: dataStore.profile.bodyMetrics,
                goalRaw: dataStore.profile.primaryGoal,
                expenditure: dataStore.expenditureEstimate(),
                onSave: { targets in
                    dataStore.updateNutritionTargets(targets)
                    showTargetsEditor = false
                },
                onCancel: { showTargetsEditor = false }
            )
            .liquidGlassPresentation()
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
        .sheet(item: $copyRequest) { request in
            MealCopySourceSheet(
                targetDay: selectedDay,
                category: request.category,
                onCopy: { sourceDay in
                    copyRequest = nil
                    copyMeals(from: sourceDay, category: request.category)
                },
                onCancel: { copyRequest = nil }
            )
            .environment(dataStore)
            .liquidGlassPresentation()
        }
        .task(id: lastWaterLog?.id) {
            // Undo window for the last water quick-add. A newer log
            // restarts the window; switching days drops it below.
            guard lastWaterLog != nil else { return }
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            guard !Task.isCancelled else { return }
            AppAnimation.with(AppAnimation.fadeIn) { lastWaterLog = nil }
        }
        .onChange(of: dayOffset) { _, _ in
            lastWaterLog = nil
        }
        .onChange(of: appState.pendingFoodLogID) { _, deepLink in
            // Spotlight tapped a food index entry.
            guard let deepLink else { return }
            pendingFoodLogID = deepLink
            appState.pendingFoodLogID = nil
            showFoodLibrary = true
        }
        .onChange(of: showFoodLibrary) { _, isPresented in
            // Sheet handoff: when the library dismisses with a
            // pending follow-up, open the requested sheet after
            // the dismiss animation settles. SwiftUI won't show
            // two sheets at the same time, so chaining on real
            // state is more robust than guessing the duration.
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
            // a pending fallback, present the photo sheet. Same
            // pattern as the library handoff above.
            guard !isPresented, pendingPhotoFallback else { return }
            pendingPhotoFallback = false
            Task { @MainActor in
                try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                showMealScan = true
            }
        }
    }

    /// The newest table on the viewed day that still has a dish in the
    /// diary.
    private func latestTable(in entries: [MealEntry]) -> (moment: TableMoment, dishes: [TableDish])? {
        for moment in TableMomentStore.shared.moments(on: selectedDay).reversed() {
            let dishes = moment.logged(in: entries)
            if !dishes.isEmpty { return (moment, dishes) }
        }
        return nil
    }

    /// Closes the scan sheet and writes the table behind it, so the
    /// "Adding 2 of 4 dishes…" pill plays on the Meals screen.
    private func keepTable(_ draft: TableMomentStore.Draft) {
        showTableScan = false
        Task { await TableMomentStore.shared.keep(draft, in: dataStore) }
    }

    /// Logs water onto the viewed day and opens the Undo window.
    private func logWater(fluidOunces: Double) {
        let date = LifestyleDataLogic.logTimestamp(on: selectedDay)
        dataStore.logWater(fluidOunces: fluidOunces, date: date)
        AppAnimation.with(AppAnimation.fadeIn) {
            lastWaterLog = WaterLog(fluidOunces: fluidOunces, date: date)
        }
    }

    private func undoWater() {
        guard let log = lastWaterLog else { return }
        dataStore.logWater(fluidOunces: -log.fluidOunces, date: log.date)
        Haptics.impact(.light)
        AppAnimation.with(AppAnimation.fadeIn) { lastWaterLog = nil }
    }

    /// Duplicates a logged meal onto the viewed day at the current
    /// clock time.
    private func logAgain(_ entry: MealEntry) {
        let date = LifestyleDataLogic.logTimestamp(on: selectedDay)
        dataStore.logMealEntry(LifestyleDataLogic.relogged(entry, at: date))
        Haptics.success()
    }

    /// Copies one meal (or the whole day when `category` is nil) from
    /// `sourceDay` onto the viewed day and opens the Undo toast.
    private func copyMeals(from sourceDay: Date, category: MealCategory?) {
        let copies = dataStore.copyMeals(from: sourceDay, to: selectedDay, category: category)
        guard !copies.isEmpty else { return }
        Haptics.success()
        lastCopiedMeals = copies
        copyToastMessage = LocalizedStringResource(
            "Copied from \(MealDaySwitcher.inlineTitle(for: sourceDay))",
            comment: "Toast after copying meals in the diary. The value is the source day, e.g. “yesterday”."
        )
        copyToastID += 1
        showCopyToast = true
    }

    private func undoCopy() {
        for meal in lastCopiedMeals {
            dataStore.unlogMealEntry(id: meal.id)
        }
        lastCopiedMeals = []
        Haptics.impact(.light)
    }

    /// Sets a flag and dismisses the barcode sheet — the .onChange
    /// on `showBarcodeScan` above presents the photo sheet once the
    /// dismiss has actually completed.
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

    private var targetsPrompt: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconTile("sparkles", size: 36)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Set your daily targets first")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Add height, weight, age, and gender on Profile to compute calorie and macro targets, or tap Edit targets to set them manually.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Edit targets") { showTargetsEditor = true }
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                    .minimumHitArea()
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassControl(
            .rect(cornerRadius: Spacing.cardCornerRadius),
            tint: AppColor.accentPrimary.opacity(0.10),
            border: AppColor.accentPrimary.opacity(0.35)
        )
    }
}
