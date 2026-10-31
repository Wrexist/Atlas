import SwiftUI
import PhotosUI

/// End-to-end barcode-scan sheet: opens the camera, resolves the
/// detected code against Open Food Facts, lets the user dial in a
/// portion + meal category, and writes a `MealEntry` through
/// `dataStore.logMealEntry(_:)` — keeping the per-meal history and
/// the day's aggregate in lockstep.
///
/// Mirrors the phase-state-machine pattern of `MealScanFlow` so the
/// two scanners feel like siblings to the user. The portion picker is
/// inlined as a section of the review phase rather than a separate
/// sheet — keeping the recalculation visually anchored to the macro
/// readout is the whole point of the UX.
struct BarcodeScanFlow: View {
    @Environment(DataStore.self) private var dataStore
    let onClose: () -> Void
    /// Fired when the user taps "Scan meal photo" on the
    /// not-found screen. The parent is responsible for dismissing this
    /// sheet and presenting `MealScanFlow` — iOS won't show two sheets
    /// concurrently, so the parent has to sequence them.
    let onRequestPhotoFallback: () -> Void
    /// Day the Meals tab is showing. Logs land on it at the current
    /// clock time, so back-filling yesterday doesn't drop into today.
    var logDay: Date = Date()

    @State private var phase: Phase = .preflight
    @State private var product: ScannedProduct?
    @State private var portion: ScannedProduct.Portion = .grams(100)
    @State private var category: MealCategory = MealCategory.auto(for: Date())
    @State private var errorText: String?
    @State private var manualBarcode: String = ""
    @State private var recentlyScanned: [ScannedProduct] = []
    @State private var manualOverride: LoggableMeal?
    @State private var showEditSheet = false
    @State private var editingExactPortion = false
    @State private var loggedSnapshot: LoggedSnapshot?
    @State private var torchOn = false
    @State private var ocrPickerItem: PhotosPickerItem?
    /// Drives the "you just logged this 30 minutes ago — log again?"
    /// confirmation when the user re-scans the same barcode within
    /// a short window (audit Meals MED 7). Nil = no prompt pending.
    @State private var pendingDuplicateConfirm: (product: ScannedProduct, lastLoggedAt: Date)?
    /// What the barcode turned out to be when the food database didn't
    /// have it — a shampoo, a bag of dog food, a set of headphones. Nil
    /// while the sibling catalogues are still being asked, and nil for
    /// good if none of them recognise it either.
    @State private var identity: BarcodeIdentity?
    /// Set when the camera read something that isn't a product code at
    /// all — a QR code, a shipping label — so the screen can say what it
    /// was instead of blaming the scan.
    @State private var unsupportedPayload: BarcodePayload?
    @State private var isIdentifying = false
    /// Held so "Try another barcode" can cancel an in-flight
    /// identification instead of letting it land on the next scan's card.
    @State private var identifyTask: Task<Void, Never>?
    /// The barcode behind the current not-found card, so a package photo
    /// can be filed under it.
    @State private var lastBarcode: String?
    /// Atlas AI's price, portion and package reading of `product`.
    @State private var insight: MealScannerService.SmartScan?
    @State private var isLoadingInsight = false
    @State private var insightTask: Task<Void, Never>?
    @State private var lookupTask: Task<Void, Never>?
    /// True when `product` came from a package photo rather than the
    /// food database — changes the source badge and the logged source.
    @State private var productReadByAI = false
    /// Grows with the Nutri-Score letter so it never clips its circle.
    @ScaledMetric(relativeTo: .body) private var nutriScoreDiameter: CGFloat = 28
    @State private var nutritionEstimatedByAI = false
    @State private var savedToMyFoods = false
    @State private var isShowingPackageCamera = false
    @State private var packagePickerItem: PhotosPickerItem?
    /// A package photo held on the device until the user allows sending
    /// it to the AI (Guideline 5.1.2(i)).
    @State private var pendingPackageImage: UIImage?
    @State private var showPackageConsent = false
    @State private var showScanLimitPaywall = false
    /// Camera access was declined (not restricted), so Settings can fix it.
    @State private var cameraDenied = false
    @State private var storeService = StoreService.shared

    private enum Phase: Equatable {
        case preflight       // checking camera permission + device support
        case scanning        // DataScanner live
        case manualEntry     // simulator / unsupported devices type a code
        case lookingUp       // OFF network round-trip
        case ocrProcessing   // VisionKit text recognition on a label photo
        case review          // product + portion + macros
        case logged          // success screen with Undo
        case notFound        // barcode looked up cleanly but no product
        case unsupportedCode // read fine, but it isn't a product code at all
        case error           // any other terminal failure
    }

