@preconcurrency import AuthenticationServices
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"

    @State private var currentPage = 0
    @State private var name: String = ""
    @State private var selectedGoals: Set<String> = []
    @State private var appeared = false
    @State private var requestingHealth = false
    @State private var requestingNotifications = false
    @State private var heroPulse = false

    @FocusState private var nameFocused: Bool
    @Namespace private var indicatorNamespace
    @Namespace private var goalNamespace
    @Namespace private var experienceNamespace

    private let totalPages = 8
    private let goals = [
        "Muscle Recovery", "Better Sleep", "Cognitive Enhancement", "Anti-Aging",
        "Fat Loss", "Immune Support", "Joint Health", "Stress Reduction",
    ]

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            ambientGlow

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    goalsPage.tag(2)
                    experiencePage.tag(3)
                    healthKitPage.tag(4)
                    notificationsPage.tag(5)
                    signInPage.tag(6)
                    readyPage.tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.springSmooth, value: currentPage)

                pageIndicator
                    .padding(.bottom, Spacing.xl)
            }
        }
        .onAppear {
            appeared = true
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                    heroPulse = true
                }
            }
        }
        .onChange(of: currentPage) { _, _ in
            dismissKeyboard()
        }
    }

    // MARK: - Ambient background

    private var ambientGlow: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(
                        x: -geo.size.width * 0.25,
                        y: -geo.size.height * (heroPulse ? 0.32 : 0.28)
                    )

                Circle()
                    .fill(AppColor.accentLight.opacity(0.10))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 100)
                    .offset(
                        x: geo.size.width * 0.30,
                        y: geo.size.height * (heroPulse ? 0.30 : 0.34)
                    )
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "flask.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.pulse.wholeSymbol, options: .repeating, isActive: !reduceMotion)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.5)
                .animation(AppAnimation.springBouncy.delay(0.2), value: appeared)
                .heroGlow()

            VStack(spacing: Spacing.md) {
                Text("Welcome to PeptideX")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                (Text("Track your ")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("peptide protocols")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColor.accentLight)
                + Text(" with precision")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            GlassButton(title: "Get Started", icon: "arrow.right", style: .primary, isFullWidth: true) {
                advance(to: 1)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Page 2: Name

    private var namePage: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.accentPrimary)
                .heroGlow()

            VStack(spacing: Spacing.md) {
                Text("What should we call you?")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Optional — used to personalize your dashboard")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            GlassTextField(placeholder: "Your name", text: $name, icon: "person.fill")
                .focused($nameFocused)
                .submitLabel(.next)
                .onSubmit { advance(to: 2) }
                .padding(.horizontal, Spacing.screenPadding)

            Spacer()

            GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                advance(to: 2)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Page 3: Goals

    private var goalsPage: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text("What are your goals?")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text("Select all that apply")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
            }

            goalGrid
                .padding(.horizontal, Spacing.screenPadding)

            Spacer()

            GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                advance(to: 3)
            }
            .opacity(selectedGoals.isEmpty ? 0.5 : 1)
            .disabled(selectedGoals.isEmpty)
            .animation(AppAnimation.springSnappy, value: selectedGoals.isEmpty)
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var goalGrid: some View {
        LiquidGlassContainer(spacing: Spacing.sm) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                ForEach(goals, id: \.self) { goal in
                    goalCell(goal)
                }
            }
        }
    }

    private func goalCell(_ goal: String) -> some View {
        let isSelected = selectedGoals.contains(goal)
        return Button {
            toggleGoal(goal)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isSelected)

                Text(goal)
                    .font(AppFont.subheadline)
                    .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                    }
            }
            .liquidGlass(
                .rect(cornerRadius: Spacing.smallCornerRadius),
                tint: isSelected ? AppColor.accentPrimary.opacity(0.45) : nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleGoal(_ goal: String) {
        let isSelected = selectedGoals.contains(goal)
        withAnimation(AppAnimation.springBouncy) {
            if isSelected {
                selectedGoals.remove(goal)
            } else {
                selectedGoals.insert(goal)
            }
        }
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Page 4: Experience Level

    private var experiencePage: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.md) {
                Text("How experienced are you?")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text("This adjusts the level of detail shown")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
            }

            LiquidGlassContainer(spacing: Spacing.md) {
                VStack(spacing: Spacing.md) {
                    experienceOption(
                        level: "beginner",
                        icon: "leaf.fill",
                        title: "Beginner",
                        subtitle: "New to peptides"
                    )
                    experienceOption(
                        level: "intermediate",
                        icon: "flame.fill",
                        title: "Intermediate",
                        subtitle: "Some protocol experience"
                    )
                    experienceOption(
                        level: "advanced",
                        icon: "bolt.fill",
                        title: "Advanced",
                        subtitle: "Experienced researcher"
                    )
                }
            }
            .padding(.horizontal, Spacing.screenPadding)

            Spacer()

            GlassButton(title: "Continue", icon: "arrow.right", style: .primary, isFullWidth: true) {
                advance(to: 4)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    private func experienceOption(level: String, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = experienceLevel == level
        return Button {
            withAnimation(AppAnimation.springBouncy) { experienceLevel = level }
            if dataStore.profile.hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(spacing: Spacing.lg) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                    .frame(width: 40)
                    .symbolEffect(.bounce, value: isSelected)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
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
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceElevated)

                    if isSelected {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.18))
                            .matchedGeometryEffect(id: "experience-pill", in: experienceNamespace)
                    }

                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                            lineWidth: 0.5
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

    // MARK: - Page 5: HealthKit

    private var healthKitPage: some View {
        permissionPage(
            icon: "heart.text.square.fill",
            title: "Connect Apple Health",
            subtitle: "Correlate protocol compliance with HRV, sleep, and activity. PeptideX never writes to your health data.",
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
                if currentPage == 4 { advance(to: 5) }
            }
        } onSkip: {
            advance(to: 5)
        }
    }

    // MARK: - Page 6: Notifications

    private var notificationsPage: some View {
        permissionPage(
            icon: "bell.badge.fill",
            title: "Enable dose reminders",
            subtitle: "Get a notification at each scheduled dose so you never miss a window.",
            primaryTitle: "Enable Reminders",
            primaryIcon: "bell.fill",
            requesting: requestingNotifications
        ) {
            requestingNotifications = true
            Task {
                let granted = await NotificationService.shared.requestAuthorization()
                requestingNotifications = false
                if dataStore.profile.doseRemindersEnabled != granted {
                    dataStore.profile.doseRemindersEnabled = granted
                    dataStore.persistProfile()
                }
                if currentPage == 5 { advance(to: 6) }
            }
        } onSkip: {
            advance(to: 6)
        }
    }

    private func permissionPage(
        icon: String,
        title: String,
        subtitle: String,
        primaryTitle: String,
        primaryIcon: String,
        requesting: Bool,
        onConnect: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(AppColor.accentPrimary)
                .heroGlow()

            VStack(spacing: Spacing.md) {
                Text(title)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.screenPadding)
            }

            Spacer()

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
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Page 7: Sign in with Apple (optional)

    private var signInPage: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "icloud.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.accentPrimary)
                .heroGlow()

            VStack(spacing: Spacing.md) {
                Text("Sync across devices")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Sign in with your Apple ID to back up and sync your protocols. All features work without signing in.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.screenPadding)
            }

            Spacer()

            VStack(spacing: Spacing.sm) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { @MainActor in
                        AuthService.shared.handleAuthorization(result)
                        if case .success = result, currentPage == 6 {
                            advance(to: 7)
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius))

                GlassButton(title: "Skip", style: .ghost, isFullWidth: true) {
                    advance(to: 7)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Page 8: Ready

    private var readyPage: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.lg)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.bounce, options: .nonRepeating, value: currentPage == 7)
                .heroGlow()

            VStack(spacing: Spacing.md) {
                Text("You're all set!")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)

                (Text("Start tracking your ")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                + Text("peptide protocols")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColor.accentLight))
                    .multilineTextAlignment(.center)
            }

            disclaimerCard
                .padding(.horizontal, Spacing.screenPadding)

            Spacer(minLength: Spacing.md)

            GlassButton(title: "I Understand — Let's Go", icon: "arrow.right", style: .primary, isFullWidth: true) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolved = trimmed.isEmpty ? (AuthService.shared.userDisplayName ?? "") : trimmed
                if dataStore.profile.name != resolved {
                    dataStore.profile.name = resolved
                }
                if !selectedGoals.isEmpty {
                    dataStore.profile.goals = Array(selectedGoals).sorted()
                }
                dataStore.persistProfile()
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                withAnimation(AppAnimation.springSnappy) {
                    hasCompleted = true
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
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

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<totalPages, id: \.self) { index in
                ZStack {
                    Capsule()
                        .fill(AppColor.textTertiary.opacity(0.35))
                        .frame(width: 6, height: 6)

                    if index == currentPage {
                        Capsule()
                            .fill(AppColor.accentPrimary)
                            .frame(width: 22, height: 8)
                            .matchedGeometryEffect(id: "active-dot", in: indicatorNamespace)
                            .shadow(color: AppColor.accentPrimary.opacity(0.5), radius: 8, y: 0)
                    }
                }
                .frame(width: 22, height: 10)
            }
        }
        .animation(AppAnimation.springSmooth, value: currentPage)
    }

    private func advance(to page: Int) {
        dismissKeyboard()
        withAnimation(AppAnimation.springSnappy) { currentPage = page }
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
}

// MARK: - Hero glow modifier

private struct HeroGlow: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: AppColor.accentPrimary.opacity(pulse ? 0.55 : 0.3),
                radius: pulse ? 28 : 18,
                y: 0
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private extension View {
    func heroGlow() -> some View { modifier(HeroGlow()) }
}

#Preview {
    OnboardingView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
