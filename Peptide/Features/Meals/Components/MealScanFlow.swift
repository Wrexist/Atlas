import SwiftUI
import PhotosUI
import Photos
import UIKit

/// End-to-end meal-scanner sheet: picks an image (camera or library),
/// posts it to `MealScannerService`, surfaces a confirmation card with
/// the macro breakdown, and writes a `.photo`-sourced `MealEntry`
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
    @State private var estimate: MealScannerService.MealEstimate?
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
            Text("Snap or pick a photo of your meal — Claude will read it back as calories, protein, carbs, and fat.")
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

    private var reviewCard: some View {
        VStack(spacing: Spacing.lg) {
            previewBox
                .frame(height: 160)

            if let estimate {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text(estimate.mealName.capitalized)
                            .font(AppFont.title2)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        confidencePill(estimate.confidence)
                    }

                    Divider().background(AppColor.glassBorder)

                    macroRow(label: "Calories", value: "\(estimate.calories) kcal")
                    macroRow(label: "Protein",  value: "\(estimate.proteinG) g")
                    macroRow(label: "Carbs",    value: "\(estimate.carbsG) g")
                    macroRow(label: "Fat",      value: "\(estimate.fatG) g")
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

                MealCategoryPicker(selection: $category)
            }

            HStack(spacing: Spacing.sm) {
                Button("Re-scan") {
                    image = nil
                    selectedItem = nil
                    estimate = nil
                    phase = .pickImage
                }
                .buttonStyle(.bordered)
                .tint(AppColor.textSecondary)

                Button("Add to today") {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accentPrimary)
            }
        }
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

    private func confidencePill(_ value: Double) -> some View {
        let pct = Int((value * 100).rounded())
        return Text("\(pct)% sure")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(AppColor.accentPrimary.opacity(0.18))
            }
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
            let result = try await MealScannerService.shared.analyze(image: image)
            await MainActor.run {
                estimate = result
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

    private func confirm() {
        guard let estimate else { return }
        // Use the photo's capture time so a yesterday-dinner photo
        // picked at 10am today logs into yesterday's bucket. Falls
        // back to now (set in @State default) for camera captures or
        // assets without a creation date.
        let entry = MealEntry(
            date: capturedAtDate,
            category: category,
            name: estimate.mealName.capitalized,
            calories: estimate.calories,
            proteinG: estimate.proteinG,
            carbsG: estimate.carbsG,
            fatG: estimate.fatG,
            sourceID: nil,
            source: .photo
        )
        dataStore.logMealEntry(entry)
        Haptics.success()
        onClose()
    }
}
