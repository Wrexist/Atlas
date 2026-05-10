import PhotosUI
import SwiftUI

/// Detailed profile customization surface presented from the Home tab when the
/// user taps the avatar in the WelcomeHeader. Lets the user upload a profile
/// image, edit identity (name, bio, pronouns), review goals, see the stacks
/// they've created, and tweak app-wide preferences without leaving Home.
struct ProfileCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore

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

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var pronouns: String = ""
    @State private var avatarData: Data?
    @State private var photoSelection: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var photoError: String?
    @State private var isConfirmingRemoveAvatar = false

    var body: some View {
        @Bindable var store = dataStore

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    avatarSection
                        .sectionAppear(index: 0)

                    identityCard
                        .sectionAppear(index: 1)

                    goalsCard
                        .sectionAppear(index: 2)

                    bodyMetricsSummary
                        .sectionAppear(index: 3)

                    stacksCard
                        .sectionAppear(index: 4)

                    preferencesCard(store: store)
                        .sectionAppear(index: 5)
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

                PhotosPicker(
                    selection: $photoSelection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
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

            HStack(spacing: Spacing.sm) {
                PhotosPicker(
                    selection: $photoSelection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        avatarData == nil ? "Upload Photo" : "Replace Photo",
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
    }

    private var avatarCircle: some View {
        let size: CGFloat = 110
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
                        .fill(AppColor.accentPrimary.opacity(0.2))
                    if let initial = displayInitial {
                        Text(initial)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.accentLight)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 44))
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
        .shadow(color: AppColor.accentGlow, radius: 14, y: 4)
    }

    private var displayInitial: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first).uppercased()
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

                identityField(
                    title: "Pronouns",
                    placeholder: "e.g. they/them",
                    text: $pronouns
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

    // MARK: - Goals

    private var goalsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Goals", systemImage: "target")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                Text("Pick what you're optimizing for. We use these to surface relevant peptides and stack recommendations.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)

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
        return Button {
            toggleGoal(goal)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
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
        let stacks = dataStore.protocols
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Your Stacks", systemImage: "square.stack.3d.up.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(stacks.isEmpty ? "" : "\(stacks.count)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .monospacedDigit()
                }

                if stacks.isEmpty {
                    Text("No stacks yet. Create your first protocol from the Protocols tab to start tracking doses.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: Spacing.xs) {
                        ForEach(stacks.sorted(by: stackOrdering)) { stack in
                            stackRow(stack)
                            if stack.id != stacks.last?.id {
                                Divider().foregroundStyle(AppColor.glassBorder)
                            }
                        }
                    }
                }
            }
        }
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
        }
        .padding(.vertical, Spacing.xxs)
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
        pronouns = profile.pronouns
        avatarData = profile.avatarImageData
    }

    private func commit() {
        dataStore.updateProfileIdentity(name: name, bio: bio, pronouns: pronouns)
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

    /// Decodes, downscales (longest edge → `avatarMaxDimension`), and re-encodes
    /// the picked image as JPEG. Performed off the main actor — large photos
    /// can otherwise cause a perceptible UI hitch.
    nonisolated private static func normalize(rawImageData: Data) -> Data? {
        guard let source = UIImage(data: rawImageData) else { return nil }
        let target = downscale(source, maxDimension: avatarMaxDimension)
        return target.jpegData(compressionQuality: avatarJPEGQuality)
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

#Preview("With Profile") {
    ProfileCustomizationSheet()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}

#Preview("Empty Profile") {
    ProfileCustomizationSheet()
        .environment(DataStore())
        .preferredColorScheme(.dark)
}
