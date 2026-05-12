import SwiftUI
import AVFoundation

/// End-to-end barcode-scan sheet: opens the camera, resolves the
/// detected code against Open Food Facts, lets the user dial in a
/// portion, and rolls the result into today's consumption via
/// `dataStore.logMeal(...)`.
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
    @State private var errorText: String?
    @State private var manualBarcode: String = ""

    private enum Phase: Equatable {
        case preflight       // checking camera permission + device support
        case scanning        // DataScanner live
        case manualEntry     // simulator / unsupported devices type a code
        case lookingUp       // OFF network round-trip
        case review          // product + portion + macros
        case notFound        // barcode looked up cleanly but no product
        case error           // any other terminal failure
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                switch phase {
                case .preflight:    preflight
                case .scanning:     scanner
                case .manualEntry:  manualEntry
                case .lookingUp:    lookingUp
                case .review:       reviewCard
                case .notFound:     notFoundCard
                case .error:        errorCard
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

                reticle
            }
            .frame(height: 360)

            Text("Hold a packaged food's barcode inside the frame.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(AppColor.accentLight.opacity(0.85), lineWidth: 2)
            .frame(width: 240, height: 140)
            .shadow(color: AppColor.accentGlow, radius: 12)
            .allowsHitTesting(false)
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
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColor.accentLight)
            Text("Looking up the product…")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    @ViewBuilder
    private var reviewCard: some View {
        if let product {
            VStack(spacing: Spacing.lg) {
                productHeader(product)
                portionPicker(for: product)
                macroPanel(for: product)
                actionButtons
            }
        } else {
            errorCard            // defensive — phase guarantees product is set
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
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
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
        let meal = product.loggable(for: portion)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider().background(AppColor.glassBorder)
            macroRow(label: "Calories", value: "\(meal?.calories ?? 0) kcal")
            macroRow(label: "Protein",  value: "\(meal?.proteinG ?? 0) g")
            macroRow(label: "Carbs",    value: "\(meal?.carbsG ?? 0) g")
            macroRow(label: "Fat",      value: "\(meal?.fatG ?? 0) g")
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.sm) {
            Button("Scan another") {
                product = nil
                manualBarcode = ""
                phase = BarcodeScannerView.canScan ? .scanning : .manualEntry
            }
            .buttonStyle(.bordered)
            .tint(AppColor.textSecondary)

            Button("Add to today") {
                confirm()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .disabled(product?.loggable(for: portion) == nil)
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
            Text("Open Food Facts doesn't know this product. You can photograph the meal instead — Claude will estimate the macros from the picture.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            VStack(spacing: Spacing.sm) {
                Button {
                    onRequestPhotoFallback()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "camera.fill")
                        Text("Snap a photo instead")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentPrimary)

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
        phase = .lookingUp
        Task { await lookup(barcode: barcode) }
    }

    private func lookup(barcode: String) async {
        do {
            let result = try await OpenFoodFactsService.shared.fetch(barcode: barcode)
            await MainActor.run {
                product = result
                portion = result.defaultPortion
                phase = .review
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } catch let lookupError as OpenFoodFactsService.LookupError {
            await MainActor.run {
                errorText = lookupError.errorDescription
                phase = (lookupError == .notFound) ? .notFound : .error
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                phase = .error
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func confirm() {
        guard let product, let meal = product.loggable(for: portion) else { return }
        dataStore.logMeal(
            calories: meal.calories,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG
        )
        if dataStore.profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        onClose()
    }
}

// MARK: - Portion case helpers

private extension ScannedProduct.Portion {
    var isServings: Bool {
        if case .servings = self { return true }
        return false
    }
    var isGrams: Bool {
        if case .grams = self { return true }
        return false
    }
}
