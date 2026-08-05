import SwiftUI
import PhotosUI
import Photos
import UIKit

/// End-to-end meal-scanner sheet: picks an image (camera or library),
/// posts it to `MealScannerService`, surfaces a per-item review where the
/// user can adjust portions, drop misfires, and save items to their food
/// library, then writes one `.photo`-sourced `MealEntry` per kept item
/// through `dataStore.logMealEntry(_:)`.
///
/// "Take photo" launches a live rear-camera capture via `CameraPicker`
/// (UIImagePickerController), and "Choose from library" uses PhotosPicker.
/// The camera option hides on simulators and devices without a usable
/// camera so the user only sees actions that work.
struct MealScanFlow: View {
    @Environment(DataStore.self) private var dataStore
    let onClose: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var phase: Phase = .pickImage
    /// Per-item editable results from the scan. Each row carries its own
    /// portion + include + saved-to-library state so the user can tune
    /// the plate before logging.
    @State private var items: [EditableFoodItem] = []
    @State private var errorText: String?
    @State private var category: MealCategory = MealCategory.auto(for: Date())
    @State private var isShowingCamera = false
    @State private var cameraDeniedAlert: CameraDeniedReason?
    /// Tracks the in-flight image-load and Anthropic analysis tasks so
    /// they get cancelled when the sheet is dismissed. Without this,
    /// closing the sheet mid-scan leaves the 30-second Anthropic call
    /// running to completion (burning proxy quota for a request the
    /// user abandoned) and mutating @State on a now-detached view.
    @State private var inFlightTask: Task<Void, Never>?
    /// Honors the photo's EXIF creation date so picking yesterday's
    /// dinner from the library at 10am today logs the meal into
    /// yesterday's bucket (audit Meals HIGH 2). Camera captures
    /// stamp Date() since there's no asset to read from.
    @State private var capturedAtDate: Date = Date()

    private enum Phase: Equatable {
        case pickImage
        case analyzing
        case review
        case error
    }