    /// Captures what was logged so the Undo button can reverse it
    /// exactly. Stored on the view so a re-render can't lose the
    /// reversal data while the success screen is up. Includes
    /// `barcode` + `portion` so Undo can also roll back the
    /// scan-history record (otherwise an undone scan still inflates
    /// the recents-row ranking and preselects the wrong portion next
    /// time).
    private struct LoggedSnapshot: Equatable {
        let productName: String
        let entryID: UUID
        let calories: Int
        let date: Date
        let barcode: String
        let portion: ScannedProduct.Portion
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Group {
                    switch phase {
                    case .preflight:        preflight
                    case .scanning:         scanner
                    case .manualEntry:      manualEntry
                    case .lookingUp:        lookingUp
                    case .ocrProcessing:    ocrProcessing
                    case .review:           reviewCard
                    case .logged:           loggedCard
                    case .notFound:         notFoundCard
                    case .unsupportedCode:  unsupportedCodeCard
                    case .error:            errorCard
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            .appAnimation(AppAnimation.springSmooth, value: phase)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColor.background)
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .task { await preflightCheck() }
        .task { await loadRecentlyScanned() }
        // Closing mid-lookup must not go on to spend a paid AI insight
        // call for a sheet that is gone.
        .onDisappear {
            lookupTask?.cancel()
            insightTask?.cancel()
            identifyTask?.cancel()
        }
        .confirmationDialog(
            "Already logged this recently",
            isPresented: Binding(
                get: { pendingDuplicateConfirm != nil },
                set: { newValue in
                    if !newValue { pendingDuplicateConfirm = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDuplicateConfirm
        ) { ctx in
            Button("Log again", role: .none) {
                if let meal = currentMacros(for: ctx.product) {
                    commitMealEntry(product: ctx.product, meal: meal)
                }
                pendingDuplicateConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDuplicateConfirm = nil
            }
        } message: { ctx in
            Text("You logged \(ctx.product.name) \(ctx.lastLoggedAt.formatted(.relative(presentation: .numeric, unitsStyle: .wide))). Log it again?")
        }
        .sheet(isPresented: $showEditSheet) {
            if let product {
                EditNutritionSheet(
                    productName: product.name,
                    initial: currentMacros(for: product),
                    onSave: { override in
                        manualOverride = override
                        showEditSheet = false
                    },
                    onCancel: { showEditSheet = false }
                )
            }
        }
        // The gram slider spans 5–2,000 g, too coarse to land on the 37 g
        // a label lists; typing it is the precise path, as in the library.
        .sheet(isPresented: $editingExactPortion) {
            if let product, let component = product.loggable(for: portion)?.components?.first {
                FoodPortionEditor(component: component) { portion = .grams($0) }
            }
        }
    }

    // MARK: - Phases

    private var preflight: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColor.accentLight)
            Text("Preparing camera…")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var scanner: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                BarcodeScannerView(
                    onDetected: { code in handleDetected(barcode: code) },
                    onError: { message in
                        errorText = message
                        phase = .error
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }

                BarcodeScannerOverlay(torchOn: $torchOn)
            }
            .frame(height: 320)
            .onDisappear {
                // Turn the torch back off when leaving the scanner —
                // it would otherwise stay on for the photo-capture
                // path or until the app loses the camera, which would
                // surprise the user.
                if torchOn {
                    torchOn = false
                    BarcodeTorch.set(false)
                }
            }

            Text("Hold a packaged food's barcode inside the frame.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            recentlyScannedRow
        }
    }

    @ViewBuilder
    private var recentlyScannedRow: some View {
        if !recentlyScanned.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Recently scanned")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, Spacing.xs)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(recentlyScanned, id: \.barcode) { product in
                            recentlyScannedTile(product)
                        }
                    }
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func recentlyScannedTile(_ product: ScannedProduct) -> some View {
        Button {
            handleDetected(barcode: product.barcode)
        } label: {
            VStack(spacing: Spacing.xs) {
                FoodThumbnail(name: product.name, imageURL: product.imageURL, size: 48)

                Text(product.name)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Re-log \(product.name)")
    }

    private var manualEntry: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "barcode.viewfinder")
                .font(AppFont.scaled(56, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.accentLight)

            Text("Type the barcode below the bars")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)

            if let errorText {
                // Camera was denied (or the device is unsupported) —
                // tell the user why they landed on manual entry so they
                // can re-enable in Settings or just type the code.
                Text(errorText)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            } else {
                Text("This device can't open the live scanner, so enter the digits manually.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            TextField("e.g. 5449000000996", text: $manualBarcode)
                .accessibilityLabel("Barcode number")
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(AppFont.scaled(20, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.textPrimary)
                .padding(Spacing.md)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }

            GlassButton(title: "Look up", style: .primary) {
                handleDetected(barcode: manualBarcode)
            }
            .disabled(manualBarcode.trimmingCharacters(in: .whitespaces).count < 8)

            if cameraDenied {
                openSettingsButton
            }
        }
    }

    private var openSettingsButton: some View {
        GlassButton(title: "Open Settings", icon: "gear", style: .secondary) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private var lookingUp: some View {
        // Skeleton-shimmer card matches the review-card destination
        // so the transition feels like the content materialised into
        // an already-staged container. Cuts perceived latency vs. a
        // bare ProgressView, especially on a slow network.
        BarcodeLookupSkeleton()
    }

    private var ocrProcessing: some View {
        // Reuse the same skeleton — Vision text recognition is local
        // and fast (~200-400ms on modern devices), but the user
        // benefits from the staged-card layout the same way they do
        // for the network lookup. Different message tells them what's
        // happening so the wait isn't ambiguous.
        VStack(spacing: Spacing.lg) {
            BarcodeLookupSkeleton()
            Text("Reading the label…")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private var reviewCard: some View {
        if let product {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    productHeader(product)
                    sourceBadge(for: product)
                    if manualOverride == nil {
                        portionPicker(for: product)
                    } else {
                        overrideNotice
                    }
                    if insight != nil || isLoadingInsight {
                        ProductInsightCard(
                            scan: insight,
                            isLoading: isLoadingInsight,
                            portionGrams: manualOverride == nil ? product.grams(for: portion) : nil,
                            onPickPortion: { grams in portion = .grams(grams) }
                        )
                    }
                    MealCategoryPicker(selection: $category)
                    macroPanel(for: product)
                    saveToMyFoodsButton(product)
                }
            }
            .scrollIndicators(.hidden)
            // Matches the photo scanner: the primary action reserves its own
            // space instead of sitting at the end of the scroll. The two
            // scanners are the same journey and were drifting apart.
            .pinnedFooter {
                actionButtons
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)
            }
        } else {
            errorCard            // defensive — phase guarantees product is set
        }
    }

    private func sourceBadge(for product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: productReadByAI || nutritionEstimatedByAI ? "sparkles" : "globe")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text(sourceLabel(for: product))
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 0)
            if manualOverride != nil {
                Text("✏ Edited")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.warning)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(AppColor.warning.opacity(0.15))
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xs)
    }

    private func sourceLabel(for product: ScannedProduct) -> LocalizedStringKey {
        if productReadByAI { return "Read from the package by Atlas AI" }
        if nutritionEstimatedByAI { return "Nutrition estimated by Atlas AI" }
        return "Open Food Facts · \(Self.relativeAge(product.fetchedAt))"
    }

    private var overrideNotice: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "pencil.circle.fill")
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Using your manual values")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Portion picker is paused while edits are active.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Reset") {
                manualOverride = nil
            }
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
            .minimumHitArea()
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.warning.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.warning.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private func productHeader(_ product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.md) {
            FoodThumbnail(name: product.name, imageURL: product.imageURL, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let brand = product.brand, brand != product.name {
                    Text(brand)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let score = product.nutriScore {
                nutriScorePill(score)
            }
        }
    }

    private func portionPicker(for product: ScannedProduct) -> some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("How much did you have?")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                PortionPicker(product: product, portion: $portion)
                Button("Enter exact grams") { editingExactPortion = true }
                    .minimumHitArea()
            }
        }
    }

    private func macroPanel(for product: ScannedProduct) -> some View {
        let meal = currentMacros(for: product)
        // Disable when no macros are available — otherwise the edit sheet
        // would open prefilled with all zeros and a hurried Save would
        // silently log a zero-calorie meal.
        let canEdit = meal != nil
        return VStack(alignment: .trailing, spacing: Spacing.xs) {
            MealScanTotalsCard(
                calories: meal?.calories ?? 0,
                proteinG: meal?.proteinG ?? 0,
                carbsG: meal?.carbsG ?? 0,
                fatG: meal?.fatG ?? 0
            )
            Button {
                showEditSheet = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "pencil")
                    Text("Edit nutrition")
                }
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(canEdit ? AppColor.accentLight : AppColor.textTertiary)
                .minimumHitArea()
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel("Edit nutrition manually")
            if manualOverride == nil && !product.hasNutrition {
                Text("No nutrition data for this product. Edit nutrition with the values from its label.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// An all-zero Open Food Facts record stays unloggable until the user
    /// enters the label values — logging it would add a silent 0 kcal row.
    private func canLog(_ product: ScannedProduct?) -> Bool {
        guard let product, currentMacros(for: product) != nil else { return false }
        return manualOverride != nil || product.hasNutrition
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.sm) {
            GlassButton(title: "Scan another", style: .secondary, isFullWidth: true) {
                resetForRescan()
            }

            GlassButton(title: addButtonTitle, style: .primary, isFullWidth: true) {
                confirm()
            }
            .disabled(!canLog(product))
        }
    }

    private var loggedCard: some View {
        VStack(spacing: Spacing.lg) {
            MilestoneArtwork(size: 64)

            Text(addedTitle)
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)

            if let snapshot = loggedSnapshot {
                // Calorie-ring micro-update: animates from
                // (today - just-logged) to today on appear, so the
                // user sees the meal's effect on today's target as
                // visceral feedback rather than a plain "420 kcal"
                // readout. The kcal target falls back to the
                // placeholder when no profile target is set.
                LoggedCaloriePanel(
                    productName: snapshot.productName,
                    deltaCalories: snapshot.calories,
                    totalCalories: dataStore.consumption(for: snapshot.date).caloriesKcal,
                    targetCalories: (dataStore.profile.nutritionTargets ?? .placeholder).calories,
                    date: snapshot.date
                )
            }

            VStack(spacing: Spacing.sm) {
                GlassButton(title: "Done", style: .primary, isFullWidth: true) { onClose() }

                GlassButton(title: "Undo", icon: "arrow.uturn.backward", style: .ghost) {
                    undoLastLog()
                }
            }
            .padding(.top, Spacing.sm)
        }
    }

    private var notFoundCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: identity == nil ? "questionmark.app.dashed" : "checkmark.seal.fill")
                .font(AppFont.scaled(48, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(identity == nil ? AppColor.accentLight : AppColor.positive)
            Text(notFoundHeadline)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            if let identity {
                identifiedArticleCard(identity)
            } else {
                Text("Open Food Facts doesn't know this product. Snap the nutrition label and we'll read it directly, or use the AI photo path for plates and meals.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                if isIdentifying {
                    identifyingRow
                }
            }
            VStack(spacing: Spacing.sm) {
                // Suppressed once we know the article is a shampoo or a
                // bag of dog food: offering to read a nutrition panel off
                // something that has none is the detail that tells a user
                // the app didn't understand what they scanned.
                if showsFoodFallbacks {
                    // Best fallback: Atlas AI reads the whole package —
                    // name, brand, net weight and nutrition panel — in
                    // one photo, and files it under this barcode.
                    packagePhotoButton

                    // On-device OCR of the nutrition
                    // panel. Free, fast, accurate when the photo is
                    // clean — no AI cost, no cloud round-trip.
                    PhotosPicker(
                        selection: $ocrPickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        // PhotosPicker owns its label, so it can't be a
                        // GlassButton — dress the label in the same capsule so
                        // the three options read as one set.
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(AppFont.scaled(13, weight: .semibold))
                            Text("Choose a label photo")
                                .font(AppFont.headline)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)
                        .frame(minHeight: Spacing.minimumHitTarget)
                        .foregroundStyle(AppColor.textSecondary)
                        .glassControl(
                            .capsule,
                            tint: AppColor.accentPrimary.opacity(0.18),
                            border: AppColor.glassBorderActive
                        )
                    }

                    // Secondary fallback: AI vision on a meal photo.
                    // Costs an API call; better for "what did I eat"
                    // (a plate of food) than "what's in this jar".
                    GlassButton(title: "Scan meal photo", icon: "camera.fill", style: .secondary) {
                        onRequestPhotoFallback()
                    }
                }

                GlassButton(title: "Try another barcode", style: .ghost) {
                    product = nil
                    manualBarcode = ""
                    errorText = nil
                    resetScanResults()
                    phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
                }
            }
            .padding(.top, Spacing.sm)
        }
        .appAnimation(AppAnimation.springSnappy, value: identity)
        .onChange(of: packagePickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    packagePickerItem = nil
                    errorText = String(localized: "Couldn't load that photo. Try a different one.")
                    phase = .error
                    return
                }
                packagePickerItem = nil
                await requestReadPackage(image)
            }
        }
        .sheet(isPresented: $showPackageConsent, onDismiss: {
            guard AIDataConsent.isGranted else {
                pendingPackageImage = nil
                return
            }
            if let image = pendingPackageImage {
                pendingPackageImage = nil
                Task { await readPackage(image) }
            } else {
                Task { await openPackageCamera() }
            }
        }) {
            AIConsentSheet(whatIsSent: "The photo of the package you take or pick.")
        }
        .sheet(isPresented: $showScanLimitPaywall) {
            PaywallView(source: .mealScanLimit)
                .environment(dataStore)
                .liquidGlassPresentation()
        }
        .fullScreenCover(isPresented: $isShowingPackageCamera) {
            CameraPicker(
                onPicked: { image in
                    isShowingPackageCamera = false
                    Task { await requestReadPackage(image) }
                },
                onCancel: { isShowingPackageCamera = false },
                cameraDevice: .rear,
                allowsEditing: false
            )
            .ignoresSafeArea()
        }
        .onChange(of: ocrPickerItem) { _, newValue in
            guard let newValue else { return }
            phase = .ocrProcessing
            Task { await runOCR(on: newValue) }
        }
    }

    /// Explicitly typed rather than a ternary inside `Text(...)`: two
    /// string literals in a ternary leave the compiler choosing between
    /// the `LocalizedStringKey` and `StringProtocol` overloads, and that
    /// ambiguity has already cost this codebase an afternoon of chasing
    /// an inference error reported thirty lines from its cause.
    private var notFoundHeadline: LocalizedStringKey {
        identity == nil ? "This barcode isn't in the food database yet" : "That's not a food"
    }

    /// Keeps the label-OCR and AI-photo escape hatches, unless we've
    /// positively identified the article as something with no human
    /// nutrition to read. Unknown barcodes keep both — the point of the
    /// identification is to remove nonsense options, not to remove the
    /// user's way forward.
    private var showsFoodFallbacks: Bool {
        identity?.catalogue.mayStillBeEdible ?? true
    }

    /// Shown while the sibling catalogues are being asked. Deliberately
    /// small and non-blocking — every button below it already works, so
    /// this is a note, not a gate.
    private var identifyingRow: some View {
        HStack(spacing: Spacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text("Checking non-food catalogs…")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    /// The answer to "what did I just scan, then?".
    ///
    /// Naming the article turns a dead end into a completed sentence:
    /// the scanner read the barcode correctly, this is what it is, and
    /// here is why it isn't going in your diary. The fallbacks below
    /// stay exactly where they were, because a product the general
    /// catalogue lists as "peanut butter" may still be something the
    /// user genuinely wants to log from its label.
    private func identifiedArticleCard(_ identity: BarcodeIdentity) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: identity.catalogue.icon)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text(identity.displayTitle)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(identity.catalogue.reasonNotLoggable)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Identified via \(identity.catalogue.displayName)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// For a code that read perfectly and simply isn't a product code.
    ///
    /// The camera accepts every symbology iOS supports, so QR codes,
    /// shipping labels and ticket codes all scan cleanly and then hit a
    /// validator that wants digits. Telling the user "that barcode
    /// doesn't look right" blames them for a scan that worked. Naming
    /// what it read, and what a product barcode looks like instead, is
    /// the difference between a dead end and a correction.
    private var unsupportedCodeCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "qrcode.viewfinder")
                .font(AppFont.scaled(48, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.accentLight)
            Text("That's not a product barcode")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(unsupportedCodeDetail)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            Text("Product barcodes are the striped ones with the digits printed underneath.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                GlassButton(title: "Scan another code", style: .primary) {
                    errorText = nil
                    resetScanResults()
                    phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
                }
                GlassButton(title: "Scan meal photo", icon: "camera.fill", style: .secondary) {
                    onRequestPhotoFallback()
                }
            }
            .padding(.top, Spacing.sm)
        }
    }

    /// Says what was read without ever echoing it at length — a scanned
    /// payload is arbitrary external content, so it gets truncated and
    /// stays inside quotation marks rather than being presented as the
    /// app's own copy.
    private var unsupportedCodeDetail: String {
        let unreadable = String(localized: "The camera read it cleanly, but there's no product code in it.")
        guard let unsupportedPayload else { return unreadable }
        switch unsupportedPayload {
        case .link(let url):
            return String(localized: "It's a QR code pointing to \(url.host ?? url.absoluteString).")
        case .text(let raw):
            let shown = raw.count > 40 ? String(raw.prefix(40)) + "…" : raw
            return String(localized: "It reads “\(shown)” — a label or tracking code rather than a product.")
        case .gtin:
            return unreadable
        }
    }

    /// Camera when there is one (scanning already got permission),
    /// else the photo library — simulators and manual-entry devices.
    @ViewBuilder
    private var packagePhotoButton: some View {
        if UIImagePickerController.SourceType.cameraIsAvailable {
            GlassButton(title: "Photograph the package", icon: "sparkles", style: .primary) {
                guard !scanLimitReached() else { return }
                // Ask before the camera opens, so the consent sheet never
                // has to present over a dismissing camera.
                guard AIDataConsent.isGranted else {
                    showPackageConsent = true
                    return
                }
                Task { await openPackageCamera() }
            }
        } else {
            PhotosPicker(selection: $packagePickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Pick a photo of the package", systemImage: "sparkles")
                    .font(AppFont.headline)
                    .frame(minHeight: Spacing.minimumHitTarget)
            }
        }
    }

    /// Keeps a product the user logs often one search away in My Foods,
    /// with Atlas AI's price attached when it has one.
    private func saveToMyFoodsButton(_ product: ScannedProduct) -> some View {
        Button {
            let item = insight?.items.first
            let pricePer100g = item.flatMap { $0.price?.scaled(by: 100 / $0.grams) }
            dataStore.saveCustomFood(SmartFoodLogic.customFood(from: product, pricePer100g: pricePer100g))
            savedToMyFoods = true
            Haptics.success()
        } label: {
            Label(saveToMyFoodsTitle, systemImage: savedToMyFoods ? "checkmark" : "bookmark")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(savedToMyFoods ? AppColor.accentPrimary : AppColor.accentLight)
        }
        .buttonStyle(.plain)
        .minimumHitArea()
        .disabled(savedToMyFoods)
    }

    private var saveToMyFoodsTitle: LocalizedStringKey {
        savedToMyFoods ? "Saved to My Foods" : "Save to My Foods"
    }

    private var errorCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.scaled(40, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.destructive)
            Text("Couldn't add this product")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(errorText ?? "Unknown error")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            VStack(spacing: Spacing.sm) {
                if cameraDenied {
                    openSettingsButton
                }

                GlassButton(title: "Try again", style: .primary) {
                    errorText = nil
                    product = nil
                    manualBarcode = ""
                    resetScanResults()
                    phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
                }

                if BarcodeScannerView.canScan {
                    GlassButton(title: "Type the code", icon: "keyboard", style: .secondary) {
                        errorText = nil
                        product = nil
                        resetScanResults()
                        phase = .manualEntry
                    }
                }

                // Network / rate-limit / decode failures shouldn't trap
                // the user — give them the same photo escape hatch the
                // notFound card offers.
                GlassButton(title: "Scan meal photo", icon: "camera.fill", style: .secondary) {
                    onRequestPhotoFallback()
                }
            }
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Small components

    private func nutriScorePill(_ score: String) -> some View {
        let palette = Self.nutriScorePalette(score)
        return Text(score.uppercased())
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(palette.ink)
            .frame(width: nutriScoreDiameter, height: nutriScoreDiameter)
            .background {
                Circle().fill(palette.fill)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nutri-Score \(score.uppercased())")
            .accessibilityHint("A through E rating of overall nutritional quality, where A is best.")
    }

    // MARK: - Helpers

    /// Fill and letter colour together: near-white is under 3:1 on the
    /// light B and C fills, so those take a fixed dark ink.
    private static func nutriScorePalette(_ score: String) -> (fill: Color, ink: Color) {
        let darkInk = Color(hex: 0x111114)
        switch score.lowercased() {
        case "a":  return (Color(red: 0.16, green: 0.59, blue: 0.27), AppColor.onAccent)
        case "b":  return (Color(red: 0.51, green: 0.74, blue: 0.21), darkInk)
        case "c":  return (Color(red: 0.96, green: 0.78, blue: 0.18), darkInk)
        case "d":  return (Color(red: 0.94, green: 0.49, blue: 0.18), AppColor.onAccent)
        case "e":  return (Color(red: 0.86, green: 0.20, blue: 0.18), AppColor.onAccent)
        default:   return (AppColor.textSecondary, AppColor.onAccent)
        }
    }

    private var isLoggingToday: Bool { Calendar.current.isDateInToday(logDay) }

    private var addButtonTitle: LocalizedStringKey {
        isLoggingToday ? "Add to today" : "Add to \(MealDaySwitcher.inlineTitle(for: logDay))"
    }

    private var addedTitle: LocalizedStringKey {
        isLoggingToday ? "Added to today" : "Added to \(MealDaySwitcher.inlineTitle(for: logDay))"
    }

    // MARK: - Actions

    private func preflightCheck() async {
        let outcome = await CameraAuthorization.resolve()
        switch outcome {
        case .granted:
            phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
        case .denied, .restricted:
            cameraDenied = outcome == .denied
            errorText = String(localized: "Camera access is off. Enable it in Settings to scan barcodes, or type a code below.")
            phase = .manualEntry
        }
    }

    private func handleDetected(barcode: String) {
        // Guard against rapid double-fires: the live scanner stops
        // after one detection, but the recently-scanned tiles can
        // trigger this from any phase. Only start a new lookup when
        // we're actually waiting for one.
        guard phase == .scanning || phase == .manualEntry else { return }
        resetScanResults()

        // Classification is pure string work, so deciding here rather
        // than inside the network task keeps a QR code from flashing the
        // lookup skeleton on its way to a screen that never needed one.
        let payload = BarcodePayload.classify(barcode)
        guard case .gtin(let candidates) = payload else {
            unsupportedPayload = payload
            phase = .unsupportedCode
            BarcodeHaptics.lookupFailure()
            return
        }

        phase = .lookingUp
        lookupTask?.cancel()
        lookupTask = Task { await lookupProduct(candidates: candidates) }
    }

    /// OCR fallback: load the picked image, run on-device text
    /// recognition, parse the panel, hand the synthetic
    /// `ScannedProduct` to the existing review flow. The result
    /// carries an `ocr:<uuid>` synthetic barcode so it doesn't pollute
    /// the OFF cache or the recents row, and history-based portion
    /// restore is intentionally skipped (each OCR scan is unique).
    private func runOCR(on item: PhotosPickerItem) async {
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                await MainActor.run {
                    errorText = String(localized: "Couldn't load that photo. Try a different one.")
                    phase = .error
                    ocrPickerItem = nil
                }
                return
            }
            let recognised = try await NutritionLabelOCR.recognize(image: image)
            await MainActor.run {
                product = recognised
                portion = recognised.defaultPortion
                category = MealCategory.auto(for: LifestyleDataLogic.logTimestamp(on: logDay))
                phase = .review
                ocrPickerItem = nil
                BarcodeHaptics.lookupSuccess()
            }
        } catch let ocrError as NutritionLabelOCR.OCRError {
            await MainActor.run {
                errorText = ocrError.errorDescription
                phase = .error
                ocrPickerItem = nil
                BarcodeHaptics.lookupFailure()
            }
        } catch {
            AppLog.diagnostics.error("Nutrition label OCR failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                errorText = String(localized: "Couldn't read that label. Try a sharper photo of the nutrition panel.")
                phase = .error
                ocrPickerItem = nil
                BarcodeHaptics.lookupFailure()
            }
        }
    }

    /// Tries each GTIN form in turn.
    ///
    /// A miss on the scanned form is not the end of it: the same product
    /// is often filed under its 13-digit or 12-digit twin, and a case
    /// code's inner GTIN is a different string again. Only when every
    /// form comes back empty is this genuinely a not-found. Any other
    /// failure — offline, rate-limited, a bad gateway — stops the walk
    /// immediately, because retrying the same outage under a different
    /// number just spends the user's time.
    private func lookupProduct(candidates: [String]) async {
        // Never leave the caller on the loading skeleton: an empty list
        // would fall out of the loop below without ever setting a phase.
        guard let primary = candidates.first else {
            await MainActor.run {
                errorText = OpenFoodFactsService.LookupError.invalidBarcode.errorDescription
                phase = .error
                BarcodeHaptics.lookupFailure()
            }
            return
        }

        await MainActor.run { lastBarcode = primary }
        for (index, candidate) in candidates.enumerated() {
            do {
                try await lookupOne(barcode: candidate)
                return
            } catch let lookupError as OpenFoodFactsService.LookupError {
                let isLastCandidate = index == candidates.count - 1
                guard lookupError == .notFound, !isLastCandidate else {
                    await MainActor.run {
                        errorText = lookupError.errorDescription
                        phase = (lookupError == .notFound) ? .notFound : .error
                        BarcodeHaptics.lookupFailure()
                        if lookupError == .notFound {
                            // A clean miss means the barcode scanned fine
                            // and Open Food Facts simply has no food under
                            // it — which is exactly what a non-food article
                            // looks like. Ask the sibling catalogues what
                            // it actually is, in the background, while the
                            // card is already on screen.
                            startIdentifying(barcode: primary)
                        }
                    }
                    return
                }
            } catch {
                AppLog.diagnostics.error("Barcode lookup failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    errorText = String(localized: "Couldn't look up this product. Check your connection and try again.")
                    phase = .error
                    BarcodeHaptics.lookupFailure()
                }
                return
            }
        }
    }

    /// One round-trip for one GTIN form. Throws so the walk above can
    /// decide whether a miss is worth another form or is the final word.
    private func lookupOne(barcode: String) async throws {
        let result = try await OpenFoodFactsService.shared.fetch(barcode: barcode)
        // History-aware default: if the user has logged this barcode
        // before, restore their previous portion choice. Falls through
        // to the product's own default for first-time scans. The lookup
        // is async (actor read), so it happens here before we hop to
        // main.
        let remembered = await BarcodeScanHistory.shared.lastPortion(for: result.barcode)
        try Task.checkCancellation()
        await MainActor.run {
            product = result
            productReadByAI = result.readFromPackage == true
            portion = remembered ?? result.defaultPortion
            category = MealCategory.auto(for: LifestyleDataLogic.logTimestamp(on: logDay))
            phase = .review
            BarcodeHaptics.lookupSuccess()
            startInsight(for: result)
        }
    }

    /// Asks Atlas AI for price, portions and any missing package facts
    /// while the user is already looking at the review. Failure is
    /// silent: the card disappears and the review is exactly what it was.
    private func startInsight(for result: ScannedProduct) {
        insightTask?.cancel()
        insight = nil
        // Product facts only, but still nothing goes to the AI before the
        // user has said yes to it once.
        guard AIDataConsent.isGranted else { return }
        isLoadingInsight = true
        let corrections = ScanCorrectionMemory.shared.recent
        insightTask = Task {
            let scan = try? await MealScannerService.shared.describeProduct(.init(product: result), corrections: corrections)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isLoadingInsight = false
                guard let scan, product?.barcode == result.barcode else { return }
                insight = scan
                let filled = SmartFoodLogic.product(result, fillingFrom: scan)
                nutritionEstimatedByAI = !result.hasNutrition && filled.hasNutrition
                product = filled
            }
        }
    }

    private func openPackageCamera() async {
        let outcome = await CameraAuthorization.resolve()
        cameraDenied = outcome == .denied
        if outcome == .granted {
            isShowingPackageCamera = true
        } else {
            errorText = String(localized: "Allow camera access in Settings to photograph the package.")
            phase = .error
        }
    }

    /// A package read is a paid photo scan, so it spends the same weekly
    /// allowance as a meal photo.
    private func scanLimitReached() -> Bool {
        guard MealScanQuota.remainingThisWeek(isPro: storeService.isProUser) == 0 else { return false }
        showScanLimitPaywall = true
        return true
    }

    private func requestReadPackage(_ image: UIImage) async {
        guard !scanLimitReached() else { return }
        guard AIDataConsent.isGranted else {
            pendingPackageImage = image
            showPackageConsent = true
            return
        }
        await readPackage(image)
    }

    /// Package photo → product, for a barcode the database doesn't know.
    /// Lands on the same review as a database hit, filed under the
    /// scanned barcode so history and re-scans line up.
    private func readPackage(_ image: UIImage) async {
        let barcode = lastBarcode ?? "ai:\(UUID().uuidString)"
        let corrections = ScanCorrectionMemory.shared.recent
        await MainActor.run {
            identifyTask?.cancel()
            phase = .ocrProcessing
        }
        do {
            let scan = try await MealScannerService.shared.smartScan(
                image: image,
                hint: "A packaged product whose barcode \(barcode) isn't in Open Food Facts. Read the brand, product name, net weight and nutrition panel from the package.",
                corrections: corrections,
                metered: true
            )
            guard let read = SmartFoodLogic.product(from: scan, barcode: barcode) else {
                throw MealScannerService.ScanError.noFoodDetected
            }
            await OpenFoodFactsService.shared.remember(read)
            await MainActor.run {
                if !storeService.isProUser { MealScanQuota.recordSuccessfulScan() }
                product = read
                insight = scan
                productReadByAI = true
                portion = read.defaultPortion
                category = MealCategory.auto(for: LifestyleDataLogic.logTimestamp(on: logDay))
                phase = .review
                BarcodeHaptics.lookupSuccess()
            }
        } catch {
            await MainActor.run {
                errorText = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Couldn't read this package. Check your connection and try again.")
                phase = .error
                BarcodeHaptics.lookupFailure()
                // The proxy's count outlives a reinstall; agree with it.
                if case .scanAllowanceSpent = error as? MealScannerService.ScanError {
                    MealScanQuota.recordAllowanceExhausted()
                    showScanLimitPaywall = !storeService.isProUser
                }
            }
        }
    }

    /// Best-effort "what is this thing, then?" for a barcode the food
    /// database missed. Purely additive — while it runs the not-found
    /// card is fully usable, and if it comes back empty the card is
    /// exactly what it always was.
    private func startIdentifying(barcode: String) {
        identifyTask?.cancel()
        identity = nil
        isIdentifying = true
        identifyTask = Task {
            let found = await BarcodeIdentityService.shared.identify(barcode: barcode)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                identity = found
                isIdentifying = false
            }
        }
    }

    /// Clears everything the previous scan concluded — the sibling-
    /// catalogue answer and the "that wasn't a product code" payload —
    /// so a stale result can't surface over the next scan.
    private func resetScanResults() {
        identifyTask?.cancel()
        identifyTask = nil
        insightTask?.cancel()
        insightTask = nil
        insight = nil
        isLoadingInsight = false
        productReadByAI = false
        nutritionEstimatedByAI = false
        savedToMyFoods = false
        identity = nil
        isIdentifying = false
        unsupportedPayload = nil
    }

    private func confirm() {
        // Re-entrancy guard: belt-and-suspenders for the single-button
        // happy path. Stops a programmatic double-call (e.g. a future
        // shortcut intent) from logging twice while only being able
        // to undo once.
        guard phase == .review,
              canLog(product),
              let product,
              let meal = currentMacros(for: product) else { return }
        // Duplicate-scan guard (audit Meals MED 7): if the same
        // barcode was logged in the past 60 minutes, surface a
        // confirmation prompt instead of silently appending a
        // second identical row. The user can confirm "yes log it
        // again" — sometimes a re-scan is intentional (second
        // helping at the same meal).
        if let lastLoggedAt = recentlyLoggedAt(barcode: product.barcode, within: 3600) {
            pendingDuplicateConfirm = (product, lastLoggedAt)
            return
        }
        commitMealEntry(product: product, meal: meal)
    }

    /// Returns the most-recent `logged` timestamp for a MealEntry that
    /// referenced `barcode` within the window — nil when no match.
    /// Used to drive the duplicate-scan confirmation dialog.
    private func recentlyLoggedAt(barcode: String, within seconds: TimeInterval) -> Date? {
        let cutoff = Date().addingTimeInterval(-seconds)
        return dataStore.profile.mealHistory
            .filter { $0.sourceID == barcode && $0.date >= cutoff }
            .map(\.date)
            .max()
    }

    /// Commits the meal entry to DataStore. Extracted from the body
    /// of confirm() so the duplicate-scan confirmation dialog can
    /// call it directly when the user picks "Log again".
    private func commitMealEntry(product: ScannedProduct, meal: LoggableMeal) {
        let now = Date()
        let loggedAt = LifestyleDataLogic.logTimestamp(on: logDay, now: now)
        // A package read by Atlas AI is a photo scan whether or not it
        // was filed under a real barcode. OCR-synthesised products carry
        // an `ocr:<uuid>` barcode and come from on-device Vision, not
        // Open Food Facts, and manual-override edits are likewise not OFF
        // data — both are `.manual`. Synthetic `ocr:`/`ai:` barcodes skip
        // history: recordLog expects an 8-14 digit code.
        let hasSyntheticBarcode = product.barcode.hasPrefix("ocr:") || product.barcode.hasPrefix("ai:")
        let source: MealSource = productReadByAI ? .photo
            : (manualOverride != nil || hasSyntheticBarcode) ? .manual : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: category,
            source: source,
            sourceID: product.barcode,
            date: loggedAt
        )
        dataStore.logMealEntry(entry)
        // .logCommitted carries a heavier impact than the lookup
        // success — the user feels "I just logged a meal" as a
        // distinct beat from "I just scanned a barcode".
        BarcodeHaptics.logCommitted()
        loggedSnapshot = LoggedSnapshot(
            productName: product.name,
            entryID: entry.id,
            calories: meal.calories,
            date: loggedAt,
            barcode: product.barcode,
            portion: portion
        )
        // Record the scan + portion choice in history so the recents
        // row re-ranks and the next re-scan of this product preselects
        // the same portion. Fire-and-forget — UI doesn't need to wait.
        // Skip OCR scans: each carries a unique synthetic barcode, so a
        // history record would never re-match and would corrupt the actor.
        if !hasSyntheticBarcode {
            let recordedBarcode = product.barcode
            let recordedPortion = portion
            Task {
                await BarcodeScanHistory.shared.recordLog(
                    barcode: recordedBarcode,
                    portion: recordedPortion,
                    at: now
                )
            }
        }
        phase = .logged
    }

    private func undoLastLog() {
        guard let snapshot = loggedSnapshot else {
            onClose()
            return
        }
        phase = .review
        dataStore.unlogMealEntry(id: snapshot.entryID)
        // Roll back the scan-history record too so an undone scan
        // doesn't inflate the recents ranking or preselect the wrong
        // portion next time. Fire-and-forget — UI is closing anyway.
        let undoneBarcode = snapshot.barcode
        Task { await BarcodeScanHistory.shared.undoLog(barcode: undoneBarcode) }
        BarcodeHaptics.logUndone()
        onClose()
    }

    private func resetForRescan() {
        resetScanResults()
        product = nil
        manualBarcode = ""
        manualOverride = nil
        portion = .grams(100)
        phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
        // Refresh the row so the product the user just scanned shows
        // up next time. The cache write happens during the OFF fetch,
        // so by now the new entry is on disk.
        Task { await loadRecentlyScanned() }
    }

    /// Resolves the macros to log: manual override wins if set, else
    /// fall back to the portion-scaled product macros. Returns nil
    /// when both paths produce nothing, which keeps the "Add to today"
    /// button correctly disabled.
    private func currentMacros(for product: ScannedProduct?) -> LoggableMeal? {
        if let override = manualOverride { return override }
        return product?.loggable(for: portion)
    }

    private func loadRecentlyScanned() async {
        // Pull more than `limit` candidates from the cache, then rank
        // by `BarcodeScanHistory`'s recency × frequency score and take
        // the top 5. Means the protein bar a user scans every morning
        // stays in the row even when a one-off product was scanned
        // more recently. Products with no log history (cache-only,
        // never confirmed) score 0 and sink to the end.
        let candidates = await OpenFoodFactsService.shared.recent(limit: 20)
        guard !candidates.isEmpty else {
            recentlyScanned = []
            return
        }
        let scores = await BarcodeScanHistory.shared.scores(for: candidates.map(\.barcode))
        recentlyScanned = candidates
            .sorted { (scores[$0.barcode] ?? 0) > (scores[$1.barcode] ?? 0) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Helpers

    // Swift 6 needs the explicit escape hatch because the formatter
    // type is not Sendable, while SwiftUI Views are. Effectively
    // read-only after init, so the unsafe annotation is sound.
    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relativeAge(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// `Portion.isServings` and `.isGrams` are now defined as an
// extension on `ScannedProduct.Portion` itself in
// `Models/ScannedProduct.swift` — single source of truth for both
// scanners.
