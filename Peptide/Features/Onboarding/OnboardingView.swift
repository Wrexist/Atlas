import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Redesigned onboarding for the training pivot — 16 premium steps that
/// lead with the workout story, use very bold display typography, the
/// anatomical figure from MuscleMapView for the body selection, an
/// Atlas-vs-without comparison, a real "log a set" demo, and a 3-second
/// "Building your plan…" reveal that sets up the post-Ready paywall.
/// Peptides are no longer pushed during onboarding; users discover them
/// later from the Library tab.
///
/// Page indices live in the nested `Page` enum so reordering only
/// requires renaming there.
///
/// State writes:
///
///   - `hasCompletedOnboarding` — final dismiss flag (set by the paywall
///     handlers, not by the Ready button itself)
///   - `experienceLevel` — beginner / intermediate / advanced
///   - `profile.{name,bodyMetrics,nutritionTargets,primaryGoal,
///      trainingPreferences}` — persisted via DataStore
struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("experienceLevel") private var experienceLevel: String = "beginner"

    @State private var page: Int = 0
    @State private var name: String = ""
    @State private var primaryGoal: PrimaryGoal = .buildMuscle
    @State private var bodyMetrics: BodyMetrics = .unspecified
    @State private var daysPerWeek: Int = 3
    @State private var preferredDays: Set<Weekday> = []
    @State private var timeOfDay: PreferredTimeOfDay = .anytime
    @State private var equipment: Set<EquipmentKind> = [.bodyweight]
    @State private var bounceTrigger = 0
    @State private var storeService = StoreService.shared
    @State private var requestingHealth = false
    @State private var requestingNotifications = false
    // Live "try a set" demo state.
    @State private var demoSet = SetEntry(index: 1, weightKg: 60, reps: 8, completed: false)
    @State private var demoCelebrate = false
    // Drives the post-Ready paywall full-screen cover. Decline and
    // accept both flip `hasCompleted` — the trial is optional, but the
    // user shouldn't enter the app before seeing the offer once.
    @State private var showTrialOffer: Bool = false
    // "Building your plan…" loading screen progress (0…1). Drives the
    // ring fill on `buildingPlanStep` and gates the auto-advance.
    @State private var buildingProgress: Double = 0
    @State private var buildingStarted: Bool = false

    @FocusState private var nameFocused: Bool

    // Page indices — single source of truth for the flow. Adjusting
    // ordering only requires renaming here; everything else reads
    // through these constants.
    private enum Page {
        static let welcome          = 0
        static let valueProof       = 1
        static let name             = 2
        static let goal             = 3
        static let experience       = 4
        static let bodyMetrics      = 5
        static let schedule         = 6
        static let equipment        = 7
        static let demoSet          = 8
        static let comparison       = 9
        static let programPreview   = 10
        static let nutrition        = 11
        static let notifications    = 12
        static let health           = 13
        static let buildingPlan     = 14
        static let ready            = 15
        static let total            = 16
    }

    private var totalPages: Int { Page.total }

    enum PrimaryGoal: String, CaseIterable, Identifiable {
        case buildMuscle, loseFat, getStronger, stayConsistent, athletic, recomp
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .buildMuscle:    return "Build muscle"
            case .loseFat:        return "Lose fat"
            case .getStronger:    return "Get stronger"
            case .stayConsistent: return "Stay consistent"
            case .athletic:       return "Athletic performance"
            case .recomp:         return "Recomp"
            }
        }
        var icon: String {
            switch self {
            case .buildMuscle:    return "figure.strengthtraining.traditional"
            case .loseFat:        return "flame.fill"
            case .getStronger:    return "bolt.fill"
            case .stayConsistent: return "calendar.badge.clock"
            case .athletic:       return "figure.run"
            case .recomp:         return "arrow.triangle.2.circlepath"
            }
        }
        var tint: Color {
            switch self {
            case .buildMuscle:    return Color(hex: 0xCF7272)
            case .loseFat:        return OnboardingTint.fatLoss
            case .getStronger:    return Color(hex: 0xD4A844)
            case .stayConsistent: return AppColor.accentPrimary
            case .athletic:       return Color(hex: 0x5B8FB9)
            case .recomp:         return Color(hex: 0x9B72CF)
            }
        }
    }

    enum Experience: String, CaseIterable, Identifiable {
        case beginner, intermediate, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .beginner:     return "New to lifting"
            case .intermediate: return "Comfortable in the gym"
            case .advanced:     return "Years of training"
            }
        }
        var subtitle: String {
            switch self {
            case .beginner:     return "Under a year of consistent training"
            case .intermediate: return "1–3 years, solid technique"
            case .advanced:     return "3+ years, dialed-in programming"
            }
        }
        var icon: String {
            switch self {
            case .beginner:     return "leaf.fill"
            case .intermediate: return "flame.fill"
            case .advanced:     return "bolt.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            OnboardingBackground(step: page)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                TabView(selection: $page) {
                    welcome.tag(Page.welcome)
                    valueProof.tag(Page.valueProof)
                    nameStep.tag(Page.name)
                    goalStep.tag(Page.goal)
                    experienceStep.tag(Page.experience)
                    bodyMetricsStep.tag(Page.bodyMetrics)
                    scheduleStep.tag(Page.schedule)
                    equipmentStep.tag(Page.equipment)
                    demoSetStep.tag(Page.demoSet)
                    comparisonStep.tag(Page.comparison)
                    programPreviewStep.tag(Page.programPreview)
                    nutritionStep.tag(Page.nutrition)
                    notificationsStep.tag(Page.notifications)
                    healthStep.tag(Page.health)
                    buildingPlanStep.tag(Page.buildingPlan)
                    readyStep.tag(Page.ready)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.springSmooth, value: page)
            }

            VStack {
                Spacer()
                footer
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showTrialOffer) {
            // Post-Ready paywall. Both branches finish onboarding —
            // the trial is genuinely optional, but the user shouldn't
            // enter the app without seeing the offer once.
            TrialOfferView(
                onAccept: { hasCompleted = true },
                onDecline: { hasCompleted = true }
            )
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            if page > 0 {
                Button {
                    haptic()
                    withAnimation { page = max(0, page - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(10)
                        .background(Circle().fill(AppColor.surfaceSecondary.opacity(0.6)))
                }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { idx in
                    Capsule()
                        .fill(idx == page
                              ? AppColor.accentPrimary
                              : AppColor.textTertiary.opacity(0.3))
                        .frame(width: idx == page ? 16 : 6, height: 6)
                        .animation(AppAnimation.springSmooth, value: page)
                }
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            // Hide the primary button on the building-plan screen —
            // it auto-advances when the ring fills, and a tappable
            // CTA next to a progress ring reads as "click to bypass."
            if page != Page.buildingPlan {
                primaryButton
            }
            if showSkipOnCurrentPage {
                Button("Skip") {
                    haptic()
                    advance()
                }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, Spacing.xl)
    }

    /// Skip is shown only on optional informational pages. Data-input
    /// pages (goal, experience, body, schedule, equipment) lose Skip so
    /// that personalization is genuinely captured — skipping these
    /// poisons the recommendation engine and removes the sunk-cost
    /// commitment that drives trial conversion.
    private var showSkipOnCurrentPage: Bool {
        switch page {
        case Page.demoSet, Page.comparison, Page.programPreview,
             Page.notifications, Page.health:
            return true
        default:
            return false
        }
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            HStack {
                Text(primaryTitle)
                    .font(AppFont.headline)
                if page < totalPages - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(AppColor.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(primaryEnabled ? Color.white : AppColor.textTertiary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!primaryEnabled)
    }

    private var primaryTitle: String {
        switch page {
        case Page.welcome:  return "Let's go"
        case Page.ready:    return "Open Atlas"
        default:            return "Continue"
        }
    }

    private var primaryEnabled: Bool {
        switch page {
        case Page.name:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private func primaryAction() {
        haptic()
        bounceTrigger += 1
        switch page {
        case Page.name:
            dataStore.updateProfileIdentity(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: dataStore.profile.bio
            )
        case Page.goal:
            dataStore.setPrimaryGoal(primaryGoal.rawValue)
        case Page.bodyMetrics:
            dataStore.updateBodyMetrics(bodyMetrics)
        case Page.equipment:
            // Schedule and equipment both feed the same struct —
            // persist once on the final advance off equipment so a
            // back-and-forth between the two doesn't lose the second
            // screen's changes.
            dataStore.updateTrainingPreferences(currentTrainingPrefs)
        case Page.nutrition:
            if let targets = NutritionMath.dailyTargets(for: bodyMetrics) {
                dataStore.updateNutritionTargets(targets)
            }
        case Page.ready:
            // Present the trial paywall instead of finishing immediately.
            // The paywall handlers flip `hasCompleted` after the user
            // either starts the trial or taps "Maybe later".
            showTrialOffer = true
            return
        default:
            break
        }
        advance()
    }

    private var currentTrainingPrefs: TrainingPreferences {
        TrainingPreferences(
            daysPerWeek: daysPerWeek,
            preferredDays: preferredDays,
            timeOfDay: timeOfDay,
            equipmentAccess: equipment
        )
    }

    private func advance() {
        withAnimation { page = min(totalPages - 1, page + 1) }
    }

    private func haptic() {
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Step 0: Welcome

    private var welcome: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            HeroIcon(
                symbol: "figure.strengthtraining.traditional",
                color: AppColor.accentPrimary,
                accent: AppColor.accentLight,
                size: 140,
                bounceTrigger: bounceTrigger
            )
            VStack(spacing: Spacing.md) {
                Text("Welcome to\nAtlas.")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-4)
                Text("Train. Eat. Recover.\nIn one place.")
                    .font(AppFont.title3)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            SocialProofPill()
                .padding(.top, Spacing.sm)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Step 1: Value proof

    private var valueProof: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Know exactly when to\n")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                + Text("push harder.")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentPrimary)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    valueBullet(icon: "list.bullet.rectangle.fill",
                                text: "Plan your workouts and stay on track.")
                    valueBullet(icon: "scalemass.fill",
                                text: "See your last weight so you know when to add more.")
                    valueBullet(icon: "chart.line.uptrend.xyaxis",
                                text: "Track progress and balance hard training with recovery.")
                    valueBullet(icon: "trophy.fill",
                                text: "Celebrate every PR with confetti and haptic feedback.")
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
        }
    }

    private func valueBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 2: Name

    private var nameStep: some View {
        VStack(spacing: Spacing.xl) {
            HeroIcon(symbol: "person.fill", bounceTrigger: bounceTrigger)
                .padding(.top, Spacing.xl)
            VStack(spacing: Spacing.sm) {
                Text("What should we call you?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("We'll keep things personal.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            TextField("First name", text: $name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .font(AppFont.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .stroke(nameFocused ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: nameFocused ? 1 : 0.5)
                )
                .padding(.horizontal, Spacing.xl)
                .onSubmit { if primaryEnabled { primaryAction() } }
            Spacer()
        }
        .onAppear { nameFocused = true }
    }

    // MARK: - Step 3: Primary goal

    private var goalStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("What's your goal?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("You can change this later.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, Spacing.xl)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.sm) {
                    ForEach(PrimaryGoal.allCases) { goalCard($0) }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
        }
    }

    private func goalCard(_ goal: PrimaryGoal) -> some View {
        let selected = primaryGoal == goal
        return Button {
            haptic()
            primaryGoal = goal
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: goal.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(goal.tint)
                Text(goal.displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(selected ? goal.tint.opacity(0.18) : AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .stroke(selected ? goal.tint : AppColor.glassBorder, lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Experience

    private var experienceStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("How much experience?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("This shapes your starter program.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, Spacing.xl)

            VStack(spacing: Spacing.sm) {
                ForEach(Experience.allCases) { experienceRow($0) }
            }
            .padding(.horizontal, Spacing.lg)
            Spacer()
        }
    }

    private func experienceRow(_ level: Experience) -> some View {
        let selected = experienceLevel == level.rawValue
        return Button {
            haptic()
            experienceLevel = level.rawValue
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: level.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(level.subtitle)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(selected ? AppColor.accentPrimary.opacity(0.12) : AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .stroke(selected ? AppColor.accentPrimary : AppColor.glassBorder, lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: Body metrics

    private var bodyMetricsStep: some View {
        ScrollView {
            BodyMetricsPage(metrics: $bodyMetrics)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
        }
    }

    // MARK: - Step 6: Schedule

    private var scheduleStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("When do you train?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Days per week + preferred slot.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.top, Spacing.xl)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    daysStepper
                    weekdayPicker
                    timeOfDayPicker
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
        }
    }

    private var daysStepper: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Days per week")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
            HStack(spacing: Spacing.xs) {
                ForEach(2...6, id: \.self) { count in
                    Button {
                        haptic()
                        daysPerWeek = count
                    } label: {
                        Text("\(count)")
                            .font(AppFont.headline.weight(.bold))
                            .foregroundStyle(daysPerWeek == count ? AppColor.background : AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .fill(daysPerWeek == count ? AppColor.accentPrimary : AppColor.surfaceSecondary.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .stroke(daysPerWeek == count ? Color.clear : AppColor.glassBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Preferred days (optional)")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    Button {
                        haptic()
                        if preferredDays.contains(day) {
                            preferredDays.remove(day)
                        } else {
                            preferredDays.insert(day)
                        }
                    } label: {
                        Text(day.shortName.prefix(1).uppercased())
                            .font(AppFont.footnote.weight(.bold))
                            .foregroundStyle(preferredDays.contains(day) ? AppColor.background : AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Circle()
                                    .fill(preferredDays.contains(day) ? AppColor.accentPrimary : AppColor.surfaceSecondary.opacity(0.6))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var timeOfDayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Preferred time")
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .textCase(.uppercase)
            HStack(spacing: Spacing.xs) {
                ForEach(PreferredTimeOfDay.allCases) { slot in
                    Button {
                        haptic()
                        timeOfDay = slot
                    } label: {
                        Text(slot.displayName)
                            .font(AppFont.footnote.weight(.semibold))
                            .foregroundStyle(timeOfDay == slot ? AppColor.background : AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                    .fill(timeOfDay == slot ? AppColor.accentPrimary : AppColor.surfaceSecondary.opacity(0.6))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 7: Equipment

    private var equipmentStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("What gear do you have?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("We'll filter exercises and programs to match.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            .padding(.top, Spacing.xl)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.sm) {
                    ForEach(EquipmentKind.allCases.filter { $0 != .other }) { equipmentCard($0) }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
        }
    }

    private func equipmentCard(_ kind: EquipmentKind) -> some View {
        let selected = equipment.contains(kind)
        return Button {
            haptic()
            if selected { equipment.remove(kind) } else { equipment.insert(kind) }
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textSecondary)
                Text(kind.displayName)
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(selected ? AppColor.accentPrimary.opacity(0.12) : AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .stroke(selected ? AppColor.accentPrimary : AppColor.glassBorder, lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 8: Try a set (interactive workout demo)

    private var demoSetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Try logging a set.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Two taps. That's the whole loop.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.top, Spacing.xl)

                demoCard
                    .padding(.top, Spacing.sm)

                if demoCelebrate {
                    successBanner
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private var demoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(AppColor.surfaceSecondary.opacity(0.6))
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bench Press")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Chest · Barbell")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }
                Divider().background(AppColor.glassBorder)
                SetEditorRow(
                    set: $demoSet,
                    previousSet: SetEntry(index: 0, weightKg: 55, reps: 8, completed: true),
                    onDelete: {}
                )
                .onChange(of: demoSet.completed) { _, completed in
                    if completed && !demoCelebrate {
                        withAnimation(.spring(response: 0.4)) { demoCelebrate = true }
                        if !UIAccessibility.isReduceMotionEnabled {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
                Text(demoCelebrate
                     ? "Nice. That's it — your workouts are this fast."
                     : "Tap the circle to log this set.")
                    .font(AppFont.footnote)
                    .foregroundStyle(demoCelebrate ? Color(red: 0.30, green: 0.80, blue: 0.50) : AppColor.textTertiary)
                    .animation(.easeInOut, value: demoCelebrate)
            }
        }
    }

    private var successBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.30, green: 0.80, blue: 0.50))
            Text("Set logged. Atlas tracks weight, reps, RPE — and lights up the muscles you trained.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(Color(red: 0.30, green: 0.80, blue: 0.50).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(Color(red: 0.30, green: 0.80, blue: 0.50).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Step 9: With / Without Atlas comparison

    private var comparisonStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Ready for a ")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                + Text("better training life?")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accentPrimary)

                HStack(alignment: .top, spacing: Spacing.sm) {
                    comparisonColumn(
                        title: "Without Atlas",
                        items: [
                            "Unsure if form is right",
                            "Guessing today's workout",
                            "Skipping muscle groups",
                            "No history to compare",
                        ],
                        isPositive: false
                    )
                    comparisonColumn(
                        title: "With Atlas",
                        items: [
                            "Form cues per exercise",
                            "Smart program scheduling",
                            "Weekly muscle heatmap",
                            "PRs detected & celebrated",
                        ],
                        isPositive: true
                    )
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
        }
    }

    private func comparisonColumn(title: String, items: [String], isPositive: Bool) -> some View {
        let tint = isPositive
            ? AppColor.accentPrimary
            : AppColor.textTertiary
        let bg = isPositive
            ? AppColor.accentPrimary.opacity(0.12)
            : AppColor.surfaceSecondary.opacity(0.6)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isPositive ? "checkmark.circle.fill" : "minus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(item)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Step 10: Program preview

    private var programPreviewStep: some View {
        VStack(spacing: Spacing.lg) {
            HeroIcon(symbol: "list.bullet.rectangle.fill", bounceTrigger: bounceTrigger)
                .padding(.top, Spacing.xl)
            VStack(spacing: Spacing.sm) {
                Text("Your starter plan")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(recommendedProgramName)
                    .font(AppFont.title3)
                    .foregroundStyle(AppColor.accentPrimary)
                Text("Built for \(primaryGoal.displayName.lowercased()), \(daysPerWeek)× per week.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            VStack(spacing: Spacing.xs) {
                programPreviewRow("1", "Day 1 · Upper push")
                programPreviewRow("2", "Day 2 · Lower")
                programPreviewRow("3", "Day 3 · Upper pull")
                if daysPerWeek >= 4 {
                    programPreviewRow("4", "Day 4 · Accessories")
                }
            }
            .padding(.horizontal, Spacing.lg)
            Spacer()
        }
    }

    private var recommendedProgramName: String {
        // Switch on the goal first, then refine by days inside each
        // arm where the choice depends on volume. Avoids the
        // partial-range-inside-tuple-pattern Swift 6 parser ambiguity
        // (the older `case (.buildMuscle, 5...)` form looked like it
        // worked but the audit flagged it as unreliable across
        // compiler versions).
        switch primaryGoal {
        case .getStronger:    return "5/3/1 Strength"
        case .buildMuscle:    return daysPerWeek >= 5 ? "Push Pull Legs" : "Upper / Lower"
        case .loseFat:        return "Full Body Hypertrophy"
        case .athletic:       return "Athletic Conditioning"
        case .recomp:         return "Hybrid Recomp"
        case .stayConsistent: return "Consistency Builder"
        }
    }

    private func programPreviewRow(_ index: String, _ name: String) -> some View {
        HStack(spacing: Spacing.md) {
            Text(index)
                .font(AppFont.headline.weight(.bold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 30)
            Text(name)
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Step 11: Nutrition

    private var nutritionStep: some View {
        ScrollView {
            DailyTargetsPage(metrics: bodyMetrics)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
        }
    }

    // MARK: - Step 12: Notifications (with preview)

    private var notificationsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "bell.badge.fill", bounceTrigger: bounceTrigger)
                    .padding(.top, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    Text("Stay on track.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Workout reminders, weekly recaps,\nand rest-timer alerts.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                NotificationPreviewCard(
                    title: "Leg day in 30 minutes",
                    subtitle: "Hit your second session of the week",
                    timestamp: "now"
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

                permissionRow(
                    icon: "bell.fill",
                    title: "Enable notifications",
                    subtitle: "Tap to allow. You can change this anytime.",
                    isLoading: requestingNotifications,
                    isOn: dataStore.profile.doseRemindersEnabled,
                    action: requestNotifications
                )
                .padding(.horizontal, Spacing.lg)

                Spacer(minLength: 100)
            }
        }
    }

    // MARK: - Step 13: Health (with value preview)

    private var healthStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(
                    symbol: "heart.fill",
                    color: Color(red: 1.0, green: 0.42, blue: 0.42),
                    accent: Color(red: 1.0, green: 0.62, blue: 0.62),
                    bounceTrigger: bounceTrigger
                )
                .padding(.top, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    Text("Connect Apple Health.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Unlock Recovery, HRV trends,\nand sleep-quality insights.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                healthValuePreview
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)

                permissionRow(
                    icon: "heart.fill",
                    title: "Connect Apple Health",
                    subtitle: "Reads sleep, HRV, heart rate, and weight.",
                    isLoading: requestingHealth,
                    isOn: dataStore.profile.healthConnected,
                    action: requestHealth
                )
                .padding(.horizontal, Spacing.lg)

                Text("Atlas reads only — never writes. Lockable with Face ID.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 100)
            }
        }
    }

    /// Mocked Health Monitor grid — three sample biomarker cards that
    /// preview what connecting Health unlocks. Pure presentation; the
    /// values are illustrative.
    private var healthValuePreview: some View {
        HStack(spacing: Spacing.sm) {
            healthPreviewCard(
                icon: "waveform.path.ecg",
                label: "HRV",
                value: "62",
                unit: "ms",
                tint: Color(red: 0.30, green: 0.80, blue: 0.50)
            )
            healthPreviewCard(
                icon: "bed.double.fill",
                label: "Sleep",
                value: "7.4",
                unit: "h",
                tint: Color(hex: 0x9B72CF)
            )
            healthPreviewCard(
                icon: "heart.fill",
                label: "Recovery",
                value: "84",
                unit: "%",
                tint: AppColor.accentPrimary
            )
        }
    }

    private func healthPreviewCard(
        icon: String, label: String, value: String, unit: String, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(unit)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Step 14: Building your plan…

    private var buildingPlanStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            buildingRing
            VStack(spacing: Spacing.sm) {
                Text("Building your plan…")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(buildingStageLabel)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: buildingStageLabel)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .onChange(of: page) { _, newPage in
            if newPage == Page.buildingPlan {
                startBuildingPlanAnimation()
            } else if newPage != Page.buildingPlan, buildingStarted {
                // Reset so a back-nav into this page re-runs the
                // animation instead of seeing progress already at 1.
                buildingProgress = 0
                buildingStarted = false
            }
        }
    }

    private var buildingRing: some View {
        ZStack {
            Circle()
                .stroke(AppColor.accentPrimary.opacity(0.15), lineWidth: 8)
                .frame(width: 120, height: 120)
            Circle()
                .trim(from: 0, to: buildingProgress)
                .stroke(
                    AppColor.accentPrimary,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
            Text("\(Int(buildingProgress * 100))%")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.1), value: buildingProgress)
        }
    }

    private var buildingStageLabel: String {
        switch buildingProgress {
        case ..<0.33:  return "Matching your goal to a program…"
        case ..<0.66:  return "Tuning volume to your schedule…"
        case ..<1.0:   return "Calibrating nutrition targets…"
        default:       return "Done."
        }
    }

    private func startBuildingPlanAnimation() {
        guard !buildingStarted else { return }
        buildingStarted = true
        buildingProgress = 0
        withAnimation(.easeInOut(duration: 2.8)) {
            buildingProgress = 1
        }
        // Auto-advance once the ring fills. Matches the animation
        // duration plus a 250ms beat so the user reads "Done."
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(3050))
            if page == Page.buildingPlan {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                advance()
            }
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String,
                               isLoading: Bool, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                } else if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.30, green: 0.80, blue: 0.50))
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isOn)
    }

    private func requestHealth() {
        haptic()
        requestingHealth = true
        Task {
            let granted = await HealthKitService.shared.requestAuthorization()
            requestingHealth = false
            // HealthKit deliberately doesn't tell apps when the user
            // denies — `granted == true` only confirms the user saw
            // the dialog. We only flip the local flag when the system
            // actually returned success so the UI never claims
            // "connected" against a denial.
            if granted, !dataStore.profile.healthConnected {
                dataStore.toggleHealthConnection()
            }
        }
    }

    private func requestNotifications() {
        haptic()
        requestingNotifications = true
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            requestingNotifications = false
            if granted, !dataStore.profile.doseRemindersEnabled {
                dataStore.profile.doseRemindersEnabled = true
            }
        }
    }

    // MARK: - Step 15: Ready

    private var readyStep: some View {
        VStack(spacing: Spacing.lg) {
            ReadyHero(bounceTrigger: bounceTrigger)
                .padding(.top, Spacing.xl)
            if !name.isEmpty {
                Text("You're set, \(name).")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Spacing.sm) {
                summaryRow(label: "Goal", value: primaryGoal.displayName)
                summaryRow(label: "Experience", value: experienceLevel.capitalized)
                summaryRow(label: "Schedule", value: "\(daysPerWeek)× per week, \(timeOfDay.displayName.lowercased())")
                summaryRow(label: "Program", value: recommendedProgramName)
            }
            .padding(.horizontal, Spacing.lg)
            Spacer()
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.glassBorder, lineWidth: 0.5)
        )
    }
}

/// Compact social-proof pill — five gold stars, a 4.9 score, and a
/// user count. Sits under the welcome headline as the first trust
/// anchor before any data is asked from the user.
private struct SocialProofPill: View {
    private let gold = Color(red: 0.961, green: 0.620, blue: 0.043)

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(gold)
                }
            }
            Text("4.9")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text("·")
                .foregroundStyle(AppColor.textTertiary)
            Text("12k+ training")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(AppColor.surfaceSecondary.opacity(0.7))
        )
        .overlay(
            Capsule()
                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
        )
    }
}