    /// Drives the alert that explains why the camera couldn't open and
    /// what the user can do next. `.denied` deep-links to Settings;
    /// `.restricted` (parental controls) only tells the user to use
    /// the photo library instead.
    private enum CameraDeniedReason: Identifiable {
        case denied
        case restricted
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                switch phase {
                case .pickImage:  picker
                case .analyzing:  analyzing
                case .review:     reviewCard
                case .error:      errorCard
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColor.background)
            .navigationTitle("Meal Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .onDisappear {
            inFlightTask?.cancel()
            inFlightTask = nil
        }
        .onChange(of: selectedItem) { _, newValue in
            inFlightTask?.cancel()
            inFlightTask = Task { await loadImage(from: newValue) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(
                onPicked: { captured in
                    isShowingCamera = false
                    image = captured
                    phase = .analyzing
                    inFlightTask?.cancel()
                    inFlightTask = Task { await runAnalysis(on: captured) }
                },
                onCancel: { isShowingCamera = false },
                cameraDevice: .rear,
                allowsEditing: false
            )
            .ignoresSafeArea()
        }
        .alert(item: $cameraDeniedAlert) { reason in
            switch reason {
            case .denied:
                Alert(
                    title: Text("Camera Access Off"),
                    message: Text("Turn on Camera access for Atlas in Settings to scan meals with your camera. You can still pick a photo from your library."),
                    primaryButton: .default(Text("Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel(Text("Use Library"))
                )
            case .restricted:
                Alert(
                    title: Text("Camera Unavailable"),
                    message: Text("The camera is restricted on this device — likely by Screen Time or a profile policy. Pick a photo from your library to continue."),
                    dismissButton: .default(Text("Use Library"))
                )
            }
        }
    }

    /// Resolves camera authorization before presenting `CameraPicker`.
    /// Without this gate, `.denied` and `.restricted` users get a
    /// black `fullScreenCover` with no system prompt and no clear
    /// dismiss path.
    private func tapTakePhoto() async {
        switch await CameraAuthorization.resolve() {
        case .granted:
            isShowingCamera = true
        case .denied:
            cameraDeniedAlert = .denied
        case .restricted:
            cameraDeniedAlert = .restricted
        }
    }

    // MARK: - Phases

    private var picker: some View {
        VStack(spacing: Spacing.lg) {
            previewBox
            Text("Snap or pick a photo of your meal — Claude separates each food so you can fine-tune the portions before logging.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                if UIImagePickerController.SourceType.cameraIsAvailable {
                    Button {
                        Task { await tapTakePhoto() }
                    } label: {
                        pickerButtonLabel(
                            icon: "camera.fill",
                            title: "Take photo",
                            style: .primary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the camera to capture a meal photo.")
                }

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    pickerButtonLabel(
                        icon: "photo.on.rectangle",
                        title: "Choose from library",
                        style: .secondary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Picks an existing photo from your library.")
            }
        }
    }

    private enum PickerButtonStyle { case primary, secondary }

    @ViewBuilder
    nonisolated private func pickerButtonLabel(icon: String, title: LocalizedStringKey, style: PickerButtonStyle) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(AppFont.scaled(13, weight: .bold))
            Text(title)
                .font(AppFont.scaled(16, weight: .bold))
        }
        .foregroundStyle(AppColor.onAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            Capsule()
                .fill(
                    style == .primary
                        ? AnyShapeStyle(AppColor.accentFill)
                        : AnyShapeStyle(AppColor.surfaceSecondary.opacity(0.85))
                )
                .overlay {
                    Capsule().strokeBorder(
                        style == .primary
                            ? Color.clear
                            : AppColor.glassBorder,
                        lineWidth: 0.5
                    )
                }
        }
        .padding(.horizontal, Spacing.lg)
    }

    /// The photo, sized once and clipped at that size.
    ///
    /// This was a fixed 220pt box that the review screen re-framed to 130pt.
    /// The clip ran at the *inner* size, so ninety points of photograph drew
    /// straight over "Detected items" and the first result card — the heading,
    /// the instructions and the first row were all painted on top of a
    /// photograph, and none of the three could be read.
    private func photoCard<Overlay: View>(
        height: CGFloat,
        @ViewBuilder overlay: () -> Overlay
    ) -> some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(AppColor.surfaceSecondary)
            .frame(height: height)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                } else {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "camera.viewfinder")
                            .font(AppFont.scaled(56, weight: .light))
                            .foregroundStyle(AppColor.accentLight)
                        Text("No photo selected")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .overlay(alignment: .bottom) { overlay() }
            // Clip *after* the frame and the overlays, so nothing can escape
            // the card's real bounds again.
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            }
    }

    private var previewBox: some View {
        photoCard(height: 220) { EmptyView() }
    }

    // MARK: - Analysing

