import PhotosUI
import SwiftUI

/// Detailed profile customization surface presented from `ProfileView` when the
/// user taps the avatar or the pencil in `ProfileHeader`. Lets the user upload a profile
/// image, edit identity (name, bio), pick an accent color, review goals, see
/// the stacks they've created (with one-tap navigation back to the Protocols
/// tab), preview unlocked achievements, and tweak app-wide preferences.
struct ProfileCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    private static let nameCharacterLimit = 40
    private static let bioCharacterLimit = 280

    @State private var themeManager = ThemeManager.shared

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var avatarData: Data?
    @State private var photoSelection: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var photoError: String?
    @State private var isConfirmingRemoveAvatar = false
    @State private var isShowingPhotoSourceMenu = false
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var isShowingPresetPicker = false
    @State private var cameraDeniedReason: CameraDeniedReason?

    private enum CameraDeniedReason: Identifiable {
        case denied
        case restricted
        var id: Self { self }
    }

    var body: some View {
        @Bindable var store = dataStore

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    avatarSection
                        .sectionAppear(index: 0)

                    statsRow
                        .sectionAppear(index: 1)

                    identityCard
                        .sectionAppear(index: 2)

                    accentColorCard
                        .sectionAppear(index: 3)

                    goalsCard
                        .sectionAppear(index: 4)

                    bodyMetricsSummary
                        .sectionAppear(index: 5)

                    ProfileStacksCard()
                        .sectionAppear(index: 6)

                    AchievementsPreviewCard()
                        .sectionAppear(index: 7)

                    preferencesCard(store: store)
                        .sectionAppear(index: 8)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColor.background)
            .dismissKeyboardOnTap()
            .navigationTitle("Customize profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .onAppear(perform: hydrateFromProfile)
        // Accent, goals and preferences save as they change, so name, bio
        // and photo do too: every way out — Done, swipe-down, or a protocol
        // row that closes Profile — keeps what the user entered.
        .onDisappear(perform: commit)
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task { await processPickedPhoto(newValue) }
        }
        .alert("Remove profile photo?", isPresented: $isConfirmingRemoveAvatar) {
            Button("Remove", role: .destructive) {
                avatarData = nil
                photoSelection = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your initials will be shown instead.")
        }
        .alert(
            "Couldn't use that photo",
            isPresented: Binding(
                get: { photoError != nil },
                set: { if !$0 { photoError = nil } }
            ),
            presenting: photoError
        ) { _ in
            Button("OK", role: .cancel) { photoError = nil }
        } message: { error in
            Text(error)
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: Spacing.md) {
            ZStack(alignment: .bottomTrailing) {
                avatarCircle
                    .overlay {
                        if isProcessingPhoto {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(AppColor.accentLight)
                        }
                    }

                Button {
                    isShowingPhotoSourceMenu = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.background)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(AppColor.accentPrimary)
                                .overlay {
                                    Circle().strokeBorder(AppColor.background, lineWidth: 2)
                                }
                        }
                        .minimumHitArea()
                }
                .disabled(isProcessingPhoto)
                .accessibilityLabel("Change profile photo")
            }

            if let resolvedName = trimmedName, !resolvedName.isEmpty {
                Text(resolvedName)
                    .font(AppFont.title2)
                    .foregroundStyle(AppColor.textPrimary)
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    isShowingPhotoSourceMenu = true
                } label: {
                    Label(
                        avatarData == nil ? "Add photo" : "Replace",
                        systemImage: "photo.on.rectangle.angled"
                    )
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        Capsule().fill(AppColor.accentPrimary.opacity(0.2))
                    }
                }
                .disabled(isProcessingPhoto)

                if avatarData != nil {
                    Button(role: .destructive) {
                        isConfirmingRemoveAvatar = true
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.destructive)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background {
                                Capsule().fill(AppColor.destructive.opacity(0.15))
                            }
                    }
                }
            }
        }
        .padding(.top, Spacing.sm)
        .confirmationDialog(
            "Profile Photo",
            isPresented: $isShowingPhotoSourceMenu,
            titleVisibility: .visible
        ) {
            photoSourceButtons
        }
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $photoSelection,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(
                onPicked: { image in
                    isShowingCamera = false
                    Task { await ingestUIImage(image) }
                },
                onCancel: { isShowingCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert(item: $cameraDeniedReason) { reason in
            switch reason {
            case .denied:
                Alert(
                    title: Text("Camera Access Off"),
                    message: Text("Turn on Camera access for Atlas in Settings to take a profile photo. You can also pick from your library."),
                    primaryButton: .default(Text("Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel(Text("Use Library")) {
                        isShowingLibrary = true
                    }
                )
            case .restricted:
                Alert(
                    title: Text("Camera Unavailable"),
                    message: Text("The camera is restricted on this device. Pick from your library or choose a preset avatar."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $isShowingPresetPicker) {
            AvatarPresetPickerSheet(
                onPick: { preset in
                    isShowingPresetPicker = false
                    Task { await ingestPreset(preset) }
                },
                onCancel: { isShowingPresetPicker = false }
            )
            .liquidGlassPresentation(detents: [.medium, .large])
        }
    }

    @ViewBuilder
    private var photoSourceButtons: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Take Photo") {
                Task { await tapTakePhoto() }
            }
        }
        Button("Choose from Library") { isShowingLibrary = true }
        Button("Pick a Preset Avatar") { isShowingPresetPicker = true }
        Button("Cancel", role: .cancel) {}
    }

    /// Camera authorization gate — see `CameraAuthorization` for the
    /// rationale. Without it, `.denied` users get a black fullscreen
    /// cover.
    private func tapTakePhoto() async {
        switch await CameraAuthorization.resolve() {
        case .granted:
            isShowingCamera = true
        case .denied:
            cameraDeniedReason = .denied
        case .restricted:
            cameraDeniedReason = .restricted
        }
    }

    private var avatarCircle: some View {
        let size: CGFloat = 120
        return Group {
            if let data = avatarData, let uiImage = AvatarImageCache.shared.image(for: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.35),
                                    AppColor.accentDark.opacity(0.55)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if let initial = displayInitial {
                        Text(initial)
                            .font(AppFont.scaled(48, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                            .foregroundStyle(AppColor.accentLight)
                    } else {
                        Image(systemName: "person.fill")
                            .font(AppFont.scaled(48, relativeTo: .largeTitle))
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .overlay {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        }
        .liquidGlass(.circle)
        .appShadow(AppShadow.glassElevated)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(avatarAccessibilityLabel)
    }

    private var avatarAccessibilityLabel: String {
        if avatarData != nil {
            return String(localized: "Profile photo")
        }
        if let name = trimmedName, !name.isEmpty {
            return String(localized: "Profile avatar showing initial \(String(name.prefix(1)).uppercased())")
        }
        return String(localized: "Profile avatar")
    }

    private var displayInitial: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first).uppercased()
    }

    private var trimmedName: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: Spacing.sm) {
            // The streak counts doses, so it means nothing without a
            // protocol running — a training-only user would see 0 forever.
            if dataStore.protocols.contains(where: { $0.status == .active }) {
                StatTile(
                    label: "Dose streak",
                    value: "\(dataStore.currentStreak)",
                    icon: "flame.fill",
                    tint: AppColor.warning,
                    surface: .glass,
                    accessibilityLabel: String(localized: "Dose streak: \(dataStore.currentStreak) days")
                )
            }
            StatTile(
                label: "Days",
                value: "\(dataStore.totalDaysLogged)",
                icon: "calendar",
                tint: AppColor.accentPrimary,
                surface: .glass,
                accessibilityLabel: String(localized: "Days logged: \(dataStore.totalDaysLogged)")
            )
            StatTile(
                label: "Protocols",
                value: "\(dataStore.protocols.count)",
                icon: "square.stack.3d.up.fill",
                tint: AppColor.accentLight,
                surface: .glass,
                accessibilityLabel: String(localized: "Protocols created: \(dataStore.protocols.count)")
            )
            StatTile(
                label: "Member",
                value: memberShortDuration,
                icon: "calendar.badge.clock",
                tint: AppColor.textSecondary,
                surface: .glass,
                accessibilityLabel: String(localized: "Member duration: \(memberShortDuration)")
            )
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var memberShortDuration: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: dataStore.profile.memberSince, to: Date())
        if let years = components.year, years >= 1 {
            return "\(years)y"
        }
        if let months = components.month, months >= 1 {
            return "\(months)mo"
        }
        let days = components.day ?? 0
        return "\(max(days, 0))d"
    }

    // MARK: - Identity

    private var identityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Identity", systemImage: "person.text.rectangle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                identityField(
                    title: "Display name",
                    placeholder: "What should we call you?",
                    text: $name
                )
                .onChange(of: name) { _, newValue in
                    if newValue.count > Self.nameCharacterLimit {
                        name = String(newValue.prefix(Self.nameCharacterLimit))
                    }
                }

                Divider().overlay(AppColor.glassBorder)

                bioField
            }
        }
    }

    private func identityField(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)

            TextField(placeholder, text: text)
                .accessibilityLabel(Text(title))
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .tint(AppColor.accentPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Bio")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(bio.count)/\(Self.bioCharacterLimit)")
                    .font(AppFont.caption2)
                    .foregroundStyle(
                        bio.count > Self.bioCharacterLimit
                        ? AppColor.destructive
                        : AppColor.textTertiary
                    )
                    .monospacedDigit()
            }

            TextField(
                "A short note about your goals, training, or what you're optimizing for.",
                text: $bio,
                axis: .vertical
            )
            .font(AppFont.body)
            .foregroundStyle(AppColor.textPrimary)
            .tint(AppColor.accentPrimary)
            .lineLimit(3...6)
            .onChange(of: bio) { _, newValue in
                if newValue.count > Self.bioCharacterLimit {
                    bio = String(newValue.prefix(Self.bioCharacterLimit))
                }
            }
        }
    }

    // MARK: - Accent color

    private var accentColorCard: some View {
        @Bindable var theme = themeManager
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Accent color", systemImage: "paintpalette.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(themeManager.theme.displayName)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                HStack(spacing: Spacing.md) {
                    ForEach(AppThemeColor.allCases) { color in
                        accentSwatch(color, selection: $theme.theme)
                    }
                }
            }
        }
    }

    private func accentSwatch(_ color: AppThemeColor, selection: Binding<AppThemeColor>) -> some View {
        let selected = selection.wrappedValue == color
        return Button {
            guard !selected else { return }
            AppAnimation.with(AppAnimation.quick) {
                selection.wrappedValue = color
            }
            Haptics.impact(.light)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.light, color.primary, color.dark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                if selected {
                    Circle()
                        .strokeBorder(AppColor.textPrimary, lineWidth: 2)
                        .frame(width: 38, height: 38)
                    Image(systemName: "checkmark")
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Goals

    private var selectedGoalCount: Int {
        OnboardingView.PrimaryGoal.allCases.filter { dataStore.profile.goals.contains($0.rawValue) }.count
    }

    private var goalsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Goals", systemImage: "target")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(selectedGoalCount) selected")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }

                Text("Pick what you're optimizing for. Long-press a selected goal to pin it as your primary focus.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)

                if let pinned = dataStore.profile.primaryGoal.flatMap(OnboardingView.PrimaryGoal.init(rawValue:)) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "pin.fill")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(AppColor.accentLight)
                            .accessibilityHidden(true)
                        Text("Primary: \(pinned.displayName)")
                            .font(AppFont.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                        Spacer()
                        Button("Unpin") {
                            dataStore.setPrimaryGoal(nil)
                        }
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                            }
                    }
                }

                FlowLayout(spacing: Spacing.sm) {
                    ForEach(OnboardingView.PrimaryGoal.allCases) { goal in
                        goalChip(goal)
                    }
                }
            }
        }
    }

    private func goalChip(_ goal: OnboardingView.PrimaryGoal) -> some View {
        let key = goal.rawValue
        let selected = dataStore.profile.goals.contains(key)
        let pinned = dataStore.profile.primaryGoal == key
        return Button {
            toggleGoal(key)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: pinned ? "pin.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                    .font(AppFont.scaled(11, weight: .semibold))
                Text(goal.displayName)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .foregroundStyle(selected ? AppColor.accentLight : AppColor.textSecondary)
            .background {
                Capsule()
                    .fill(selected ? AppColor.accentPrimary.opacity(0.25) : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        Capsule().strokeBorder(
                            selected ? AppColor.glassBorderActive : AppColor.glassBorder,
                            lineWidth: 0.5
                        )
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(goal.displayName)
        .accessibilityValue(pinned ? Text("Primary goal") : Text(""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityActions {
            if selected {
                if pinned {
                    Button("Unpin") { dataStore.setPrimaryGoal(nil) }
                } else {
                    Button("Pin as primary") { pin(key) }
                }
            }
        }
        .contextMenu {
            if selected {
                if pinned {
                    Button {
                        dataStore.setPrimaryGoal(nil)
                    } label: {
                        Label("Unpin", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        pin(key)
                    } label: {
                        Label("Pin as primary", systemImage: "pin")
                    }
                }
            }
        }
    }

    private func pin(_ key: String) {
        dataStore.setPrimaryGoal(key)
        Haptics.success()
    }

    private func toggleGoal(_ goal: String) {
        var current = Set(dataStore.profile.goals)
        if current.contains(goal) {
            current.remove(goal)
        } else {
            current.insert(goal)
        }
        dataStore.updateGoals(current)
        Haptics.selection()
    }

    // MARK: - Body Metrics summary

    private var bodyMetricsSummary: some View {
        let metrics = dataStore.profile.bodyMetrics
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Body metrics", systemImage: "figure.arms.open")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if metrics.isComplete {
                    HStack(spacing: Spacing.lg) {
                        bodyStat("Weight", weightString(metrics))
                        bodyStat("Height", heightString(metrics))
                        bodyStat("Age", metrics.age.map { "\($0)" } ?? "—")
                    }
                } else {
                    Text("Optional — add your weight, height, and age in the Body metrics card on your Profile to display them alongside compliance trends.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bodyStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.title3)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weightString(_ m: BodyMetrics) -> String {
        guard let kg = m.weightKg else { return "—" }
        return m.unit.weightLabel(kg)
    }

    private func heightString(_ m: BodyMetrics) -> String {
        guard let cm = m.heightCm else { return "—" }
        if m.unit == .metric { return "\(Int(cm.rounded())) cm" }
        // Feet + inches reads naturally ("5'11\""); round total inches
        // first so we never produce "5'12\"".
        let totalInches = Int((cm / 2.54).rounded())
        return "\(totalInches / 12)'\(totalInches % 12)\""
    }

    // MARK: - Stacks

    // MARK: - Achievements

    // MARK: - Preferences

    private func preferencesCard(store: DataStore) -> some View {
        @Bindable var store = store
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Preferences", systemImage: "slider.horizontal.3")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.bottom, Spacing.xs)

                SettingsToggleRow(
                    icon: "hand.tap.fill",
                    title: "Haptic feedback",
                    subtitle: "Vibrate on taps and toggles",
                    isOn: $store.profile.hapticFeedbackEnabled
                )
                .onChange(of: dataStore.profile.hapticFeedbackEnabled) { _, _ in
                    dataStore.persistProfile()
                }

                Divider().overlay(AppColor.glassBorder)

                SettingsToggleRow(
                    icon: "bell.fill",
                    title: "Dose reminders",
                    subtitle: "Get notified for scheduled doses",
                    isOn: $store.profile.doseRemindersEnabled
                )
                .onChange(of: dataStore.profile.doseRemindersEnabled) { _, _ in
                    dataStore.persistProfile()
                }
            }
        }
    }

    // MARK: - State sync

    private func hydrateFromProfile() {
        let profile = dataStore.profile
        name = profile.name
        bio = profile.bio
        avatarData = profile.avatarImageData
    }

    private func commit() {
        let profile = dataStore.profile
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != profile.name
            || bio.trimmingCharacters(in: .whitespacesAndNewlines) != profile.bio {
            dataStore.updateProfileIdentity(name: name, bio: bio)
        }
        if avatarData != dataStore.profile.avatarImageData {
            dataStore.updateAvatarImageData(avatarData)
        }
    }

    // MARK: - Photo processing

    @MainActor
    private func processPickedPhoto(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        // Cleared after every pick so choosing the same library item again
        // is still a change `onChange(of: photoSelection)` sees.
        defer {
            isProcessingPhoto = false
            photoSelection = nil
        }

        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                photoError = String(localized: "We couldn't read that photo. Try a different image.")
                return
            }

            let processed = await Task.detached(priority: .userInitiated) {
                AvatarImageNormalizer.normalize(rawImageData: raw)
            }.value

            if let processed {
                avatarData = processed
            } else {
                photoError = String(localized: "That image format isn't supported. Try a JPEG or PNG.")
            }
        } catch {
            photoError = String(localized: "We couldn't load that photo. Please try again.")
        }
    }

    @MainActor
    private func ingestUIImage(_ image: UIImage) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        let processed = await Task.detached(priority: .userInitiated) {
            AvatarImageNormalizer.normalize(image: image)
        }.value
        if let processed {
            avatarData = processed
        } else {
            photoError = String(localized: "We couldn't process that photo. Try a different image.")
        }
    }

    @MainActor
    private func ingestPreset(_ preset: AvatarPreset) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        let data = await Task.detached(priority: .userInitiated) {
            preset.renderJPEGData()
        }.value
        avatarData = data
    }
}

#Preview("With Profile") {
    ProfileCustomizationSheet()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}

#Preview("Empty Profile") {
    ProfileCustomizationSheet()
        .environment(DataStore())
        .environment(AppState())
        .preferredColorScheme(.dark)
}
