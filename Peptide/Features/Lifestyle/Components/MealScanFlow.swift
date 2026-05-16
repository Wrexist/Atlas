import SwiftUI
import PhotosUI
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

    private enum Phase: Equatable {
        case pickImage
        case analyzing
        case review
        case error
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
        .onChange(of: selectedItem) { _, newValue in
            Task { await loadImage(from: newValue) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(
                onPicked: { captured in
                    isShowingCamera = false
                    image = captured
                    phase = .analyzing
                    Task { await runAnalysis(on: captured) }
                },
                onCancel: { isShowingCamera = false },
                cameraDevice: .rear,
                allowsEditing: false
            )
            .ignoresSafeArea()
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
                        isShowingCamera = true
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
    private func pickerButtonLabel(icon: String, title: LocalizedStringKey, style: PickerButtonStyle) -> some View {
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
            Button("Try again") {
                image = nil
                selectedItem = nil
                errorText = nil
                phase = .pickImage
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
            await MainActor.run {
                image = ui
                phase = .analyzing
            }
            await runAnalysis(on: ui)
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                phase = .error
            }
        }
    }

    private func runAnalysis(on image: UIImage) async {
        do {
            let result = try await MealScannerService.shared.analyze(image: image)
            await MainActor.run {
                estimate = result
                category = MealCategory.auto(for: Date())
                phase = .review
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        guard let estimate else { return }
        let entry = MealEntry(
            date: Date(),
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
        if dataStore.profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        onClose()
    }
}