    /// A bare `ProgressView` over the photo, with its caption in grey on top
    /// of the picture, is what this was. Neither could be read and neither
    /// said what was happening.
    ///
    /// Now: the photo keeps its card, the bar sweeps underneath it, and three
    /// skeleton rows stand where the results will land so the wait shows the
    /// shape of what is coming rather than a spinner.
    private var analyzing: some View {
        VStack(spacing: Spacing.lg) {
            photoCard(height: 200) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(13, weight: .bold))
                    Text("Analysing your meal")
                        .font(AppFont.scaled(13, weight: .semibold))
                }
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .glassSurfaceCapsule()
                .padding(.bottom, Spacing.md)
            }

            ScanProgressBar()

            VStack(spacing: Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in skeletonRow }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysing your meal")
    }

    private var skeletonRow: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(AppColor.surfaceSecondary)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary)
                    .frame(width: 120, height: 8)
            }
            RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary)
                .frame(width: 44, height: 20)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.4))
        }
        .shimmer()
        .accessibilityHidden(true)
    }

    // MARK: - Review

    private var includedItems: [EditableFoodItem] { items.filter(\.include) }
    private var totalCalories: Int { includedItems.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Int { includedItems.reduce(0) { $0 + $1.proteinG } }
    private var totalCarbs: Int { includedItems.reduce(0) { $0 + $1.carbsG } }
    private var totalFat: Int { includedItems.reduce(0) { $0 + $1.fatG } }

    private var reviewCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                photoCard(height: 200) {
                    HStack(alignment: .bottom) {
                        detectedBadge
                        Spacer(minLength: Spacing.sm)
                        retakeButton
                    }
                    .padding(Spacing.md)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Detected items")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(includedItems.count) selected")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Text("Tap a row to adjust the portion, untick anything that isn't yours, or save an item to your food library for next time.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($items) { $item in
                    FoodItemEditCard(
                        item: $item,
                        onSave: { saveToLibrary(item.id) }
                    )
                }

                MealScanTotalsCard(
                    calories: totalCalories,
                    proteinG: totalProtein,
                    carbsG: totalCarbs,
                    fatG: totalFat
                )

                MealCategoryPicker(selection: $category)
            }
            .animation(AppAnimation.springSnappy, value: includedItems.count)
        }
        .scrollIndicators(.hidden)
        // The CTA reserves its own space rather than floating, so the last
        // card always scrolls clear of it.
        .pinnedFooter {
            GlassButton(title: addButtonTitle, style: .primary, isFullWidth: true) {
                confirm()
            }
            .disabled(includedItems.isEmpty)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)
        }
    }

    /// Sits on the photo, where the count belongs — it describes the picture.
    private var detectedBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(AppColor.positive)
                Text("\(items.count) items detected")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Text("\(totalCalories) kcal")
                .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }

    private var retakeButton: some View {
        Button {
            Haptics.impact(.soft)
            image = nil
            selectedItem = nil
            items = []
            phase = .pickImage
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.counterclockwise")
                Text("Retake")
            }
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .glassSurfaceCapsule()
        }
        .buttonStyle(.plain)
        .minimumHitArea()
        .accessibilityLabel("Retake photo")
    }

    /// `LocalizedStringKey`, not `String`: GlassButton takes a key, and
    /// interpolating the count produces the same "Add %lld items" key the
    /// manual `String(format:)` was looking up — so this is the identical
    /// lookup expressed in the type the button actually wants.
    ///
    /// Neither key is in `Localizable.xcstrings` yet, so both fall back to
    /// the key text itself. That was already true before this change; the
    /// catalog sits at 13% coverage and is tracked separately.
    private var addButtonTitle: LocalizedStringKey {
        includedItems.count <= 1
            ? "Add to today"
            : "Add \(includedItems.count) items"
    }

    private var errorCard: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.destructive)
            Text("Couldn't read this meal")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(errorText ?? "Unknown error")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
            GlassButton(title: image == nil ? "Try again" : "Retry", style: .primary) {
                errorText = nil
                if let image {
                    // Re-run analysis on the photo already loaded —
                    // no need to make the user re-pick and re-upload
                    // from scratch after a transient failure.
                    phase = .analyzing
                    inFlightTask = Task { await runAnalysis(on: image) }
                } else {
                    selectedItem = nil
                    phase = .pickImage
                }
            }
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Actions

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let ui = UIImage(data: data)
            else {
                await MainActor.run {
                    errorText = "Couldn't load that photo. Try a different one."
                    phase = .error
                }
                return
            }
            // Capture EXIF date so a meal picked from a yesterday-
            // dinner photo logs into yesterday's bucket, not today's
            // (audit Meals HIGH 2). Falls back to today only when
            // the asset truly has no creation date.
            let capturedAt = await loadCreationDate(for: item) ?? Date()
            await MainActor.run {
                image = ui
                capturedAtDate = capturedAt
                phase = .analyzing
            }
            await runAnalysis(on: ui)
        } catch {
            await MainActor.run {
                // Never surface raw PHPhotosErrorDomain strings to
                // the user — those read "The operation couldn't be
                // completed. (PHPhotosErrorDomain error 3304.)"
                // which is unactionable (audit Meals HIGH 3). Log
                // the underlying string at .private privacy for
                // diagnostic purposes.
                AppLog.persistence.error("PhotosPicker loadImage failed: \(error.localizedDescription, privacy: .private)")
                errorText = "Couldn't load that photo. Try another one."
                phase = .error
            }
        }
    }

    /// Reads the original asset's `creationDate` via PhotoKit so we
    /// preserve the moment-of-capture for the meal log. The
    /// `PhotosPickerItem.itemIdentifier` is the local PHAsset
    /// identifier; absent or unfetchable assets fall back to nil and
    /// the caller writes "now" as a final fallback.
    private func loadCreationDate(for item: PhotosPickerItem) async -> Date? {
        guard let assetID = item.itemIdentifier else { return nil }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        return result.firstObject?.creationDate
    }

    private func runAnalysis(on image: UIImage) async {
        do {
            let result = try await MealScannerService.shared.analyzeItems(image: image)
            await MainActor.run {
                items = result.map(EditableFoodItem.init(from:))
                // Auto-categorise from the PHOTO's capture time, not
                // the analyze-finished time. Otherwise a yesterday-
                // dinner photo picked at 10am gets bucketed as snack
                // (audit Meals M1).
                category = MealCategory.auto(for: capturedAtDate)
                phase = .review
                Haptics.success()
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                phase = .error
                Haptics.error()
            }
        }
    }

    /// Logs one `MealEntry` per ticked item. Each carries the same
    /// capture date + category, so a single photo of a sandwich and a
    /// soda lands as two editable rows in the day's log. Uses the
    /// photo's capture time so a yesterday-dinner photo picked at 10am
    /// today logs into yesterday's bucket.
    private func confirm() {
        let toLog = includedItems
        guard !toLog.isEmpty else { return }
        for item in toLog {
            dataStore.logMealEntry(
                MealEntry(
                    date: capturedAtDate,
                    category: category,
                    name: item.name,
                    calories: item.calories,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG,
                    sourceID: nil,
                    source: .photo
                )
            )
        }
        Haptics.success()
        onClose()
    }

    /// Saves the item to the user's food library as a `CustomFood` so it
    /// can be re-logged later from search without re-scanning. Macros are
    /// stored per-100g (derived on the item) and the model's depicted
    /// portion is recorded as the canonical one-serving size.
    ///
    /// Re-saving the same scanned item reuses the existing same-name
    /// food's id so `saveCustomFood` updates it in place instead of
    /// cluttering "My Foods" with duplicates.
    private func saveToLibrary(_ id: UUID) {
        // Read the live item so an inline rename / portion edit made just
        // before tapping Save is reflected, rather than a stale copy
        // captured when the row was built.
        guard let item = items.first(where: { $0.id == id }) else { return }

        let normalizedName = item.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let existingID = dataStore.profile.customFoods.first { existing in
            existing.brand == nil
                && existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == normalizedName
        }?.id

        let food = CustomFood(
            id: existingID ?? UUID(),
            name: item.name,
            per100g: item.per100g,
            // One serving = the model's depicted-portion estimate, not
            // whatever the user dialed the portion to before saving, so
            // the library's "Serving" mode stays accurate on re-log.
            servingGrams: item.aiGrams > 0 ? item.aiGrams : nil,
            servingLabel: item.quantityLabel.nilIfEmpty
        )
        dataStore.saveCustomFood(food)
        Haptics.success()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].savedToLibrary = true
        }
    }
}

