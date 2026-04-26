@preconcurrency import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"

    @State private var currentPage = 0
    @State private var name: String = ""
    @State private var selectedGoals: Set<String> = []
    @State private var appeared = false
    @State private var requestingHealth = false
    @State private var requestingNotifications = false

    private let totalPages = 8
    private let goals = [
        "Muscle Recovery", "Better Sleep", "Cognitive Enhancement", "Anti-Aging",
        "Fat Loss", "Immune Support", "Joint Health", "Stress Reduction",
    ]

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

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
        .onAppear { appeared = true }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "flask.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColor.accentPrimary)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.5)
                .animation(AppAnimation.springBouncy.delay(0.2), value: appeared)

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
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var goalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            ForEach(goals, id: \.self) { goal in
                let isSelected = selectedGoals.contains(goal)
                Button {
                    withAnimation(AppAnimation.springSnappy) {
                        if isSelected {
                            selectedGoals.remove(goal)
                        } else {
                            selectedGoals.insert(goal)
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                            .contentTransition(.symbolEffect(.replace))

                        Text(goal)
                            .font(AppFont.subheadline)
                            .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(isSelected ? AppColor.accentPrimary.opacity(0.1) : AppColor.surfaceElevated)
                            .overlay {
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? AppColor.glassBorderActive : AppColor.glassBorder,
                                        lineWidth: 0.5
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
            }
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
            withAnimation(AppAnimation.springSnappy) { experienceLevel = level }
        } label: {
            GlassCard(tinted: isSelected) {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                        .frame(width: 40)

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
            }
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
                advance(to: 5)
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
                advance(to: 6)
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
                        advance(to: 7)
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
                if dataStore.profile.name != trimmed {
                    dataStore.profile.name = trimmed
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
                Circle()
                    .fill(index == currentPage ? AppColor.accentPrimary : AppColor.textTertiary)
                    .frame(width: index == currentPage ? 10 : 6, height: index == currentPage ? 10 : 6)
                    .animation(AppAnimation.springSnappy, value: currentPage)
            }
        }
    }

    private func advance(to page: Int) {
        withAnimation(AppAnimation.springSnappy) { currentPage = page }
    }
}

#Preview {
    OnboardingView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
