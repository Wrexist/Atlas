import PhotosUI
import SwiftUI

/// Detailed profile customization surface presented from the Home tab when the
/// user taps the avatar in the WelcomeHeader. Lets the user upload a profile
/// image, edit identity (name, bio), pick an accent color, review goals, see
/// the stacks they've created (with one-tap navigation back to the Protocols
/// tab), preview unlocked achievements, and tweak app-wide preferences —
/// without leaving Home.
struct ProfileCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    /// Maximum dimension for the stored avatar — anything larger is downscaled
    /// before JPEG-encoding to keep the profile JSON under a few hundred KB.
    private static let avatarMaxDimension: CGFloat = 1024
    private static let avatarJPEGQuality: CGFloat = 0.82
    private static let bioCharacterLimit = 280

    private static let availableGoals = [
        "Muscle Recovery",
        "Better Sleep",
        "Cognitive Edge",
        "Anti-Aging",
        "Fat Loss",
        "Immune Support",
        "Joint Health",
        "Stress Reduction",
    ]

    @State private var achievementService = AchievementService.shared
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

                    stacksCard
                        .sectionAppear(index: 6)

                    achievementsPreview
                        .sectionAppear(index: 7)

                    preferencesCard(store: store)
                        .sectionAppear(index: 8)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Customize Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: hydrateFromProfile)
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task { await processPickedPhoto(newValue) }
        }
        .alert("Remove Profile Photo?", isPresented: $isConfirmingRemoveAvatar) {
            Button("Remove", role: .destructive) {
                avatarData = nil
                photoSelection = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your initials will be shown instead.")
        }
        .alert(
            "Couldn't Use That Photo",
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.background)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(AppColor.accentPrimary)
                                .overlay {
                                    Circle().strokeBorder(AppColor.background, lineWidth: 2)
                                }
                        }
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
                        avatarData == nil ? "Add Photo" : "Replace",
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
        .sheet(isPresented: $isShowingPresetPicker) {
            AvatarPresetPickerSheet(
                hapticEnabled: dataStore.profile.hapticFeedbackEnabled,
                onPick: { preset in
                    isShowingPresetPicker = false
                    Task { await ingestPreset(preset) }
                },
                onCancel: { isShowingPresetPicker = false }
            )
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var photoSourceButtons: some View {
        if UIImagePickerController.cameraIsAvailable {
            Button("Take Photo") { isShowingCamera = true }
        }
        Button("Choose from Library") { isShowingLibrary = true }
        Button("Pick a Preset Avatar") { isShowingPresetPicker = true }
        Button("Cancel", role: .cancel) {}
    }

    private var avatarCircle: some View {
        let size: CGFloat = 120
        return Group {
            if let data = avatarData, let uiImage = UIImage(data: data) {
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
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.accentLight)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 48))
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
        .shadow(color: AppColor.accentGlow, radius: 16, y: 6)
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
            statTile(
                value: "\(dataStore.currentStreak)",
                label: "Streak",
                icon: "flame.fill",
                accent: AppColor.warning
            )
            statTile(
                value: "\(dataStore.totalDaysLogged)",
                label: "Days",
                icon: "calendar",
                accent: AppColor.accentPrimary
            )
            statTile(
                value: "\(dataStore.protocols.count)",
                label: "Stacks",
                icon: "square.stack.3d.up.fill",
                accent: AppColor.accentLight
            )
            statTile(
                value: memberShortDuration,
                label: "Member",
                icon: "calendar.badge.clock",
                accent: AppColor.textSecondary
            )
        }
    }

    private func statTile(
        value: String,
        label: LocalizedStringKey,
        icon: String,
        accent: Color
    ) -> some View {
        GlassCardCompact {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(value)
                    .font(AppFont.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    title: "Display Name",
                    placeholder: "What should we call you?",
                    text: $name
                )

                Divider().foregroundStyle(AppColor.glassBorder)

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
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)

            TextField(placeholder, text: text)
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
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(bio.count)/\(Self.bioCharacterLimit)")
                    .font(AppFont.caption)
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
                    Label("Accent Color", systemImage: "paintpalette.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(themeManager.theme.displayName)
                        .font(AppFont.caption)
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
            withAnimation(.snappy(duration: 0.2)) {
                selection.wrappedValue = color
            }
            if dataStore.profile.hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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
                        .font(.system(size: 14, weight: .bold))
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

    private var goalsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Goals", systemImage: "target")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(dataStore.profile.goals.count) selected")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }

                Text("Pick what you're optimizing for. Long-press a selected goal to pin it as your primary focus.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)

                if let pinned = dataStore.profile.primaryGoal, !pinned.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.accentLight)
                        Text("Primary: \(pinned)")
                            .font(AppFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                        Spacer()
                        Button("Unpin") {
                            dataStore.setPrimaryGoal(nil)
                        }
                        .font(AppFont.caption)
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
                    ForEach(Self.availableGoals, id: \.self) { goal in
                        goalChip(goal)
                    }
                }
            }
        }
    }

    private func goalChip(_ goal: String) -> some View {
        let selected = dataStore.profile.goals.contains(goal)
        let pinned = dataStore.profile.primaryGoal == goal
        return Button {
            toggleGoal(goal)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: pinned ? "pin.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 12, weight: .semibold))
                Text(goal)
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
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
                        dataStore.setPrimaryGoal(goal)
                        if dataStore.profile.hapticFeedbackEnabled {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } label: {
                        Label("Pin as Primary", systemImage: "pin")
                    }
                }
            }
        }
    }

    private func toggleGoal(_ goal: String) {
        var current = Set(dataStore.profile.goals)
        if current.contains(goal) {
            current.remove(goal)
        } else {
            current.insert(goal)
        }
        dataStore.updateGoals(current)
        if dataStore.profile.hapticFeedbackEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Body Metrics summary

    private var bodyMetricsSummary: some View {
        let metrics = dataStore.profile.bodyMetrics
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Body Metrics", systemImage: "figure.arms.open")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if metrics.isComplete {
                    HStack(spacing: Spacing.lg) {
                        bodyStat("Weight", weightString(metrics))
                        bodyStat("Height", heightString(metrics))
                        bodyStat("Age", metrics.age.map { "\($0)" } ?? "—")
                    }
                } else {
                    Text("Optional — add your weight, height, and age in the Profile tab to display them alongside compliance trends.")
                        .font(AppFont.caption)
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
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weightString(_ m: BodyMetrics) -> String {
        guard let kg = m.weightKg else { return "—" }
        if m.unit == .metric { return "\(Int(kg.rounded())) kg" }
        return "\(Int((kg * 2.20462).rounded())) lb"
    }

    private func heightString(_ m: BodyMetrics) -> String {
        guard let cm = m.heightCm else { return "—" }
        if m.unit == .metric { return "\(Int(cm.rounded())) cm" }
        return "\(Int((cm / 2.54).rounded())) in"
    }

    // MARK: - Stacks

    private var stacksCard: some View {
        let stacks = dataStore.protocols.sorted(by: stackOrdering)
        let activeCount = stacks.filter { $0.status == .active }.count
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Your Stacks", systemImage: "square.stack.3d.up.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if !stacks.isEmpty {
                        Text("\(activeCount) active · \(stacks.count) total")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }

                if stacks.isEmpty {
                    emptyStacksView
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(stacks) { stack in
                            stackRow(stack)
                            if stack.id != stacks.last?.id {
                                Divider().foregroundStyle(AppColor.glassBorder)
                            }
                        }
                    }

                    Button {
                        if dataStore.profile.hapticFeedbackEnabled {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        appState.selectedTab = .protocols
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text("Manage Stacks")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Spacing.xs)
                    }
                    .buttonStyle(ScalePressStyle())
                }
            }
        }
    }

    private var emptyStacksView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.textTertiary)

            Text("No stacks yet")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)

            Text("Create your first protocol from the Protocols tab to start tracking doses, streaks, and compliance.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                appState.selectedTab = .protocols
                dismiss()
            } label: {
                Label("Create Stack", systemImage: "plus")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background {
                        Capsule().fill(AppColor.accentPrimary.opacity(0.25))
                    }
            }
            .buttonStyle(ScalePressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    }

    private func stackOrdering(_ a: PeptideProtocol, _ b: PeptideProtocol) -> Bool {
        if a.status != b.status {
            return statusRank(a.status) < statusRank(b.status)
        }
        return a.startDate > b.startDate
    }

    private func statusRank(_ status: ProtocolStatus) -> Int {
        switch status {
        case .active: 0
        case .paused: 1
        case .completed: 2
        }
    }

    private func stackRow(_ stack: PeptideProtocol) -> some View {
        Button {
            if dataStore.profile.hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            appState.pendingProtocolDeepLink = stack.id
            appState.selectedTab = .protocols
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: stack.status.iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(stackColor(stack.status))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(stack.name)
                            .font(AppFont.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)

                        Text(stackSubtitle(stack))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Text(stack.status.displayName)
                        .font(AppFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(stackColor(stack.status))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(stackColor(stack.status).opacity(0.15))
                        }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                if stack.status == .active {
                    cycleProgressBar(for: stack)
                        .padding(.leading, 34)
                }
            }
            .padding(.vertical, Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    private func cycleProgressBar(for stack: PeptideProtocol) -> some View {
        let progress = stack.cycleProgress
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.surfaceElevated)
                    Capsule()
                        .fill(stackColor(stack.status))
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 4)

            HStack {
                Text("Week \(stack.weekNumber) of \(stack.cycleLengthWeeks)")
                Spacer()
                Text("\(stack.daysRemaining) days left")
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
            .monospacedDigit()
        }
    }

    private func stackSubtitle(_ stack: PeptideProtocol) -> String {
        let abbreviations = stack.peptides.prefix(3).map(\.abbreviation).joined(separator: " · ")
        let extras = stack.peptides.count > 3 ? " +\(stack.peptides.count - 3)" : ""
        let body = abbreviations.isEmpty ? "Empty stack" : abbreviations + extras
        return "\(body) — \(stack.schedule.summary)"
    }

    private func stackColor(_ status: ProtocolStatus) -> Color {
        switch status {
        case .active: AppColor.accentPrimary
        case .paused: AppColor.warning
        case .completed: AppColor.textSecondary
        }
    }

    // MARK: - Achievements

    private var achievementsPreview: some View {
        let unlocked = achievementService.achievements.filter(\.isUnlocked)
            .sorted { ($0.unlockedDate ?? .distantPast) > ($1.unlockedDate ?? .distantPast) }
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Achievements", systemImage: "rosette")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(achievementService.unlockedCount)/\(achievementService.totalCount)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }

                if unlocked.isEmpty {
                    Text("Log doses, build streaks, and create protocols to start unlocking badges.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: Spacing.md) {
                        ForEach(unlocked.prefix(4)) { achievement in
                            achievementBadge(achievement)
                        }
                        if unlocked.count > 4 {
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AppColor.textTertiary)
                                Text("+\(unlocked.count - 4)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textTertiary)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .overlay {
                        Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                    }
                Image(systemName: achievement.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(AppColor.accentLight)
            }
            .frame(width: 44, height: 44)

            Text(achievement.title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Preferences

    private func preferencesCard(store: DataStore) -> some View {
        @Bindable var store = store
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Preferences", systemImage: "slider.horizontal.3")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.bottom, Spacing.xs)

                preferenceToggle(
                    icon: "hand.tap.fill",
                    title: "Haptic Feedback",
                    subtitle: "Vibrate on taps and toggles",
                    isOn: $store.profile.hapticFeedbackEnabled
                )
                .onChange(of: dataStore.profile.hapticFeedbackEnabled) { _, _ in
                    dataStore.persistProfile()
                }

                Divider().foregroundStyle(AppColor.glassBorder)

                preferenceToggle(
                    icon: "bell.fill",
                    title: "Dose Reminders",
                    subtitle: "Get notified for scheduled doses",
                    isOn: $store.profile.doseRemindersEnabled
                )
                .onChange(of: dataStore.profile.doseRemindersEnabled) { _, _ in
                    dataStore.persistProfile()
                }
            }
        }
    }

    private func preferenceToggle(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppColor.accentPrimary)
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
        dataStore.updateProfileIdentity(name: name, bio: bio)
        if avatarData != dataStore.profile.avatarImageData {
            dataStore.updateAvatarImageData(avatarData)
        }
    }

    // MARK: - Photo processing

    @MainActor
    private func processPickedPhoto(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                photoError = "We couldn't read that photo. Try a different image."
                return
            }

            let processed = await Task.detached(priority: .userInitiated) {
                Self.normalize(rawImageData: raw)
            }.value

            if let processed {
                avatarData = processed
            } else {
                photoError = "That image format isn't supported. Try a JPEG or PNG."
            }
        } catch {
            photoError = "We couldn't load that photo. Please try again."
        }
    }

    @MainActor
    private func ingestUIImage(_ image: UIImage) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        let processed = await Task.detached(priority: .userInitiated) {
            Self.normalize(image: image)
        }.value
        if let processed {
            avatarData = processed
        } else {
            photoError = "We couldn't process that photo. Try a different image."
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

    /// Decodes, square-crops to the largest centered square, downscales to
    /// `avatarMaxDimension`, and JPEG-encodes. Performed off the main actor —
    /// large photos can otherwise cause a perceptible UI hitch.
    nonisolated private static func normalize(rawImageData: Data) -> Data? {
        guard let source = UIImage(data: rawImageData) else { return nil }
        return normalize(image: source)
    }

    nonisolated private static func normalize(image: UIImage) -> Data? {
        let cropped = squareCenterCrop(image)
        let downsampled = downscale(cropped, maxDimension: avatarMaxDimension)
        return downsampled.jpegData(compressionQuality: avatarJPEGQuality)
    }

    /// Returns the largest centered square from the image, accounting for
    /// `imageOrientation` so portrait shots aren't sliced sideways.
    nonisolated private static func squareCenterCrop(_ image: UIImage) -> UIImage {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0, size.width != size.height else { return image }
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            image.draw(in: CGRect(x: -originX, y: -originY, width: size.width, height: size.height))
        }
    }

    nonisolated private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension, largest > 0 else { return image }
        let scale = maxDimension / largest
        let newSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Compact grid picker for the built-in symbol-on-gradient avatars. Lives in
/// the same file as `ProfileCustomizationSheet` because it's only ever used
/// from there and shares its rendering pipeline.
private struct AvatarPresetPickerSheet: View {
    let hapticEnabled: Bool
    let onPick: (AvatarPreset) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: Spacing.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(AvatarPreset.all) { preset in
                        Button {
                            if hapticEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            onPick(preset)
                        } label: {
                            tile(for: preset)
                        }
                        .buttonStyle(ScalePressStyle())
                    }
                }
                .padding(Spacing.lg)
            }
            .background(AppColor.background)
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func tile(for preset: AvatarPreset) -> some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: preset.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                    }
                Image(systemName: preset.symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .liquidGlass(.circle)
        }
        .frame(maxWidth: .infinity)
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
