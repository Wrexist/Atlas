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
        .preferredColorScheme(.dark)
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
                .font(.system(size: 14, weight: .bold))
            Text(title)
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: style == .primary
                            ? [
                                Color(red: 0.310, green: 0.275, blue: 0.898),
                                Color(red: 0.486, green: 0.227, blue: 0.929),
                            ]
                            : [
                                AppColor.surfaceSecondary.opacity(0.85),
                                AppColor.surfaceSecondary.opacity(0.55),
                            ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
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

    private var previewBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
            } else {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(AppColor.accentLight)
                    Text("No photo selected")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(height: 220)
    }

    private var analyzing: some View {
        VStack(spacing: Spacing.lg) {
            previewBox
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColor.accentLight)
            Text("Reading the plate…")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var includedItems: [EditableFoodItem] { items.filter(\.include) }
    private var totalCalories: Int { includedItems.reduce(0) { $0 + $1.calories } }

    private var reviewCard: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                previewBox
                    .frame(height: 130)

                HStack {
                    Text("Detected items")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(includedItems.count) selected · \(totalCalories) kcal")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }

                Text("Tap a row to adjust the portion, untick anything that isn't yours, or save an item to your food library for next time.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach($items) { $item in
                    FoodItemEditCard(
                        item: $item,
                        onSave: { saveToLibrary(item) }
                    )
                }

                MealCategoryPicker(selection: $category)

                HStack(spacing: Spacing.sm) {
                    Button("Re-scan") {
                        image = nil
                        selectedItem = nil
                        items = []
                        phase = .pickImage
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColor.textSecondary)

                    Button(addButtonTitle) {
                        confirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.accentPrimary)
                    .disabled(includedItems.isEmpty)
                }
                .padding(.top, Spacing.xs)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var addButtonTitle: LocalizedStringKey {
        includedItems.count <= 1 ? "Add to today" : "Add \(includedItems.count) items"
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
            Button(image == nil ? "Try again" : "Retry") {
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
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
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
    /// stored per-100g (derived on the item) and the current portion is
    /// recorded as the default serving.
    private func saveToLibrary(_ item: EditableFoodItem) {
        let food = CustomFood(
            name: item.name,
            per100g: item.per100g,
            servingGrams: item.grams > 0 ? item.grams : nil,
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

    /// Common portion presets (grams) shown as quick-pick chips.
    private static let gramPresets: [Double] = [50, 100, 150, 200, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            if item.include {
                Divider().overlay(AppColor.glassBorder)
                portionStepper
                presetChips
                macroSummary
                saveButton
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
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                item.include.toggle()
            } label: {
                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.include ? AppColor.accentPrimary : AppColor.textTertiary)
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                Text("kcal")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var portionStepper: some View {
        HStack {
            Text("Portion")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Button {
                item.grams = max(5, (item.grams - 10).rounded())
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColor.accentLight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease portion")

            Text("\(Int(item.grams.rounded())) g")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 64)

            Button {
                item.grams = min(2000, (item.grams + 10).rounded())
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColor.accentLight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase portion")
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                chip(label: "Serving", grams: item.aiGrams)
                ForEach(Self.gramPresets, id: \.self) { grams in
                    chip(label: "\(Int(grams)) g", grams: grams)
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
                .font(.system(size: 12, weight: .semibold))
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.savedToLibrary ? "checkmark" : "bookmark")
                    .font(.system(size: 12, weight: .bold))
                Text(item.savedToLibrary ? "Saved to library" : "Save to library")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(item.savedToLibrary ? AppColor.accentPrimary : AppColor.accentLight)
        }
        .buttonStyle(.plain)
        .disabled(item.savedToLibrary)
    }
}
