import SwiftUI
@preconcurrency import AVFoundation
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
    /// Fired when the user taps "Snap a photo instead" on the
    /// not-found screen. The parent is responsible for dismissing this
    /// sheet and presenting `MealScanFlow` — iOS won't show two sheets
    /// concurrently, so the parent has to sequence them.
    let onRequestPhotoFallback: () -> Void

    @State private var phase: Phase = .preflight
    @State private var product: ScannedProduct?
    @State private var portion: ScannedProduct.Portion = .grams(100)
    @State private var category: MealCategory = MealCategory.auto(for: Date())
    @State private var errorText: String?
    @State private var manualBarcode: String = ""
    @State private var recentlyScanned: [ScannedProduct] = []
    @State private var manualOverride: LoggableMeal?
    @State private var showEditSheet = false
    @State private var loggedSnapshot: LoggedSnapshot?
    @State private var torchOn = false
    @State private var ocrPickerItem: PhotosPickerItem?

    private enum Phase: Equatable {
        case preflight       // checking camera permission + device support
        case scanning        // DataScanner live
        case manualEntry     // simulator / unsupported devices type a code
        case lookingUp       // OFF network round-trip
        case ocrProcessing   // VisionKit text recognition on a label photo
        case review          // product + portion + macros
        case logged          // success screen with Undo + auto-close
        case notFound        // barcode looked up cleanly but no product
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
                switch phase {
                case .preflight:        preflight
                case .scanning:         scanner
                case .manualEntry:      manualEntry
                case .lookingUp:        lookingUp
                case .ocrProcessing:    ocrProcessing
                case .review:           reviewCard
                case .logged:           loggedCard
                case .notFound:         notFoundCard
                case .error:            errorCard
                }
            }
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
        .preferredColorScheme(.dark)
        .task { await preflightCheck() }
        .task { await loadRecentlyScanned() }
        // SwiftUI-owned auto-close. Re-running on phase changes
        // cancels the previous task automatically, so leaving the
        // .logged screen (via Undo, Done, or swipe-dismiss) cleanly
        // stops the timer without any manual cancel bookkeeping.
        .task(id: phase) {
            guard phase == .logged else { return }
            try? await Task.sleep(for: AppAnimation.logSuccessAutoCloseDelay)
            // Re-check phase after the sleep — a user tap on Undo or
            // Done that lands in the final window before the timer
            // fires would otherwise double-call `onClose()`.
            guard !Task.isCancelled, phase == .logged else { return }
            onClose()
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
                    .font(AppFont.caption)
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
                AsyncImage(url: product.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .frame(width: 48, height: 48)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                }

                Text(product.name)
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppColor.accentLight)

            Text("Type the barcode below the bars")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)

            if let errorText {
                // Camera was denied (or the device is unsupported) —
                // tell the user why they landed on manual entry so they
                // can re-enable in Settings or just type the code.
                Text(errorText)
                    .font(AppFont.caption)
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
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
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

            Button("Look up") {
                handleDetected(barcode: manualBarcode)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .disabled(manualBarcode.trimmingCharacters(in: .whitespaces).count < 8)
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
                .font(AppFont.caption)
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
                    MealCategoryPicker(selection: $category)
                    macroPanel(for: product)
                    actionButtons
                }
            }
            .scrollIndicators(.hidden)
        } else {
            errorCard            // defensive — phase guarantees product is set
        }
    }

    private func sourceBadge(for product: ScannedProduct) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "globe")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text("Open Food Facts · \(Self.relativeAge(product.fetchedAt))")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: 0)
            if manualOverride != nil {
                Text("✏ Edited")
                    .font(.system(size: 11, weight: .heavy))
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

    private var overrideNotice: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Using your manual values")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Portion picker is paused while edits are active.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Reset") {
                manualOverride = nil
            }
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.accentLight)
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
            AsyncImage(url: product.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 56, height: 56)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                if let brand = product.brand, brand != product.name {
                    Text(brand)
                        .font(AppFont.caption)
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

                HStack(spacing: Spacing.sm) {
                    if product.servingGrams != nil {
                        modeChip(title: "Serving", isActive: portion.isServings) {
                            portion = .servings(1)
                        }
                    }
                    if product.packageGrams != nil {
                        modeChip(title: "Whole pack", isActive: portion == .wholePackage) {
                            portion = .wholePackage
                        }
                    }
                    modeChip(title: "Grams", isActive: portion.isGrams) {
                        portion = .grams(100)
                    }
                }

                portionControl(for: product)
            }
        }
    }

    @ViewBuilder
    private func portionControl(for product: ScannedProduct) -> some View {
        switch portion {
        case .servings(let count):
            HStack {
                Stepper(
                    value: Binding(
                        get: { count },
                        set: { portion = .servings($0) }
                    ),
                    in: 0.5...10,
                    step: 0.5
                ) {
                    HStack(spacing: 4) {
                        Text(formatServings(count))
                            .font(AppFont.title2)
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textPrimary)
                        Text(count == 1 ? "serving" : "servings")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .tint(AppColor.accentPrimary)
            }
            if let label = product.servingSizeText {
                Text("1 serving = \(label)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

        case .wholePackage:
            HStack {
                Text("Entire package")
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if let g = product.packageGrams {
                    Text("\(Int(g.rounded())) g")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
            }

        case .grams(let g):
            VStack(spacing: Spacing.sm) {
                HStack(spacing: 4) {
                    Text("\(Int(g.rounded()))")
                        .font(AppFont.title2)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text("g")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                }
                Slider(value: Binding(
                    get: { g },
                    set: { portion = .grams($0) }
                ), in: 10...2000, step: 5)
                .tint(AppColor.accentPrimary)
                HStack(spacing: Spacing.xs) {
                    ForEach([50.0, 100.0, 200.0, 500.0], id: \.self) { quick in
                        Button("\(Int(quick))g") { portion = .grams(quick) }
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentLight)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background {
                                Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                            }
                    }
                }
            }
        }
    }

    private func macroPanel(for product: ScannedProduct) -> some View {
        let meal = currentMacros(for: product)
        return GlassCard(tinted: true, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Nutrition")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                // Disable when no macros are available — otherwise the
                // edit sheet would open prefilled with all zeros and a
                // hurried Save would silently log a zero-calorie meal.
                let canEdit = meal != nil
                Button {
                    showEditSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canEdit ? AppColor.accentLight : AppColor.textSecondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
                .accessibilityLabel("Edit nutrition manually")
            }
            Divider().background(AppColor.glassBorder)
            macroRow(label: "Calories", value: "\(meal?.calories ?? 0) kcal")
            macroRow(label: "Protein",  value: "\(meal?.proteinG ?? 0) g")
            macroRow(label: "Carbs",    value: "\(meal?.carbsG ?? 0) g")
            macroRow(label: "Fat",      value: "\(meal?.fatG ?? 0) g")
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.sm) {
            Button("Scan another") {
                resetForRescan()
            }
            .buttonStyle(.bordered)
            .tint(AppColor.textSecondary)

            Button("Add to today") {
                confirm()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .disabled(currentMacros(for: product) == nil)
        }
    }

    private var loggedCard: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)

            Text("Added to today")
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
                    totalCalories: dataStore.consumption().caloriesKcal,
                    targetCalories: (dataStore.profile.nutritionTargets ?? .placeholder).calories
                )
            }

            VStack(spacing: Spacing.sm) {
                Button {
                    undoLastLog()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.destructive.opacity(0.85))

                Button("Done") { onClose() }
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, Spacing.sm)
        }
    }

    private var notFoundCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColor.accentLight)
            Text("This barcode isn't in the food database yet")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Open Food Facts doesn't know this product. Snap the nutrition label and we'll read it directly, or use the AI photo path for plates and meals.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            VStack(spacing: Spacing.sm) {
                // Primary fallback: on-device OCR of the nutrition
                // panel. Free, fast, accurate when the photo is
                // clean — no AI cost, no cloud round-trip.
                PhotosPicker(
                    selection: $ocrPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "doc.text.viewfinder")
                        Text("Scan the nutrition label")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentPrimary)

                // Secondary fallback: AI vision on a meal photo.
                // Costs an API call; better for "what did I eat"
                // (a plate of food) than "what's in this jar".
                Button {
                    onRequestPhotoFallback()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "camera.fill")
                        Text("Use the AI meal scanner")
                    }
                }
                .buttonStyle(.bordered)
                .tint(AppColor.accentLight)

                Button("Try another barcode") {
                    product = nil
                    manualBarcode = ""
                    errorText = nil
                    phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
                }
                .buttonStyle(.bordered)
                .tint(AppColor.textSecondary)
            }
            .padding(.top, Spacing.sm)
        }
        .onChange(of: ocrPickerItem) { _, newValue in
            guard let newValue else { return }
            phase = .ocrProcessing
            Task { await runOCR(on: newValue) }
        }
    }

    private var errorCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
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
                Button("Try again") {
                    errorText = nil
                    product = nil
                    manualBarcode = ""
                    phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentPrimary)

                // Network / rate-limit / decode failures shouldn't trap
                // the user — give them the same photo escape hatch the
                // notFound card offers.
                Button("Snap a photo instead") {
                    onRequestPhotoFallback()
                }
                .buttonStyle(.bordered)
                .tint(AppColor.textSecondary)
            }
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Small components

    private func modeChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? AppColor.textPrimary : AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)        // HIG minimum tap target
                .background {
                    Capsule()
                        .fill(isActive ? AppColor.accentPrimary.opacity(0.25) : Color.clear)
                        .overlay {
                            Capsule().strokeBorder(
                                isActive ? AppColor.accentPrimary.opacity(0.55) : AppColor.glassBorder,
                                lineWidth: 1
                            )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func nutriScorePill(_ score: String) -> some View {
        Text(score.uppercased())
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(Self.nutriScoreColor(score))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nutri-Score \(score.uppercased())")
            .accessibilityHint("A through E rating of overall nutritional quality, where A is best.")
    }

    private func macroRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    // MARK: - Helpers

    private static func nutriScoreColor(_ score: String) -> Color {
        switch score.lowercased() {
        case "a":  Color(red: 0.16, green: 0.59, blue: 0.27)
        case "b":  Color(red: 0.51, green: 0.74, blue: 0.21)
        case "c":  Color(red: 0.96, green: 0.78, blue: 0.18)
        case "d":  Color(red: 0.94, green: 0.49, blue: 0.18)
        case "e":  Color(red: 0.86, green: 0.20, blue: 0.18)
        default:   AppColor.textSecondary
        }
    }

    private func formatServings(_ count: Double) -> String {
        count.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", count)
            : String(format: "%.1f", count)
    }

    // MARK: - Actions

    private func preflightCheck() async {
        let status = await BarcodeCameraAuthorization.request()
        await MainActor.run {
            switch status {
            case .authorized:
                phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
            case .denied, .restricted:
                errorText = "Camera access is off. Enable it in Settings to scan barcodes, or type a code below."
                phase = .manualEntry
            case .notDetermined:
                // Shouldn't happen — request() resolves notDetermined —
                // but if it somehow does, falling back to manual entry
                // is still a working path.
                phase = .manualEntry
            @unknown default:
                phase = .manualEntry
            }
        }
    }

    private func handleDetected(barcode: String) {
        // Guard against rapid double-fires: the live scanner stops
        // after one detection, but the recently-scanned tiles can
        // trigger this from any phase. Only start a new lookup when
        // we're actually waiting for one.
        guard phase == .scanning || phase == .manualEntry else { return }
        phase = .lookingUp
        Task { await lookup(barcode: barcode) }
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
                    errorText = "Couldn't load that photo. Try a different one."
                    phase = .error
                    ocrPickerItem = nil
                }
                return
            }
            let recognised = try await NutritionLabelOCR.recognize(image: image)
            await MainActor.run {
                product = recognised
                portion = recognised.defaultPortion
                category = MealCategory.auto(for: Date())
                phase = .review
                ocrPickerItem = nil
                if dataStore.profile.hapticFeedbackEnabled {
                    BarcodeHaptics.lookupSuccess()
                }
            }
        } catch let ocrError as NutritionLabelOCR.OCRError {
            await MainActor.run {
                errorText = ocrError.errorDescription
                phase = .error
                ocrPickerItem = nil
                if dataStore.profile.hapticFeedbackEnabled {
                    BarcodeHaptics.lookupFailure()
                }
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                phase = .error
                ocrPickerItem = nil
                if dataStore.profile.hapticFeedbackEnabled {
                    BarcodeHaptics.lookupFailure()
                }
            }
        }
    }

    private func lookup(barcode: String) async {
        do {
            let result = try await OpenFoodFactsService.shared.fetch(barcode: barcode)
            // History-aware default: if the user has logged this
            // barcode before, restore their previous portion choice.
            // Falls through to the product's own default for first-
            // time scans. The lookup is async (actor read), so it
            // happens here before we hop to main.
            let remembered = await BarcodeScanHistory.shared.lastPortion(for: result.barcode)
            await MainActor.run {
                product = result
                portion = remembered ?? result.defaultPortion
                category = MealCategory.auto(for: Date())
                phase = .review
                if dataStore.profile.hapticFeedbackEnabled {
                    BarcodeHaptics.lookupSuccess()
                }
            }
        } catch let lookupError as OpenFoodFactsService.LookupError {
            await MainActor.run {
                errorText = lookupError.errorDescription
                phase = (lookupError == .notFound) ? .notFound : .error
                if dataStore.profile.hapticFeedbackEnabled {
                    BarcodeHaptics.lookupFailure()
                }
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                phase = .error
                if dataStore.profile.hapticFeedbackEnabled {
                    BarcodeHaptics.lookupFailure()
                }
            }
        }
    }

    private func confirm() {
        // Re-entrancy guard: belt-and-suspenders for the single-button
        // happy path. Stops a programmatic double-call (e.g. a future
        // shortcut intent) from logging twice while only being able
        // to undo once.
        guard phase == .review,
              let product,
              let meal = currentMacros(for: product) else { return }
        let now = Date()
        // OCR-synthesised products and manual-override edits share the
        // OFF flow but aren't strictly Open Food Facts data; tag them
        // as `manual` so the meal-history list reflects what the user
        // actually did.
        let source: MealSource = (manualOverride != nil) ? .manual : .openFoodFacts
        let entry = MealEntry(
            loggable: meal,
            name: product.name,
            category: category,
            source: source,
            sourceID: product.barcode,
            date: now
        )
        dataStore.logMealEntry(entry)
        if dataStore.profile.hapticFeedbackEnabled {
            // .logCommitted carries a heavier impact than the lookup
            // success — the user feels "I just logged a meal" as a
            // distinct beat from "I just scanned a barcode".
            BarcodeHaptics.logCommitted()
        }
        loggedSnapshot = LoggedSnapshot(
            productName: product.name,
            entryID: entry.id,
            calories: meal.calories,
            date: now,
            barcode: product.barcode,
            portion: portion
        )
        // Record the scan + portion choice in history so the recents
        // row re-ranks and the next re-scan of this product preselects
        // the same portion. Fire-and-forget — UI doesn't need to wait.
        let recordedBarcode = product.barcode
        let recordedPortion = portion
        Task {
            await BarcodeScanHistory.shared.recordLog(
                barcode: recordedBarcode,
                portion: recordedPortion,
                at: now
            )
        }
        phase = .logged                                  // .task(id: phase) above starts the 5-s auto-close
    }

    private func undoLastLog() {
        guard let snapshot = loggedSnapshot else {
            onClose()
            return
        }
        // Cancel the auto-close timer before it fires onClose a second
        // time — moving phase out of `.logged` triggers the
        // `.task(id: phase)` modifier to drop the in-flight sleep.
        phase = .review
        dataStore.unlogMealEntry(id: snapshot.entryID)
        // Roll back the scan-history record too so an undone scan
        // doesn't inflate the recents ranking or preselect the wrong
        // portion next time. Fire-and-forget — UI is closing anyway.
        let undoneBarcode = snapshot.barcode
        Task { await BarcodeScanHistory.shared.undoLog(barcode: undoneBarcode) }
        if dataStore.profile.hapticFeedbackEnabled {
            BarcodeHaptics.logUndone()
        }
        onClose()
    }

    private func resetForRescan() {
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