// MARK: - Editable scanned item

/// One scanned food the user can tune before logging. Macros are held on
/// a per-100g basis (derived from the model's portion estimate) so the
/// grams stepper rescales calories/protein/carbs/fat live, matching the
/// portion math the rest of the food flow already uses.
struct EditableFoodItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var per100g: ScannedProduct.Nutriments
    var grams: Double
    /// The model's original portion estimate, offered as a one-tap
    /// "Serving" preset so the user can snap back to it.
    let aiGrams: Double
    var quantityLabel: String
    var include: Bool
    var savedToLibrary: Bool
    /// Whether the portion controls step in whole servings or raw grams.
    /// Defaults to servings — most people think "1 sandwich", not "180 g".
    var portionMode: PortionMode = .serving

    enum PortionMode: String, CaseIterable, Identifiable, CustomStringConvertible {
        case serving, grams
        var id: Self { self }
        var label: String { self == .serving ? "Servings" : "Grams" }
        var description: String { label }
    }

    /// Current portion expressed in servings, where one serving is the
    /// model's depicted-portion estimate (`aiGrams`).
    var servings: Double { aiGrams > 0 ? grams / aiGrams : 1 }

    init(from item: MealScannerService.ScannedFoodItem) {
        id = item.id
        name = item.name.capitalized
        // A zero/missing weight estimate falls back to a 100 g basis so
        // the per-100g math stays finite; the user can correct the
        // portion in the review card.
        let basis = item.grams > 0 ? item.grams : 100
        aiGrams = basis
        grams = basis
        quantityLabel = item.quantityLabel
        include = true
        savedToLibrary = false
        per100g = ScannedProduct.Nutriments(
            calories: Double(item.calories) / basis * 100,
            proteinG: Double(item.proteinG) / basis * 100,
            carbsG: Double(item.carbsG) / basis * 100,
            fatG: Double(item.fatG) / basis * 100,
            fiberG: nil,
            sugarsG: nil
        )
    }

    private func scaled(_ per100: Double) -> Int { Int((per100 * grams / 100).rounded()) }
    var calories: Int { scaled(per100g.calories) }
    var proteinG: Int { scaled(per100g.proteinG) }
    var carbsG: Int { scaled(per100g.carbsG) }
    var fatG: Int { scaled(per100g.fatG) }
}

