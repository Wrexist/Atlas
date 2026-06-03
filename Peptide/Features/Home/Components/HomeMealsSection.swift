import SwiftUI

/// "Meals" block of the merged Today scroll. Phase 33 (Today
/// recompose) pulled this content out of the now-deleted
/// `LifestyleView` so the user lands on a single curated scroll
/// instead of a Home/Lifestyle pill split.
///
/// Owns every meal-related sheet (food library, barcode, photo,
/// targets editor, meal entry edit) because each one is paired
/// to its own state. Mounting these sheets on the section view
/// keeps Home's body tight — SwiftUI bubbles `.sheet(...)` up
/// through the view hierarchy so attaching them here works
/// identically to attaching them on Home's NavigationStack.
struct HomeMealsSection: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    /// True when this instance is the canonical destination for
    /// Spotlight food deep-links. The section is mounted both on
    /// the Today scroll and on the Meals tab; only the Meals-tab
    /// instance should react to `appState.pendingFoodLogID`,
    /// otherwise both instances clear the flag on the same runloop
    /// tick and the active-tab instance loses the race.
    var consumesDeepLink: Bool = false

    @State private var showMealScan = false
    @State private var showBarcodeScan = false
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

    private enum PendingLibraryHandoff {
        case barcode
        case photo
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

            FoodLibraryEntryCard(onTap: { showFoodLibrary = true })

            LogMealEntryPicker(
                onScanBarcode: { showBarcodeScan = true },
                onSnapPhoto: { showMealScan = true }
            )

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
                                .font(.system(size: 11, weight: .semibold))
                            Text("Edit targets")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColor.accentLight)
                    }
                    .buttonStyle(.plain)
                }
            )

            let dailyBreakdown = dataStore.mealsByCategory()
            MacroSummaryRow(
                targets: targets,
                consumed: dataStore.consumption(),
                breakdown: dailyBreakdown,
                onAddWater: { oz in dataStore.logWater(oz: oz) }
            )
            .contextMenu {
                Button("Edit targets", systemImage: "pencil") {
                    showTargetsEditor = true
                }
            }

            MealStreakBadge(
                currentStreak: dataStore.mealLoggingStreak,
                bestStreak: dataStore.bestMealLoggingStreak
            )

            let todaysEntries = dataStore.mealEntries()
            if dataStore.consumption().caloriesKcal > 0 || !todaysEntries.isEmpty {
                MealCategoriesCard(breakdown: dailyBreakdown)

                TodaysMealsCard(
                    entries: todaysEntries,
                    onEdit: { entry in editingMealEntry = entry },
                    onDelete: { id in dataStore.unlogMealEntry(id: id) }
                )
            }
        }
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
        .onChange(of: appState.pendingFoodLogID) { _, deepLink in
            // Spotlight tapped a food index entry. Only the Meals-tab
            // instance consumes — see `consumesDeepLink` above.
            guard consumesDeepLink, let deepLink else { return }
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
