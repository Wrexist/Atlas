import SwiftUI

struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("experienceLevel") private var experienceLevel = "beginner"
    @State private var currentPage = 0
    @State private var selectedGoals: Set<String> = []
    @State private var appeared = false

    private let totalPages = 4
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
                    goalsPage.tag(1)
                    experiencePage.tag(2)
                    readyPage.tag(3)
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

                Text("Track your peptide protocols with precision")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            GlassButton(title: "Get Started", icon: "arrow.right", style: .primary, isFullWidth: true) {
                withAnimation(AppAnimation.springSnappy) { currentPage = 1 }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Page 2: Goals

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
                withAnimation(AppAnimation.springSnappy) { currentPage = 2 }
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

    // MARK: - Page 3: Experience Level

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
                withAnimation(AppAnimation.springSnappy) { currentPage = 3 }
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

    // MARK: - Page 4: Ready

    private var readyPage: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColor.accentPrimary)

            VStack(spacing: Spacing.md) {
                Text("You're all set!")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)

                Text("Start tracking your peptide protocols")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            GlassButton(title: "Let's Go", icon: "arrow.right", style: .primary, isFullWidth: true) {
                dataStore.updateGoals(selectedGoals)
                withAnimation(AppAnimation.springSnappy) {
                    hasCompleted = true
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.lg)
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
}

#Preview {
    OnboardingView()
        .environment(DataStore())
        .preferredColorScheme(.dark)
}