// MARK: - Per-item review card

/// Editable row for one detected food: rename, include/exclude, adjust
/// the portion (stepper + Lifesum-style quick-pick chips), see macros
/// rescale live, and save the item to the food library for re-logging
/// without the camera.
private struct FoodItemEditCard: View {
    @Binding var item: EditableFoodItem
    let onSave: () -> Void
    /// Drives the sliding selection pill on the Servings/Grams control.
    @Namespace private var portionNS

    /// Quick-pick portion presets for each mode.
    private static let gramPresets: [Double] = [50, 100, 150, 200, 300]
    private static let servingPresets: [Double] = [0.5, 1, 1.5, 2, 3]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            if item.include {
                Divider().overlay(AppColor.glassBorder)
                modePicker
                portionStepper
                presetChips
                // Macros on the left, save affordance on the right —
                // one balanced row instead of two stacked ones.
                HStack(spacing: Spacing.sm) {
                    macroSummary
                    Spacer(minLength: Spacing.sm)
                    saveButton
                }
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            item.include ? AppColor.accentPrimary.opacity(0.30) : AppColor.glassBorder,
                            lineWidth: item.include ? 1 : 0.5
                        )
                }
        }
        .opacity(item.include ? 1 : 0.55)
        // Only the include state animates. Binding this to the whole card
        // would re-animate every portion tap and every macro recount.
        .animation(AppAnimation.springSnappy, value: item.include)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                Haptics.selection()
                withAnimation(AppAnimation.springSnappy) { item.include.toggle() }
            } label: {
                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20))
                    .foregroundStyle(item.include ? AppColor.accentPrimary : AppColor.textTertiary)
                    // The glyph swap alone was invisible at a glance on a
                    // dense list; the scale gives the tap a moment.
                    .scaleEffect(item.include ? 1 : 0.88)
            }
            .buttonStyle(.plain)
            .minimumHitArea()
            .accessibilityLabel(item.include ? "Exclude item" : "Include item")

            VStack(alignment: .leading, spacing: 2) {
                TextField("Item name", text: $item.name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .textInputAutocapitalization(.words)
                if !item.quantityLabel.isEmpty {
                    Text(item.quantityLabel)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(item.calories)")
                    .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    // Rolls rather than cuts when the portion changes, so the
                    // stepper visibly drives this number.
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var modePicker: some View {
        GlassSegmentedControl(
            options: EditableFoodItem.PortionMode.allCases,
            selected: $item.portionMode,
            namespace: portionNS
        )
    }

    @ViewBuilder
    private var portionStepper: some View {
        switch item.portionMode {
        case .serving: servingStepper
        case .grams:   gramStepper
        }
    }

    private var servingStepper: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Amount")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                stepperButton(icon: "minus.circle.fill", label: "Fewer servings") {
                    setServings(item.servings - 0.5)
                }
                VStack(spacing: 0) {
                    Text(servingsLabel)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    Text("≈ \(Int(item.grams.rounded())) g")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .frame(minWidth: 80)
                stepperButton(icon: "plus.circle.fill", label: "More servings") {
                    setServings(item.servings + 0.5)
                }
            }

            // Name what one serving actually is, when the scan gave a label.
            if !item.quantityLabel.isEmpty {
                Text("1 serving = \(item.quantityLabel)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var gramStepper: some View {
        HStack {
            Text("Amount")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            stepperButton(icon: "minus.circle.fill", label: "Decrease grams") {
                item.grams = max(5, (item.grams - 10).rounded())
            }
            Text("\(Int(item.grams.rounded())) g")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 64)
            stepperButton(icon: "plus.circle.fill", label: "Increase grams") {
                item.grams = min(2000, (item.grams + 10).rounded())
            }
        }
    }

    private func stepperButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(24))
                .foregroundStyle(AppColor.accentLight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Snaps to the nearest half-serving and writes it back as grams,
    /// keeping `grams` the single source of truth for macro scaling.
    private func setServings(_ value: Double) {
        let snapped = max(0.5, (value * 2).rounded() / 2)
        item.grams = (snapped * item.aiGrams).rounded()
    }

    private var servingsLabel: String { "\(formatCount(item.servings))×" }

    private func formatCount(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                switch item.portionMode {
                case .serving:
                    ForEach(Self.servingPresets, id: \.self) { count in
                        chip(label: "\(formatCount(count))×", grams: count * item.aiGrams)
                    }
                case .grams:
                    chip(label: "1 serving", grams: item.aiGrams)
                    ForEach(Self.gramPresets, id: \.self) { grams in
                        chip(label: "\(Int(grams)) g", grams: grams)
                    }
                }
            }
        }
    }

    private func chip(label: String, grams: Double) -> some View {
        let isActive = Int(item.grams.rounded()) == Int(grams.rounded())
        return Button {
            item.grams = grams.rounded()
        } label: {
            Text(label)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(isActive ? .white : AppColor.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(isActive ? AppColor.accentPrimary : AppColor.surfaceElevated)
                }
        }
        .buttonStyle(.plain)
    }

    private var macroSummary: some View {
        Text("P \(item.proteinG)g · C \(item.carbsG)g · F \(item.fatG)g")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .monospacedDigit()
    }

    private var saveButton: some View {
        Button(action: onSave) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.savedToLibrary ? "checkmark" : "bookmark")
                    .font(AppFont.scaled(11, weight: .bold))
                Text(item.savedToLibrary ? "Saved to library" : "Save to library")
                    .font(AppFont.scaled(13, weight: .semibold))
            }
            .foregroundStyle(item.savedToLibrary ? AppColor.accentPrimary : AppColor.accentLight)
        }
        .buttonStyle(.plain)
        .disabled(item.savedToLibrary)
    }
}
