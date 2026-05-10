import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.requestReview) private var requestReview
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"

    @State private var currentPage = 0
    @State private var name: String = ""
    @State private var selectedGoals: Set<String> = []
    @State private var bodyMetrics: BodyMetrics = .unspecified
    @State private var selectedRecommendationIds: Set<UUID> = []
    @State private var hasAutoSelectedRecommendations = false
    @State private var requestingHealth = false
    @State private var requestingNotifications = false
    @State private var bounceTrigger = 0
    @State private var authService = AuthService.shared
    /// Observed so the picker step re-renders the moment the user taps a
    /// new theme — `AppColor.accent*` reads from this manager, so anything
    /// touching `themeManager.theme` in body forces a full re-render.
    @State private var themeManager = ThemeManager.shared

    // Creator attribution step state. Lives on the parent so the footer
    // (apply / skip / continue buttons) and the input field can share it
    // and so the validated attribution survives a back-and-forward swipe.
    @State private var creatorCodeInput: String = ""
    @State private var creatorAttribution: CreatorAttribution?
    @State private var creatorCodeError: String?

    // Email-capture step state. Same pattern as the creator attribution —
    // input lives on the parent so the field survives swipe navigation.
    @State private var emailInput: String = ""
    @State private var emailError: String?

    @FocusState private var nameFocused: Bool

    private let totalPages = 17
    @State private var storeService = StoreService.shared

    private struct OnboardingGoal: Identifiable {
        var id: String { title }
        /// Canonical English string used as the persistence key in
        /// `profile.goals` and the keyword input to the recommendation
        /// engine. Do NOT change without a migration.
        let title: String
        /// Localized display key — same English string at literal time, but
        /// flows through Xcode's xcstrings extraction and the user's locale.
        let localizedTitle: LocalizedStringKey
        let icon: String
        let tint: Color
    }

    private let goals: [OnboardingGoal] = [
        .init(title: "Muscle Recovery",  localizedTitle: "Muscle Recovery",  icon: "figure.strengthtraining.traditional", tint: OnboardingTint.muscleRecovery),
        .init(title: "Better Sleep",     localizedTitle: "Better Sleep",     icon: "moon.stars.fill",         tint: OnboardingTint.sleep),
        .init(title: "Cognitive Edge",   localizedTitle: "Cognitive Edge",   icon: "brain.head.profile.fill", tint: OnboardingTint.cognitive),
        .init(title: "Anti-Aging",       localizedTitle: "Anti-Aging",       icon: "sparkles",                tint: OnboardingTint.antiAging),
        .init(title: "Fat Loss",         localizedTitle: "Fat Loss",         icon: "flame.fill",              tint: OnboardingTint.fatLoss),
        .init(title: "Immune Support",   localizedTitle: "Immune Support",   icon: "shield.lefthalf.filled",  tint: OnboardingTint.immune),
        .init(title: "Joint Health",     localizedTitle: "Joint Health",     icon: "figure.flexibility",      tint: AppColor.accentPrimary),
        .init(title: "Stress Reduction", localizedTitle: "Stress Reduction", icon: "leaf.fill",               tint: AppColor.accentLight),
    ]

    var body: some View {
        // Reading the @Observable properties registers this view as a
        // dependency, so the entire onboarding tree (back button tint,
        // progress bar gradient, page accents…) re-renders the moment the
        // user picks a different theme on the "Make it yours" step.
        let _ = themeManager.theme
        let _ = themeManager.displayMode

        return ZStack {
            OnboardingBackground(step: currentPage)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    goalsPage.tag(2)
                    bodyMetricsPage.tag(3)
                    dailyTargetsPage.tag(4)
                    recommendationsPage.tag(5)
                    experiencePage.tag(6)
                    healthKitPage.tag(7)
                    notificationsPage.tag(8)
                    signInPage.tag(9)
                    reviewPromptPage.tag(10)
                    creatorAttributionPage.tag(11)
                    emailCapturePage.tag(12)
                    offerPage.tag(13)
                    themeChoicePage.tag(14)
                    addMedicationPreviewPage.tag(15)
                    readyPage.tag(16)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.springSmooth, value: currentPage)
            }
        }
        .preferredColorScheme(themeManager.displayMode.preferredScheme)
        .onChange(of: currentPage) { _, newValue in
            dismissKeyboard()
            if newValue == 5 && !hasAutoSelectedRecommendations {
                let top = currentSuggestions.prefix(2).map(\.peptide.id)
                selectedRecommendationIds = Set(top)
                hasAutoSelectedRecommendations = true
            }
            // If the user lands on the sign-in page already authenticated
            // (e.g. Keychain survived a re-onboard), still show the
            // confirmation briefly and advance — never strand them here.
            if newValue == 9 && authService.isSignedIn {
                scheduleSignInAdvance()
            }
        }
        .onChange(of: selectedGoals) { _, _ in
            hasAutoSelectedRecommendations = false
            selectedRecommendationIds.removeAll()
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            if signedIn, currentPage == 9 {
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                scheduleSignInAdvance()
            }
        }
        .alert(
            authService.lastError?.title ?? "",
            isPresented: Binding(
                get: { authService.lastError != nil && currentPage == 9 },
                set: { if !$0 { authService.clearLastError() } }
            ),
            presenting: authService.lastError
        ) { _ in
            Button("Try Again") {
                authService.clearLastError()
                authService.signIn()
            }
            Button("Continue Without Signing In", role: .cancel) {
                authService.clearLastError()
                advance(to: nextAfterSignIn)
            }
        } message: { error in
            Text(error.message)
        }
        .task { await storeService.loadProducts() }
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "flask.fill", size: 110, bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.md) {
                    Text("Welcome to PeptideX")
                        .font(AppFont.largeTitle)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColor.textPrimary, AppColor.accentLight],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .multilineTextAlignment(.center)

                    (Text("Track your ")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                    + Text("peptide protocols")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                    + Text(" with precision")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)

                    HStack(spacing: Spacing.md) {
                        WelcomeFeatureBadge(
                            icon: "calendar.badge.clock",
                            label: "Smart\nScheduling",
                            animationDelay: 0.20
                        )
                        WelcomeFeatureBadge(
                            icon: "heart.text.square.fill",
                            label: "Health\nInsights",
                            animationDelay: 0.32
                        )
                        WelcomeFeatureBadge(
                            icon: "lock.shield.fill",
                            label: "Private &\nSecure",
                            animationDelay: 0.44
                        )
                    }
                    .padding(.top, Spacing.md)
                }
            },
            footer: {
                GlassButton(title: "Get Started", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    advance(to: 1)
                }
            }
        )
    }

    // MARK: - Page 1: Name

    private var namePage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "person.crop.circle.fill", size: 96, bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.md) {
                    Text("What should we call you?")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Optional — we'll use it to personalize your dashboard")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)

                    GlassTextField(placeholder: "Your name", text: $name, icon: "person.fill")
                        .focused($nameFocused)
                        .submitLabel(.next)
                        .onSubmit { advance(to: 2) }
                        .padding(.top, Spacing.lg)
                }
            },
            footer: {
                GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    advance(to: 2)
                }
            }
        )
    }

    // MARK: - Page 2: Goals

    private var goalsPage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "target", size: 80, bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.md) {
                    Text("What are your goals?")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(selectedGoals.isEmpty
                         ? "Select all that apply"
                         : "\(selectedGoals.count) selected — tap any tile")
                        .font(AppFont.subheadline)
                        .foregroundStyle(selectedGoals.isEmpty ? AppColor.textSecondary : AppColor.accentLight)
                        .contentTransition(.numericText())
                        .animation(AppAnimation.springSnappy, value: selectedGoals.count)

                    goalGrid
                        .padding(.top, Spacing.sm)
                }
            },
            footer: {
                GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    advance(to: 3)
                }
                .opacity(selectedGoals.isEmpty ? 0.4 : 1)
                .disabled(selectedGoals.isEmpty)
                .animation(AppAnimation.springSnappy, value: selectedGoals.isEmpty)
            }
        )
    }

    // MARK: - Page 3: Body Metrics

    private var bodyMetricsPage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "figure.arms.open", size: 88, bounceTrigger: bounceTrigger),
            content: {
                BodyMetricsPage(metrics: $bodyMetrics)
            },
            footer: {
                VStack(spacing: Spacing.sm) {
                    GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                        advance(to: 4)
                    }
                    GlassButton(title: "Skip for now", style: .ghost, isFullWidth: true) {
                        // Skip past Daily Targets too — without body stats it
                        // has nothing to compute and would render placeholders.
                        advance(to: 5)
                    }
                }
            }
        )
    }

    // MARK: - Page 4: Daily Targets

    private var dailyTargetsPage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "fork.knife.circle.fill", size: 88, bounceTrigger: bounceTrigger),
            content: {
                DailyTargetsPage(metrics: bodyMetrics)
            },
            footer: {
                GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    advance(to: 5)
                }
            }
        )
    }

    // MARK: - Page 5: Recommended Stack

    private var recommendationsPage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "sparkle.magnifyingglass", size: 88, bounceTrigger: bounceTrigger),
            content: {
                RecommendationsPage(
                    suggestions: currentSuggestions,
                    selectedIds: $selectedRecommendationIds
                )
            },
            footer: {
                VStack(spacing: Spacing.sm) {
                    GlassButton(
                        title: starterButtonTitle,
                        icon: selectedRecommendationIds.isEmpty ? "arrow.right" : "checkmark.circle.fill",
                        style: .primary,
                        isFullWidth: true
                    ) {
                        advance(to: 6)
                    }
                    GlassButton(title: "Skip for now", style: .ghost, isFullWidth: true) {
                        selectedRecommendationIds.removeAll()
                        advance(to: 6)
                    }
                }
            }
        )
    }

    private var currentSuggestions: [OnboardingRecommendationEngine.Suggestion] {
        OnboardingRecommendationEngine.recommend(
            goals: Array(selectedGoals),
            from: dataStore.peptideDatabase
        )
    }

    private var starterButtonTitle: LocalizedStringKey {
        if selectedRecommendationIds.isEmpty { return "Continue without a stack" }
        let count = selectedRecommendationIds.count
        if count == 1 { return "Add 1 peptide & continue" }
        return "Add \(count) peptides & continue"
    }

    /// Builds a short, human-readable name from the user's primary goal —
    /// e.g. "Muscle Recovery Stack". Falls back to "Starter Stack" when no
    /// goal is selected so we never produce an empty name.
    private var starterProtocolName: String {
        guard let primary = selectedGoals.sorted().first else { return "Starter Stack" }
        return "\(primary) Stack"
    }

    private var goalGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
            spacing: Spacing.sm
        ) {
            ForEach(goals) { goal in
                goalTile(goal)
            }
        }
    }

    private func goalTile(_ goal: OnboardingGoal) -> some View {
        let isSelected = selectedGoals.contains(goal.title)
        return Button {
            withAnimation(AppAnimation.springSnappy) {
                if isSelected {
                    selectedGoals.remove(goal.title)
                } else {
                    selectedGoals.insert(goal.title)
                }
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: goal.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? goal.tint : AppColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? goal.tint.opacity(0.18) : AppColor.surfaceElevated)
                        }
                        .symbolEffect(.bounce, value: isSelected)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? goal.tint : AppColor.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }

                Text(goal.localizedTitle)
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? goal.tint.opacity(0.10) : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? goal.tint.opacity(0.45) : AppColor.glassBorder,
                                lineWidth: isSelected ? 1.0 : 0.5
                            )
                    }
            }
            .liquidGlass(
                .rect(cornerRadius: Spacing.smallCornerRadius),
                tint: isSelected ? goal.tint.opacity(0.45) : nil,
                interactive: true
            )
            .scaleEffect(isSelected ? 1.0 : 0.985)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 6: Experience Level

    private var experiencePage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "graduationcap.fill", size: 84, bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.md) {
                    Text("How experienced are you?")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("This adjusts the level of detail shown")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: Spacing.md) {
                        experienceOption(level: "beginner", icon: "leaf.fill",
                                          title: "Beginner", subtitle: "New to peptides")
                        experienceOption(level: "intermediate", icon: "flame.fill",
                                          title: "Intermediate", subtitle: "Some protocol experience")
                        experienceOption(level: "advanced", icon: "bolt.fill",
                                          title: "Advanced", subtitle: "Experienced researcher")
                    }
                    .padding(.top, Spacing.sm)
                }
            },
            footer: {
                GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    advance(to: 7)
                }
            }
        )
    }

    private func experienceOption(level: String, icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        let isSelected = experienceLevel == level
        return Button {
            withAnimation(AppAnimation.springSnappy) { experienceLevel = level }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            HStack(spacing: Spacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(isSelected ? AppColor.glassTint : AppColor.surfaceElevated)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                            }
                    }
                    .symbolEffect(.bounce, value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? AppColor.accentPrimary.opacity(0.10) : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                lineWidth: isSelected ? 1.0 : 0.5
                            )
                    }
            }
            .liquidGlass(
                .rect(cornerRadius: Spacing.cardCornerRadius),
                tint: isSelected ? AppColor.accentPrimary.opacity(0.35) : nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 7: HealthKit

    private var healthKitPage: some View {
        permissionPage(
            icon: "heart.text.square.fill",
            title: "Connect Apple Health",
            subtitle: "Correlate protocol compliance with HRV, sleep, and activity. PeptideX never writes to your health data.",
            bullets: [
                ("waveform.path.ecg", "HRV & resting heart rate"),
                ("bed.double.fill", "Sleep quality trends"),
                ("figure.walk", "Activity & recovery load"),
            ],
            primaryTitle: "Connect Health",
            primaryIcon: "heart.fill",
            requesting: requestingHealth
        ) {
            requestingHealth = true
            Task {
                let granted = await HealthKitService.shared.requestAuthorization()
                requestingHealth = false
                if dataStore.profile.healthConnected != granted {
                    dataStore.profile.healthConnected = granted
                    dataStore.persistProfile()
                }
                if currentPage == 7 { advance(to: 8) }
            }
        } onSkip: {
            advance(to: 8)
        }
    }

    // MARK: - Page 8: Notifications

    private var notificationsPage: some View {
        pageScaffold(
            hero: EmptyView(),
            content: {
                VStack(spacing: Spacing.lg) {
                    VStack(spacing: Spacing.sm) {
                        Text("Consistency is everything.")
                            .font(AppFont.largeTitle)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColor.textPrimary, AppColor.accentLight],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .multilineTextAlignment(.center)

                        Text("People who track their protocols achieve significantly better results over time.")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.md)
                    }

                    ConsistencyChart()
                        .padding(.top, Spacing.sm)

                    NotificationPreviewCard()
                        .padding(.top, Spacing.xs)
                }
            },
            footer: {
                VStack(spacing: Spacing.sm) {
                    GlassButton(
                        title: requestingNotifications ? "Requesting…" : "Enable reminders",
                        icon: "bell.fill",
                        style: .primary,
                        isFullWidth: true,
                        action: requestNotificationPermission
                    )
                    .disabled(requestingNotifications)

                    GlassButton(
                        title: "Skip for now",
                        style: .ghost,
                        isFullWidth: true
                    ) {
                        advance(to: 9)
                    }
                    .disabled(requestingNotifications)
                }
            }
        )
    }

    private func requestNotificationPermission() {
        requestingNotifications = true
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            requestingNotifications = false
            if dataStore.profile.doseRemindersEnabled != granted {
                dataStore.profile.doseRemindersEnabled = granted
                dataStore.persistProfile()
            }
            // Advance regardless of permission outcome — the spec says the
            // user shouldn't be stranded if they decline.
            if currentPage == 8 { advance(to: 9) }
        }
    }

    private func permissionPage(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        bullets: [(String, LocalizedStringKey)],
        primaryTitle: LocalizedStringKey,
        primaryIcon: String,
        requesting: Bool,
        onConnect: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        pageScaffold(
            hero: HeroIcon(symbol: icon, size: 92, bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.lg) {
                    VStack(spacing: Spacing.md) {
                        Text(title)
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.lg)
                    }

                    VStack(spacing: Spacing.sm) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                            permissionBullet(icon: bullet.0, label: bullet.1)
                        }
                    }
                    .padding(.top, Spacing.sm)
                }
            },
            footer: {
                VStack(spacing: Spacing.sm) {
                    GlassButton(
                        title: requesting ? "Requesting..." : primaryTitle,
                        icon: primaryIcon,
                        style: .primary,
                        isFullWidth: true,
                        action: onConnect
                    )
                    .disabled(requesting)

                    GlassButton(title: "Skip", style: .ghost, isFullWidth: true, action: onSkip)
                        .disabled(requesting)
                }
            }
        )
    }

    private func permissionBullet(icon: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(AppColor.glassTint)
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }

            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    // MARK: - Page 9: Sign in with Apple

    private var signInPage: some View {
        pageScaffold(
            hero: HeroIcon(symbol: "icloud.fill", size: 92, bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.md) {
                    Text("Sync across devices")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Sign in with your Apple ID to back up and sync your protocols. All features work without signing in.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
            },
            footer: {
                if authService.isSignedIn {
                    signedInConfirmation
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    VStack(spacing: Spacing.sm) {
                        ZStack {
                            AppleSignInButton(cornerRadius: 26) {
                                authService.signIn()
                            }
                            .frame(height: 52)
                            .opacity(authService.isSigningIn ? 0.5 : 1)
                            .allowsHitTesting(!authService.isSigningIn)

                            if authService.isSigningIn {
                                HStack(spacing: Spacing.sm) {
                                    ProgressView().tint(.black)
                                    Text("Signing in…")
                                        .font(AppFont.subheadline)
                                        .foregroundStyle(.black)
                                }
                                .allowsHitTesting(false)
                            }
                        }

                        GlassButton(title: "Continue without signing in", style: .ghost, isFullWidth: true) {
                            advance(to: nextAfterSignIn)
                        }
                    }
                    .transition(.opacity)
                }
            }
        )
        .animation(AppAnimation.springSnappy, value: authService.isSignedIn)
    }

    private var signedInConfirmation: some View {
        HStack(spacing: Spacing.md) {
            PulsatingDot(color: AppColor.accentPrimary, size: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Signed In")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(authService.userDisplayName ?? authService.userEmail ?? "Apple ID connected")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.bounce, value: authService.isSignedIn)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.accentPrimary.opacity(0.45), lineWidth: 1)
                }
        }
    }

    // MARK: - Page 10: Review Prompt (social proof before paywall)

    /// Always advance to the review prompt after sign-in. The review page is
    /// shown to everyone — Pro users may still want to leave a review — and
    /// the offer page (11) self-skips for ineligible / already-Pro users.
    private var nextAfterSignIn: Int { 10 }

    private var reviewPromptPage: some View {
        pageScaffold(
            hero: EmptyView(),
            content: { ReviewPromptPage() },
            footer: {
                // Single CTA. Tapping "Continue" both fires the App Store
                // review request and advances to the creator-attribution step.
                // The cooldown gate inside ReviewPromptService still applies,
                // so re-onboarding never burns a second prompt within 90 days.
                GlassButton(
                    title: "Continue",
                    icon: "arrow.right",
                    style: .primary,
                    isFullWidth: true
                ) {
                    ReviewPromptService.shared.requestReviewOnUserAction(using: requestReview)
                    if dataStore.profile.hapticFeedbackEnabled {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    advance(to: 11)
                }
            }
        )
    }

    // MARK: - Page 11: Creator Attribution (referral code)

    private var creatorAttributionPage: some View {
        pageScaffold(
            hero: EmptyView(),
            content: {
                CreatorAttributionPage(
                    input: $creatorCodeInput,
                    attribution: creatorAttribution,
                    error: creatorCodeError
                )
            },
            footer: {
                VStack(spacing: Spacing.sm) {
                    if creatorAttribution != nil {
                        GlassButton(
                            title: "Continue",
                            icon: "arrow.right",
                            style: .primary,
                            isFullWidth: true
                        ) {
                            advance(to: 12)
                        }
                    } else {
                        GlassButton(
                            title: "Apply",
                            icon: "checkmark.circle.fill",
                            style: .primary,
                            isFullWidth: true,
                            action: applyCreatorCode
                        )
                        .disabled(creatorCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    GlassButton(title: "Skip for now", style: .ghost, isFullWidth: true) {
                        advance(to: 12)
                    }
                }
            }
        )
    }

    /// Validates the typed code against the local seeded list and updates
    /// the success / error state. The validated attribution is persisted
    /// to the profile in `finishOnboarding` rather than here so swiping
    /// back and re-applying a different code doesn't strand stale data.
    private func applyCreatorCode() {
        if let match = CreatorCodeService.lookup(creatorCodeInput) {
            withAnimation(AppAnimation.springSnappy) {
                creatorAttribution = match
                creatorCodeError = nil
            }
            if dataStore.profile.hapticFeedbackEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            withAnimation(AppAnimation.springSnappy) {
                creatorCodeError = "Code not found — double-check and try again"
            }
            if dataStore.profile.hapticFeedbackEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Page 12: Email Capture (mailing-list opt-in)

    private var emailCapturePage: some View {
        pageScaffold(
            hero: EmptyView(),
            content: {
                EmailCapturePage(input: $emailInput, error: emailError)
            },
            footer: {
                VStack(spacing: Spacing.sm) {
                    GlassButton(
                        title: "Send me updates",
                        icon: "paperplane.fill",
                        style: .primary,
                        isFullWidth: true,
                        action: submitEmail
                    )
                    .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty)

                    GlassButton(title: "Skip for now", style: .ghost, isFullWidth: true) {
                        advance(to: 13)
                    }
                }
            }
        )
    }

    /// Validates the typed email and, on success, persists it to the
    /// profile and advances to the paywall. The spec'd Supabase insert /
    /// Resend welcome email / 7-day pg_cron retargeting all need a
    /// backend that doesn't exist in this repo today — once it ships, the
    /// stored EmailSubscription is the source of truth a sync job can
    /// drain into the email_subscribers table.
    private func submitEmail() {
        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.looksLikeEmail else {
            withAnimation(AppAnimation.springSnappy) {
                emailError = "That doesn't look like an email address."
            }
            if dataStore.profile.hapticFeedbackEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            return
        }

        emailError = nil
        dataStore.profile.emailSubscription = EmailSubscription(
            email: trimmed,
            capturedAt: Date()
        )
        dataStore.persistProfile()

        if dataStore.profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        advance(to: 13)
    }

    // MARK: - Page 13: Free-Trial Funnel

    @ViewBuilder
    private var offerPage: some View {
        if storeService.isProUser || !storeService.isEligibleForMonthlyTrial {
            Color.clear.onAppear {
                if currentPage == 13 { advance(to: 14) }
            }
        } else {
            TrialOfferView(
                onAccept: { advance(to: 14) },
                onDecline: { advance(to: 14) }
            )
        }
    }

    // MARK: - Page 14: Theme Choice ("Make it yours")

    private var themeChoicePage: some View {
        pageScaffold(
            hero: EmptyView(),
            content: { ThemeChoicePage(theme: themeManager) },
            footer: {
                GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    advance(to: 15)
                }
            }
        )
    }

    // MARK: - Page 15: Add Medication Preview

    private var addMedicationPreviewPage: some View {
        pageScaffold(
            hero: EmptyView(),
            content: { AddMedicationPreviewPage() },
            footer: {
                GlassButton(title: "Add Medication", icon: "plus", style: .primary, isFullWidth: true) {
                    advance(to: 16)
                }
            }
        )
    }

    // MARK: - Page 16: Ready

    private var readyPage: some View {
        pageScaffold(
            hero: ReadyHero(bounceTrigger: bounceTrigger),
            content: {
                VStack(spacing: Spacing.md) {
                    if storeService.isProUser {
                        proCelebrationBadge
                    }

                    Text(readyHeadline)
                        .font(AppFont.largeTitle)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColor.textPrimary, AppColor.accentLight],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .multilineTextAlignment(.center)

                    (Text("Your dashboard is ready. Start tracking your ")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                    + Text("peptide protocols")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight))
                        .multilineTextAlignment(.center)

                    setupSummaryCard
                        .padding(.top, Spacing.md)

                    disclaimerCard
                }
            },
            footer: {
                GlassButton(title: "I Understand — Let's Go", icon: "arrow.right", style: .primary, isFullWidth: true) {
                    finishOnboarding()
                }
            }
        )
    }

    private var readyHeadline: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "You're all set!" }
        return "You're all set, \(trimmed)!"
    }

    /// Recap card showing the choices the user just made so the moment of
    /// completion feels like real progress, not just a "Done" tap. Hidden
    /// rows fall through silently when the corresponding step was skipped.
    private var setupSummaryCard: some View {
        let goalCount = selectedGoals.count
        let recCount = selectedRecommendationIds.count

        return GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                    Text("WHAT WE SET UP")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(AppColor.accentLight)
                }

                VStack(spacing: Spacing.sm) {
                    if goalCount > 0 {
                        summaryRow(
                            icon: "target",
                            text: goalCount == 1
                                ? "1 goal selected"
                                : "\(goalCount) goals selected"
                        )
                    }
                    if bodyMetrics.isComplete {
                        summaryRow(
                            icon: "figure.arms.open",
                            text: "Body metrics saved"
                        )
                    }
                    if recCount > 0 {
                        summaryRow(
                            icon: "flask.fill",
                            text: recCount == 1
                                ? "1 peptide added to your starter stack"
                                : "\(recCount) peptides added to your starter stack"
                        )
                    }
                    if dataStore.profile.healthConnected {
                        summaryRow(icon: "heart.fill", text: "Apple Health connected")
                    }
                    if dataStore.profile.doseRemindersEnabled {
                        summaryRow(icon: "bell.fill", text: "Dose reminders enabled")
                    }
                    if authService.isSignedIn {
                        summaryRow(icon: "person.crop.circle.fill", text: "Signed in with Apple")
                    }
                }
            }
        }
    }

    private func summaryRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(AppColor.accentPrimary.opacity(0.2))
                }
            Text(text)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
        }
    }

    private var proCelebrationBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.accentLight)
            Text("Pro Trial Active — Welcome aboard!")
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule()
                .fill(AppColor.accentPrimary.opacity(0.18))
                .overlay(Capsule().strokeBorder(AppColor.accentPrimary.opacity(0.4), lineWidth: 0.5))
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var disclaimerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("Before you continue")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                }

                Text(PeptideDatabase.disclaimer)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func pageScaffold<Hero: View, Content: View, Footer: View>(
        hero: Hero,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) -> some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: Spacing.lg)

                    hero
                        .padding(.bottom, Spacing.xl)

                    content()
                        .padding(.horizontal, Spacing.screenPadding)

                    Spacer(minLength: Spacing.lg)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer()
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
    }

    private func advance(to page: Int) {
        dismissKeyboard()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(AppAnimation.springSmooth) {
            currentPage = page
            bounceTrigger &+= 1
        }
    }

    /// Top strip combining a back chevron + the progress bar. Wrapped in a
    /// LiquidGlassContainer so on iOS 26 the chevron and the progress capsules
    /// share one rendering pass — same trick the system tab bar uses to make
    /// its glass shapes feel like one continuous material.
    private var topBar: some View {
        LiquidGlassContainer(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                backButton
                    .opacity(canGoBack ? 1 : 0)
                    .frame(width: canGoBack ? 36 : 0)
                    .animation(AppAnimation.springSnappy, value: canGoBack)

                OnboardingProgressBar(current: currentPage, total: totalPages)
            }
        }
    }

    private var canGoBack: Bool {
        // Welcome (0) has nothing behind it. Pages 10–13 (review prompt,
        // creator attribution, email capture, offer) are intentionally
        // one-way — going back from any of them would either re-fire the
        // review request, re-trigger the sign-in flow, or land the user
        // on the auto-skipping offer page in a loop.
        currentPage > 0 && !(10...13).contains(currentPage)
    }

    private var backButton: some View {
        Button(action: goBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Circle().fill(AppColor.cardOverlay)
                        }
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
                .liquidGlass(.circle, interactive: true)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Go back")
    }

    private func goBack() {
        guard canGoBack else { return }
        // The trial-offer page (13) is in the back-disabled range, so a
        // user navigating back from theme (14) would otherwise land on
        // a screen that hides the back button — a dead end. Always skip
        // past the offer page on the way back, regardless of trial
        // eligibility. From Ready (16) and add-medication preview (15)
        // the back walk proceeds normally to the theme step first.
        let target: Int
        if currentPage == 14 {
            target = 12
        } else {
            target = currentPage - 1
        }
        advance(to: max(0, target))
    }

    /// Holds the sign-in page for ~1.4 s so the "Signed In" confirmation
    /// animation is actually visible, then advances. Used by both the
    /// fresh-sign-in path and the already-authenticated re-onboard path.
    private func scheduleSignInAdvance() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            if currentPage == 9 {
                advance(to: nextAfterSignIn)
            }
        }
    }

    private func dismissKeyboard() {
        nameFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
    }

    private func finishOnboarding() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? (AuthService.shared.userDisplayName ?? "") : trimmed
        if dataStore.profile.name != resolved || dataStore.profile.bio.isEmpty == false {
            dataStore.updateProfileIdentity(name: resolved, bio: dataStore.profile.bio)
        }
        if !selectedGoals.isEmpty {
            dataStore.profile.goals = Array(selectedGoals).sorted()
        }
        dataStore.profile.bodyMetrics = bodyMetrics
        // Pre-fill the Lifestyle tab from the daily-targets calculation
        // so the user lands on a populated screen on first run. Skipped
        // when body stats are incomplete — `dailyTargets` returns nil and
        // the Lifestyle tab can re-prompt later.
        if let targets = NutritionMath.dailyTargets(for: bodyMetrics) {
            dataStore.profile.nutritionTargets = targets
        }
        // Persist creator attribution if a code was applied — survives
        // re-launches via the profile JSON. The Supabase install / conversion
        // counters spec'd alongside this will read from the same field once
        // the backend pipeline lands.
        if let attribution = creatorAttribution {
            dataStore.profile.creatorAttribution = attribution
        }
        dataStore.persistProfile()

        if !selectedRecommendationIds.isEmpty {
            let chosen = currentSuggestions
                .filter { selectedRecommendationIds.contains($0.peptide.id) }
                .map(\.peptide)
            if !chosen.isEmpty {
                dataStore.adoptStarterProtocol(
                    peptides: chosen,
                    name: starterProtocolName
                )
            }
        }

        if dataStore.profile.hapticFeedbackEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        withAnimation(AppAnimation.springSnappy) {
            hasCompleted = true
        }
    }
}

// WelcomeFeatureBadge and ReadyHero live in Onboarding/Components/.

#Preview {
    OnboardingView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
