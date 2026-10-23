import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Onboarding for Atlas — a health & fitness app. Nine steps (see
/// `OnboardingStep`) covering training, nutrition, recovery permissions
/// and optional referral attribution. Related asks share a page, and the
/// last page is the personalised plan — projection, daily targets and
/// program — whose primary action opens the paywall, so the offer
/// always follows a concrete result.
///
/// State writes:
///
///   - `hasCompletedOnboarding` — final dismiss flag (set by the
///     paywall handlers via the theme picker, not by the plan button
///     itself)
///   - `experienceLevel` — beginner / intermediate / advanced
///   - `disclaimerAcknowledgedAt` — Unix timestamp of the two-tap
///     medical-disclaimer acknowledgement; persistent legal record
///   - `profile.{name,bodyMetrics,nutritionTargets,primaryGoal,
///      goals,goalDate,trainingPreferences,creatorAttribution}`
///      — persisted via DataStore
struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @AppStorage("experienceLevel") private var experienceLevel: String = "beginner"
    /// Unix timestamp of the moment the user tapped "I understand" on
    /// the medical disclaimer step. Persisted because the disclaimer
    /// step is the only legal record of acknowledgement (audit security
    /// H-3); without persistence a scene-restore or `@State` reset
    /// would erase the audit trail. Zero means "never acknowledged."
    @AppStorage("disclaimerAcknowledgedAt") private var disclaimerAcknowledgedAt: Double = 0
    /// Persisted so a kill mid-flow resumes where the user left off
    /// instead of restarting at the Welcome screen. Cleared when the
    /// theme picker closes (which also sets `hasCompletedOnboarding`)
    /// so a future re-run of onboarding (testing path) starts at 0.
    /// `.v2` because the 16-page indices of the old key point at
    /// different pages in the 9-page flow.
    @AppStorage("onboarding.lastPage.v2") private var lastPage: Int = 0

    @State private var page: OnboardingStep = .welcome
    @State private var name: String = ""
    /// The headline goal — drives the projection chart, the goal-date
    /// tint, and the nutrition recommendation. Always one of
    /// `selectedGoals` once the user has picked anything.
    @State private var primaryGoal: PrimaryGoal = .buildMuscle
    /// Every goal the user tapped. The step is multi-select — most
    /// people want more than one outcome (build muscle *and* lose fat).
    /// `primaryGoal` is the first one they chose and stays the anchor.
    @State private var selectedGoals: Set<PrimaryGoal> = []
    @State private var bodyMetrics: BodyMetrics = .unspecified
    @State private var daysPerWeek: Int = 3
    @State private var preferredDays: Set<Weekday> = []
    @State private var timeOfDay: PreferredTimeOfDay = .anytime
    @State private var equipment: Set<EquipmentKind> = [.bodyweight]
    @State private var bounceTrigger = 0
    /// Set once the saved profile has been copied into the step state, so
    /// a later `.onAppear` can't clobber edits the user hasn't saved yet.
    @State private var hasHydratedFromProfile = false
    // Refused last-deselect on the equipment grid.
    @State private var keepOneEquipmentHinted = false
    @State private var shakingEquipment: EquipmentKind?
    @State private var equipmentShakeOffset: CGFloat = 0
    @Environment(\.openURL) private var openURL
    @State private var notificationsDenied = false
    @State private var requestingHealth = false
    @State private var requestingNotifications = false
    /// Pinned reference to the AuthService singleton so the
    /// sign-in section re-renders when AuthService's @Observable
    /// state (`isSignedIn`, `isSigningIn`, `lastError`) changes.
    /// Without this @State, accessing `AuthService.shared.isSignedIn`
    /// directly inside a computed view property may not register the
    /// observation dependency on the outer view (audit code-review #11).
    @State private var authService = AuthService.shared
    /// Reflects the live UNUserNotificationCenter authorization status —
    /// the onboarding step needs to mirror the OS prompt outcome
    /// independently of the user's `doseRemindersEnabled` peptide-
    /// reminder preference (those are separate concerns).
    @State private var notificationsAuthorized = false
    // Drives the post-Ready paywall full-screen cover. Decline and
    // accept both flip `hasCompleted` — the trial is optional, but the
    // user shouldn't enter the app before seeing the offer once.
    @State private var showTrialOffer: Bool = false
    // Theme picker presented after the paywall closes. Persisted via
    // ThemeManager.shared inside the page itself.
    @State private var showThemePicker: Bool = false
    // Creator-attribution step state. Looked up against
    // CreatorCodeService.seeded on primary-action.
    @State private var creatorCodeInput: String = ""
    @State private var creatorAttribution: CreatorAttribution?
    @State private var creatorError: String?
    // Projection chart "reveal" state. Drives a tasteful fade-in on
    // the chart instead of jump-cutting in fully drawn.
    @State private var projectionRevealed: Bool = false
    // Date-based goal target. Defaults to 12 weeks from today so a
    // user who taps Continue without touching the picker still gets a
    // meaningful projection. Persisted to dataStore.profile on
    // advance off the goalDate step.
    @State private var goalDate: Date = OnboardingPlanEngine.defaultGoalDate()
    /// Selected marketing-attribution channel. Persisted into the funnel
    /// snapshot only — never into the user profile (the marketing-channel
    /// answer is anonymous-aggregate signal, not personal data).
    @State private var attributionChannel: AttributionChannel? = nil

    enum AttributionChannel: String, CaseIterable, Identifiable {
        case friend, appStore, tiktok, youtube, reddit, podcast, other
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .friend:   return String(localized: "A friend")
            case .appStore: return String(localized: "App Store")
            case .tiktok:   return "TikTok"
            case .youtube:  return "YouTube"
            case .reddit:   return String(localized: "Reddit")
            case .podcast:  return String(localized: "Podcast")
            case .other:    return String(localized: "Other")
            }
        }
        var icon: String {
            switch self {
            case .friend:   return "person.2.fill"
            case .appStore: return "apple.logo"
            case .tiktok:   return "music.note"
            case .youtube:  return "play.rectangle.fill"
            case .reddit:   return "bubble.left.and.bubble.right.fill"
            case .podcast:  return "mic.fill"
            case .other:    return "ellipsis.circle.fill"
            }
        }
    }

    @FocusState private var nameFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var totalPages: Int { OnboardingStep.allCases.count }

    enum PrimaryGoal: String, CaseIterable, Identifiable {
        case buildMuscle, loseFat, getStronger, stayConsistent,
             athletic, recomp, betterSleep, recovery, antiAging,
             skinHair, energy
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .buildMuscle:    return String(localized: "Build muscle")
            case .loseFat:        return String(localized: "Lose fat")
            case .getStronger:    return String(localized: "Get stronger")
            case .stayConsistent: return String(localized: "Stay consistent")
            case .athletic:       return String(localized: "Athletic performance")
            case .recomp:         return String(localized: "Recomp")
            case .betterSleep:    return String(localized: "Better sleep")
            case .recovery:       return String(localized: "Faster recovery")
            case .antiAging:      return String(localized: "Healthy aging")
            case .skinHair:       return String(localized: "Look & feel better")
            case .energy:         return String(localized: "More energy")
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
            case .betterSleep:    return "moon.zzz.fill"
            case .recovery:       return "bandage.fill"
            case .antiAging:      return "hourglass"
            case .skinHair:       return "sparkles"
            case .energy:         return "bolt.heart.fill"
            }
        }
        var tint: Color {
            switch self {
            case .buildMuscle:    return AppColor.metricHeartRate
            case .loseFat:        return AppColor.streak
            case .getStronger:    return AppColor.achievement
            case .stayConsistent: return AppColor.accentPrimary
            case .athletic:       return Color(light: 0x3D6E93, dark: 0x5B8FB9)
            case .recomp:         return AppColor.metricHRV
            case .betterSleep:    return Color(light: 0x4460D8, dark: 0x6B8AFF)
            case .recovery:       return Color(light: 0x2A8792, dark: 0x4CB8C4)
            case .antiAging:      return Color(light: 0x7B54C4, dark: 0xC59FFF)
            case .skinHair:       return Color(light: 0xB05585, dark: 0xE89BC4)
            case .energy:         return AppColor.perceivedEffort
            }
        }
    }

    enum Experience: String, CaseIterable, Identifiable {
        case beginner, intermediate, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .beginner:     return String(localized: "New to lifting")
            case .intermediate: return String(localized: "Comfortable in the gym")
            case .advanced:     return String(localized: "Years of training")
            }
        }
        var subtitle: String {
            switch self {
            case .beginner:     return String(localized: "Under a year of consistent training")
            case .intermediate: return String(localized: "1–3 years, solid technique")
            case .advanced:     return String(localized: "3+ years, dialed-in programming")
            }
        }
        var icon: String {
            switch self {
            case .beginner:     return "figure.walk"
            case .intermediate: return "figure.strengthtraining.traditional"
            case .advanced:     return "trophy.fill"
            }
        }
    }

    /// Blocks forward swipes on every page so the only way forward is
    /// the footer button. `primaryAction()` is what persists each step
    /// (name, goal, nutrition targets) and records the disclaimer
    /// acknowledgment (Deep Audit II A1); a swipe would skip it.
    /// `advance()` writes `page` directly, so it never hits this gate.
    /// Backward swipes are always allowed.
    private var gatedPage: Binding<OnboardingStep> {
        Binding(
            get: { page },
            set: { newValue in
                // A blocked forward swipe just settles back — no
                // warning buzz, which read as an error for a gesture
                // the user had every reason to try.
                guard newValue <= page else { return }
                page = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                TabView(selection: gatedPage) {
                    // Note: page-resume + bookmark wiring lives on the
                    // ZStack below — `.onAppear` restores from
                    // `lastPage`, `.onChange(of: page)` writes it
                    // back. A kill mid-flow resumes where the user
                    // left off instead of restarting from page 0 with
                    // partially-saved body metrics.
                    //
                    // Tags are `OnboardingStep` cases rather than literal
                    // Ints so a step insertion doesn't silently shift
                    // every downstream tag and re-bucket the funnel events.
                    welcome.tag(OnboardingStep.welcome)
                    nameStep.tag(OnboardingStep.name)
                    goalStep.tag(OnboardingStep.goal)
                    bodyMetricsStep.tag(OnboardingStep.bodyMetrics)
                    trainingStep.tag(OnboardingStep.training)
                    permissionsStep.tag(OnboardingStep.permissions)
                    referralStep.tag(OnboardingStep.referral)
                    disclaimerStep.tag(OnboardingStep.disclaimer)
                    planStep.tag(OnboardingStep.plan)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: page)
                // `pinnedFooter`, not a floating overlay. The footer used
                // to be `VStack { Spacer(); footer }` layered in this
                // ZStack, which reserves no space whatsoever: every
                // scrolling step ran its content underneath the CTA
                // permanently. On the body-metrics step that put the Gender
                // row under the button with no way to scroll it clear —
                // the field simply could not be reached. The modifier gives
                // each page's ScrollView real bottom room, so the last row
                // always clears the button, and lands the backdrop's fade
                // above the button instead of behind it.
                .pinnedFooter { footer }
            }
        }
        .onAppear {
            // Resume from the last saved page so a kill / re-launch
            // mid-onboarding doesn't drop the user back at Welcome
            // with partial body metrics already written.
            if page == .welcome, let saved = OnboardingStep(rawValue: lastPage) {
                page = saved
            }
        }
        .onChange(of: page) { _, newValue in
            lastPage = newValue.rawValue
        }
        .onAppear {
            OnboardingFunnelTracker.recordStepEntered(page.funnelName, index: page.rawValue)
            hydrateFromProfile()
            // Re-hydrate goalDate + selected-goal state from a
            // previously-saved profile in case the user re-opened
            // onboarding (debug menu, reset-onboarding tester).
            // Otherwise the @State defaults (12 weeks from today,
            // .buildMuscle) win, which is also fine for a fresh install.
            // A saved date that's now inside the picker's minimum window
            // keeps the default instead of landing outside its range.
            if let saved = dataStore.profile.goalDate, saved >= earliestGoalDate {
                goalDate = saved
            }
            if let rawGoal = dataStore.profile.primaryGoal,
               let parsed = PrimaryGoal(rawValue: rawGoal) {
                primaryGoal = parsed
                goalHasBeenSelected = true
            }
            // Re-hydrate the full multi-select set from the saved
            // goals so a returning user sees every chip they'd picked
            // still lit, not just the primary.
            let savedGoals = dataStore.profile.goals.compactMap(PrimaryGoal.init(rawValue:))
            if !savedGoals.isEmpty {
                selectedGoals = Set(savedGoals)
                goalHasBeenSelected = true
            } else if goalHasBeenSelected {
                selectedGoals = [primaryGoal]
            }
        }
        .onChange(of: page) { _, newPage in
            OnboardingFunnelTracker.recordStepEntered(newPage.funnelName, index: newPage.rawValue)
            // Focus the name field only when the name page is actually
            // the current one. Driving this from the sub-view's
            // `.onAppear` summoned the keyboard early — TabView mounts
            // adjacent pages, so `.onAppear` fired on the prior page.
            //
            // Leaving any text-entry step must put the keyboard away —
            // otherwise the name keyboard rode along onto the goal grid
            // (and the creator-code keyboard onto its
            // neighbours), covering the lower half of the next card.
            if newPage == .name {
                nameFocused = true
            } else {
                nameFocused = false
                dismissKeyboard()
            }
            // Move VoiceOver to the new step instead of leaving focus
            // parked on the footer button of the step that just left.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            // Driven by the page, not the step's `.onAppear`: the paged
            // TabView mounts neighbours, so the curve used to draw while
            // the user was still on the previous page.
            if newPage == .plan {
                Haptics.success()
                AppAnimation.with(AppAnimation.springSmooth.delay(0.2)) {
                    projectionRevealed = true
                }
            } else {
                projectionRevealed = false
            }
        }
        .task(id: scenePhase) {
            // Re-check OS permission state when the user returns from
            // Settings — a flipped notification or HealthKit auth in
            // iOS Settings must reflect in the onboarding row, otherwise
            // the UI lies about the live grant. .task(id:) cancels the
            // previous task on each phase change so rapid background/
            // foreground toggles don't accumulate observers (audit
            // code-review #14).
            guard scenePhase == .active else { return }
            let status = await NotificationService.shared.checkAuthorization()
            notificationsAuthorized = (status == .authorized || status == .provisional)
            notificationsDenied = status == .denied
        }
        .fullScreenCover(isPresented: $showTrialOffer) {
            // Post-Ready paywall. Both branches advance into the
            // theme picker — the trial is genuinely optional, but the
            // user shouldn't enter the app without seeing the offer
            // once.
            TrialOfferView(
                onAccept: {
                    OnboardingFunnelTracker.recordEvent("paywall_accepted")
                    showTrialOffer = false
                    showThemePicker = true
                },
                onDecline: {
                    OnboardingFunnelTracker.recordEvent("paywall_declined")
                    UpsellScheduler.recordTrialDeclined()
                    showTrialOffer = false
                    showThemePicker = true
                }
            )
        }
        .fullScreenCover(isPresented: $showThemePicker) {
            ThemePickerCover(onContinue: {
                OnboardingFunnelTracker.recordCompletion()
                showThemePicker = false
                hasCompleted = true
                // Reset the resume bookmark so a future re-onboarding
                // (testing path or user-triggered reset) starts at
                // page 0 instead of the now-stale last page.
                lastPage = 0
            })
        }
        .onChange(of: showTrialOffer) { _, presented in
            // If the paywall cover dismissed without onAccept/onDecline
            // firing (system interruption — Siri, call, multi-scene
            // re-layout), advance into the theme picker anyway so the
            // user isn't stuck on the plan page tapping its CTA
            // re-triggering the paywall every time (audit code-review
            // #10). The funnel event "paywall_dismissed_externally"
            // lets us distinguish this from user-initiated decline.
            if !presented && !showThemePicker && !hasCompleted {
                OnboardingFunnelTracker.recordEvent("paywall_dismissed_externally")
                showThemePicker = true
            }
        }
    }

    /// Copies whatever an earlier run already saved into the step state.
    /// Resuming mid-flow restores `page`, but without this every field
    /// behind it fell back to its default: the plan summary showed a
    /// generic schedule and skipped the nutrition-target write because
    /// `bodyMetrics` read as unspecified.
    private func hydrateFromProfile() {
        guard !hasHydratedFromProfile else { return }
        hasHydratedFromProfile = true
        let profile = dataStore.profile
        if name.isEmpty { name = profile.name }
        if bodyMetrics == .unspecified { bodyMetrics = profile.bodyMetrics }
        if let prefs = profile.trainingPreferences {
            preferredDays = prefs.preferredDays
            setDaysPerWeek(min(max(prefs.daysPerWeek, Self.daysPerWeekRange.lowerBound), Self.daysPerWeekRange.upperBound))
            timeOfDay = prefs.timeOfDay
            if !prefs.equipmentAccess.isEmpty { equipment = prefs.equipmentAccess }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            // Both side slots share the back button's 44pt so the
            // progress capsule stays centred on every page, Welcome
            // included.
            ZStack {
                if let previous = page.previous {
                    Button {
                        haptic()
                        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { page = previous }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                            .glassControl(.circle)
                    }
                    .accessibilityLabel("Back")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
            Spacer()
            progressIndicator
            Spacer()
            Color.clear.frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
        }
    }

    /// Compact progress indicator — a thin capsule that fills based on
    /// the current page, with a small "step / total" counter underneath.
    /// Replaces the per-page dot row that overflowed once the flow grew
    /// past ~12 steps, and gives the user a concrete sense of how much
    /// is left ("you're 80% there") instead of a foggy dot count.
    private var progressIndicator: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.textTertiary.opacity(0.25))
                    .frame(height: 4)
                GeometryReader { proxy in
                    Capsule()
                        .fill(AppColor.accentPrimary)
                        .frame(
                            width: max(8, proxy.size.width * progressFraction),
                            height: 4
                        )
                        .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: page)
                }
                .frame(height: 4)
            }
            .frame(width: 160)

            Text("\(page.rawValue + 1) / \(totalPages)")
                .font(AppFont.scaled(11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textTertiary)
                .contentTransition(.numericText())
                .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: page)
        }
        // The capsule and the "3 / 9" counter are one fact; read as two
        // stops they were meaningless on their own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page.rawValue + 1) of \(totalPages)")
    }

    private var progressFraction: CGFloat {
        guard totalPages > 1 else { return 1 }
        let pos = CGFloat(page.rawValue) / CGFloat(totalPages - 1)
        return min(1, max(0, pos))
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            primaryButton
            // `OnboardingStep.isSkippable` whitelists Skip on the
            // optional steps only; the personalization-critical pages
            // (goal, body metrics, training, plan) are intentionally
            // excluded — skipping body metrics silently breaks
            // nutrition targets and skipping the plan bypasses the
            // derived-targets write.
            if page.isSkippable {
                Button("Skip") {
                    haptic()
                    // Record the skip with the step name so the funnel
                    // can distinguish "user advanced after engaging" vs
                    // "user tapped Skip" (audit integration M3).
                    OnboardingFunnelTracker.recordEvent("skip_\(page.funnelName)")
                    advance()
                }
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .minimumHitArea()
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xl)
    }

    private var primaryButton: some View {
        PrimaryCTAButton(title: LocalizedStringKey(primaryTitle), action: primaryAction)
            // "Continue" → "I understand" → "Apply" cross-fades instead
            // of jump-cutting between steps.
            .contentTransition(.interpolate)
            .appAnimation(AppAnimation.springSnappy, value: primaryTitle)
            .disabled(!primaryEnabled)
    }

    private var primaryTitle: String {
        switch page {
        case .welcome:    return String(localized: "Let's go")
        case .disclaimer: return String(localized: "I understand")
        case .referral:   return hasCreatorCodeToApply ? String(localized: "Apply") : String(localized: "Continue")
        case .plan:       return String(localized: "Start my plan")
        default:          return String(localized: "Continue")
        }
    }

    /// "Apply" only once there's a code to apply — an empty field reads
    /// "Continue", since that's what tapping it does.
    private var hasCreatorCodeToApply: Bool {
        creatorAttribution == nil
            && !creatorCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryEnabled: Bool {
        switch page {
        case .name:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .goal:
            // Must pick a goal before Continue lights up. The date
            // picker auto-defaults to 12 weeks from today so no
            // explicit date selection is required.
            return goalHasBeenSelected
        default:
            return true
        }
    }

    private func primaryAction() {
        haptic()
        bounceTrigger += 1
        if page.presentsPaywall {
            presentPaywall()
            return
        }
        switch page {
        case .name:
            dataStore.updateProfileIdentity(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: dataStore.profile.bio
            )
        case .goal:
            // Merged step persists the goals, the chosen date and the
            // experience answer. setPrimaryGoal guards against goals
            // that aren't in profile.goals, so updateGoals must run
            // first (audit C2). Flush sync so a force-quit within the
            // 350ms debounce doesn't lose either field.
            let raw = primaryGoal.rawValue
            var goalSet = Set(dataStore.profile.goals)
            goalSet.formUnion(selectedGoals.map(\.rawValue))
            goalSet.insert(raw)
            dataStore.updateGoals(goalSet)
            dataStore.setPrimaryGoal(raw)
            dataStore.profile.goalDate = goalDate
            dataStore.flushPendingSave()
            // Seed `activityLevel` from the experience answer on the
            // way out, before the body-metrics page derives targets
            // from it (audit Meals L12).
            bodyMetrics.activityLevel = OnboardingPlanEngine.activityLevel(forExperience: experienceLevel)
        case .bodyMetrics:
            // Untouched wheels save the values they displayed, and the
            // derived targets persist now so the plan page shows — and
            // the Meals tab inherits — the same numbers.
            bodyMetrics = BodyMetricsRanges.filledWithDefaults(bodyMetrics)
            dataStore.updateBodyMetrics(bodyMetrics)
            if let targets = NutritionMath.recommendedTargets(for: bodyMetrics, goalRaw: primaryGoal.rawValue) {
                dataStore.updateNutritionTargets(targets)
            }
        case .training:
            dataStore.updateTrainingPreferences(currentTrainingPrefs)
        case .disclaimer:
            // One-tap acknowledge → advance. The persistent
            // @AppStorage timestamp is the legal audit trail.
            disclaimerAcknowledgedAt = Date().timeIntervalSince1970
            OnboardingFunnelTracker.recordEvent("disclaimer_acknowledged")
        case .referral:
            if creatorAttribution == nil {
                applyCreatorCode()
                return
            }
        default:
            break
        }
        advance()
    }

    /// Opens the trial paywall from the plan page — the flow continues
    /// through the paywall and the theme picker before hasCompleted
    /// flips. The theme picker's onContinue path resets `lastPage = 0`
    /// so a future re-onboarding starts at page 0. An existing
    /// subscriber (reinstall / new device) skips the trial offer.
    private func presentPaywall() {
        if StoreService.shared.isProUser {
            OnboardingFunnelTracker.recordEvent("paywall_skipped_pro")
            showThemePicker = true
        } else {
            showTrialOffer = true
        }
    }

    /// Looks up the typed creator code against the seeded list and
    /// flips state for the success card. Empty input is a silent
    /// "skip" — the user moves on without any record.
    private func applyCreatorCode() {
        let trimmed = creatorCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            creatorError = nil
            advance()
            return
        }
        if let match = CreatorCodeService.lookup(trimmed) {
            AppAnimation.with(AppAnimation.springBouncy) {
                creatorAttribution = match
                creatorError = nil
            }
            dataStore.profile.creatorAttribution = match
            // Flush sync — see goalDate comment.
            dataStore.flushPendingSave()
            OnboardingFunnelTracker.recordEvent("creator_code_applied")
            Haptics.success()
        } else {
            AppAnimation.with(AppAnimation.fadeIn) { creatorError = String(localized: "Code not found — double-check and try again.") }
            OnboardingFunnelTracker.recordEvent("creator_code_invalid")
            Haptics.error()
        }
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
        // Tear down the keyboard before the page transition so it can't
        // linger over the next card mid-animation.
        dismissKeyboard()
        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { page = page.next ?? page }
    }

    /// Resigns the first responder app-wide. Covers the text fields that
    /// live inside sub-views (creator code) where the parent has
    /// no `FocusState` binding to flip.
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    /// Primary-CTA and navigation feedback. Chips and toggles use
    /// `Haptics.selection()`; commit moments use `Haptics.success()`.
    private func haptic() {
        Haptics.impact(.light)
    }

    // MARK: - Welcome

    private var welcome: some View {
        centeredScroll {
            VStack(spacing: Spacing.xl) {
                Spacer()
                HeroLogo(
                    size: 148,
                    bounceTrigger: bounceTrigger,
                    isActive: page == .welcome
                )
                .staggeredAppear(index: 0)
                VStack(spacing: Spacing.md) {
                    Text("Welcome to\nAtlas.")
                        .font(AppFont.scaled(56, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .staggeredAppear(index: 1)
                    Text("Train. Eat. Recover.\nIn one place.")
                        .font(AppFont.title3)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .staggeredAppear(index: 2)
                }
                SocialProofPill()
                    .padding(.top, Spacing.sm)
                    .staggeredAppear(index: 3)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    /// A page that centres its content with `Spacer`s when it fits, and
    /// scrolls instead of pushing controls off screen when it doesn't —
    /// the 56pt Welcome title overflows
    /// at accessibility type sizes.
    private func centeredScroll<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Sign in with Apple

    /// Optional sign-in, folded under the name field. Skipping it is
    /// genuinely fine — every feature works without an Apple ID, and
    /// Profile → Account offers the same button later — but a signed-in
    /// user gets cloud sync across devices and their name pre-filled.
    private var signInSection: some View {
        VStack(spacing: Spacing.md) {
            sectionEyebrow("Save your progress (optional)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if authService.isSignedIn {
                    signedInBadge
                } else if authService.isSigningIn {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text("Signing in…")
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .frame(height: 50)
                } else {
                    AppleSignInButton {
                        Haptics.impact(.medium)
                        OnboardingFunnelTracker.recordEvent("sign_in_initiated")
                        authService.signIn()
                    }
                    .frame(height: 50)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))

            signInDisclosureRow(icon: "icloud.fill", text: "Cloud sync across iPhone, iPad, and Watch.")
            signInDisclosureRow(icon: "lock.shield.fill", text: "Atlas never sees your email — Apple relays it.")
        }
        .appAnimation(AppAnimation.springSnappy, value: authService.isSignedIn)
        .appAnimation(AppAnimation.springSnappy, value: authService.isSigningIn)
        .onChange(of: authService.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Haptics.success()
            prefillNameFromAppleID()
        }
        .alert(
            authService.lastError?.title ?? "Sign-in failed",
            isPresented: signInErrorBinding,
            presenting: authService.lastError
        ) { _ in
            Button("OK") { authService.clearLastError() }
        } message: { error in
            Text(error.message)
        }
    }

    private var signInErrorBinding: Binding<Bool> {
        Binding(
            get: { authService.lastError != nil },
            set: { newValue in
                if !newValue { authService.clearLastError() }
            }
        )
    }

    private var signedInBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppColor.accentPrimary)
                .symbolEffect(.bounce, value: authService.isSignedIn)
                .accessibilityHidden(true)
            Text(authService.userDisplayName.map { String(localized: "Signed in as \($0)") } ?? String(localized: "Signed in with Apple"))
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .glassControl(
            .capsule,
            tint: AppColor.accentPrimary.opacity(0.18),
            border: AppColor.accentPrimary.opacity(0.45),
            interactive: false
        )
    }

    private func signInDisclosureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 22)
            Text(text)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Referral (attribution survey + creator code)

    /// Optional page pairing the two "how did you get here" asks. The
    /// channel answer is anonymous, captured into the funnel snapshot
    /// only — useful for allocating ad spend, never stored on the
    /// profile. The creator code stamps attribution onto the profile
    /// (credit only — no discount is applied at checkout).
    private var referralStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                OnboardingHeader(title: "How did you find Atlas?", subtitle: "Optional.")
                    .padding(.top, Spacing.xl)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.sm) {
                    ForEach(AttributionChannel.allCases) { channel in
                        attributionChip(channel)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    sectionEyebrow("Have a creator or referral code?")
                    if let attribution = creatorAttribution {
                        creatorSuccessCard(attribution)
                    } else {
                        creatorCodeField
                    }
                }
                .padding(.top, Spacing.sm)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func attributionChip(_ channel: AttributionChannel) -> some View {
        let isSelected = attributionChannel == channel
        return Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) { attributionChannel = channel }
            OnboardingFunnelTracker.recordEvent("attribution_\(channel.rawValue)")
        } label: { chipLabel(channel: channel, isSelected: isSelected) }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(channel.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private func chipLabel(channel: AttributionChannel, isSelected: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: channel.icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textSecondary)
                .frame(width: 22)
            Text(channel.displayName)
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.accentPrimary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingChoice(isSelected: isSelected)
    }

    // MARK: - Name

    private var nameStep: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                HeroIcon(symbol: "person.fill", bounceTrigger: bounceTrigger, isActive: page == .name)
                    .padding(.top, Spacing.xl)
                OnboardingHeader(title: "What should we call you?")
                GlassTextField(placeholder: "First name", text: $name, icon: nil, focus: $nameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.continue)
                    .font(AppFont.title2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                    .onSubmit { if primaryEnabled { primaryAction() } }
                signInSection
                    .padding(.top, Spacing.md)
                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        // Only the pre-fill runs here. Focus is driven from the root
        // `.onChange(of: page)` — setting it on appear fired while the
        // page was still off-screen (TabView pre-mounts neighbours) and
        // summoned the keyboard early.
        .onAppear { prefillNameFromAppleID() }
    }

    /// Pre-fills the first name from the Apple-relayed full name.
    /// AppleSignInButton only forwards the name on the very first
    /// authorization — once we have it, we shouldn't ask twice (audit
    /// H2). Trimmed to the first name so the "First name" placeholder
    /// semantic still reads true. Never overwrites typed input.
    private func prefillNameFromAppleID() {
        guard name.isEmpty, let display = authService.userDisplayName else { return }
        let first = display.split(separator: " ").first.map(String.init) ?? display
        if !first.isEmpty { name = first }
    }

    // MARK: - Primary goal

    /// Merged "what's your goal, by when, and how experienced are
    /// you?" step. The user picks a goal from the grid; the date row
    /// animates in below once a goal is selected, and the experience
    /// rows close the page. Related intentions, one screen.
    private var goalStep: some View {
        VStack(spacing: 0) {
            OnboardingHeader(title: "What are your goals?", subtitle: "Pick all that apply")
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.md)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: Spacing.sm) {
                        ForEach(PrimaryGoal.allCases) { goalCard($0) }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)

                    if goalHasBeenSelected {
                        goalDateSection
                            .id(Self.goalDateAnchorID)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.top, Spacing.lg)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    experienceSection
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.lg)
                        .padding(.bottom, Spacing.xxxxl)
                }
                .onChange(of: goalHasBeenSelected) { _, isSelected in
                    // After the date section reveals, pull it into view —
                    // on small phones (SE) the goal grid fills the
                    // viewport and the chips sit below the fold, hiding
                    // the next-step affordance (audit Onboarding 4.14).
                    guard isSelected else { return }
                    AppAnimation.with(AppAnimation.springSmooth) {
                        proxy.scrollTo(Self.goalDateAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: goalHasBeenSelected)
    }

    private static let goalDateAnchorID = "onboarding.goal.dateSection"

    /// True after the user has tapped a goal card at least once.
    /// Drives the date-section reveal so the picker only appears
    /// once there's an intention to anchor it to.
    @State private var goalHasBeenSelected: Bool = false

    private var goalDateSection: some View {
        VStack(spacing: Spacing.sm) {
            sectionEyebrow("Target date")
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.sm) {
                goalDateChip("8 wks", a11yLabel: String(localized: "8 weeks"), weeks: 8)
                goalDateChip("12 wks", a11yLabel: String(localized: "12 weeks"), weeks: 12)
                goalDateChip("6 mo", a11yLabel: String(localized: "6 months"), weeks: 26)
            }

            DatePicker(
                "Or a custom date",
                selection: $goalDate,
                in: earliestGoalDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .glassSurface(cornerRadius: Spacing.smallCornerRadius)

            Text(goalDateSummary)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .padding(.top, 2)
        }
    }

    private func goalDateChip(_ label: LocalizedStringKey, a11yLabel: String, weeks: Int) -> some View {
        let candidate = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: Date()) ?? Date()
        let isSelected = Calendar.current.isDate(goalDate, inSameDayAs: candidate)
        return Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) { goalDate = candidate }
        } label: {
            Text(label)
                .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                .onboardingFilledChoice(isSelected: isSelected)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Target date \(a11yLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func goalCard(_ goal: PrimaryGoal) -> some View {
        let selected = selectedGoals.contains(goal)
        return Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSmooth) { toggleGoal(goal) }
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: goal.icon)
                    .font(AppFont.scaled(28, weight: .semibold, relativeTo: .title1))
                    .foregroundStyle(goal.tint)
                    .symbolEffect(.bounce, value: selected)
                Text(goal.displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .onboardingChoice(isSelected: selected, tint: goal.tint, cornerRadius: Spacing.cardCornerRadius)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(16, weight: .bold))
                        .foregroundStyle(goal.tint)
                        .background(Circle().fill(AppColor.background).padding(2))
                        .padding(Spacing.sm)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(goal.displayName)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// Toggles a goal in/out of the multi-select set and keeps
    /// `primaryGoal` pointing at a still-selected goal. The first goal
    /// the user picks becomes primary; removing the primary promotes the
    /// next selected goal (in stable `allCases` order) so the projection
    /// and date tint never reference a deselected goal.
    private func toggleGoal(_ goal: PrimaryGoal) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
            if primaryGoal == goal {
                primaryGoal = PrimaryGoal.allCases.first { selectedGoals.contains($0) } ?? primaryGoal
            }
        } else {
            if selectedGoals.isEmpty { primaryGoal = goal }
            selectedGoals.insert(goal)
        }
        goalHasBeenSelected = !selectedGoals.isEmpty
    }

    /// Two weeks out: the soonest target the date picker offers.
    private var earliestGoalDate: Date {
        Date().addingTimeInterval(60 * 60 * 24 * 14)
    }

    /// Human-readable "8 weeks to commit" summary for the merged
    /// goal-and-date step. Used inside the date section underneath
    /// the picker.
    private var goalDateSummary: String {
        String(localized: "That's \(goalWeeks) weeks to commit.")
    }

    /// Weeks between today and the user's chosen goal date. Used by
    /// the plan page's headline and the ProjectionChart's framing.
    private var goalWeeks: Int {
        OnboardingPlanEngine.goalWeeks(until: goalDate)
    }

    // MARK: - Experience

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionEyebrow("Training experience")
            ForEach(Experience.allCases) { experienceRow($0) }
        }
    }

    private func experienceRow(_ level: Experience) -> some View {
        let selected = experienceLevel == level.rawValue
        return Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.springSnappy) { experienceLevel = level.rawValue }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: level.icon)
                    .font(AppFont.scaled(20, weight: .semibold))
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
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(Spacing.md)
            .onboardingChoice(isSelected: selected, cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Body metrics

    private var bodyMetricsStep: some View {
        ScrollView {
            BodyMetricsPage(metrics: $bodyMetrics)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
        }
    }

    // MARK: - Training (schedule + equipment)

    /// Schedule and equipment both feed `TrainingPreferences`, so they
    /// share one page and one write on the way out.
    private var trainingStep: some View {
        VStack(spacing: Spacing.lg) {
            OnboardingHeader(title: "How do you train?")
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xl)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    daysStepper
                    weekdayPicker
                    timeOfDayPicker
                    equipmentSection
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
        }
        .onAppear {
            // `.other` and `.plate` have no card in the grid — if a
            // re-hydrated profile carries one, it can't be deselected
            // and skews the "keep at least one selected" count. Strip
            // them so the step only ever holds card-backed kinds.
            equipment.formIntersection(EquipmentKind.accessChoices)
        }
    }

    private static let daysPerWeekRange = 2...6

    /// Keeps the preferred days within the weekly count, dropping the
    /// latest days of the week first.
    private func setDaysPerWeek(_ count: Int) {
        daysPerWeek = count
        if preferredDays.count > count {
            preferredDays = Set(Weekday.allCases.filter(preferredDays.contains).prefix(count))
        }
    }

    /// Picking more preferred days than the weekly count raises the count.
    private func togglePreferredDay(_ day: Weekday) {
        if preferredDays.remove(day) == nil {
            preferredDays.insert(day)
            daysPerWeek = max(daysPerWeek, preferredDays.count)
        }
    }

    private var daysStepper: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionEyebrow("Days per week")
            HStack(spacing: Spacing.xs) {
                ForEach(Self.daysPerWeekRange, id: \.self) { count in
                    let isSelected = daysPerWeek == count
                    Button {
                        Haptics.selection()
                        AppAnimation.with(AppAnimation.springSnappy) { setDaysPerWeek(count) }
                    } label: {
                        Text("\(count)")
                            .font(AppFont.headline.weight(.bold))
                            .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .onboardingFilledChoice(isSelected: isSelected)
                    }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityLabel("\(count) days per week")
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionEyebrow("Preferred days (optional)")
            HStack(spacing: Spacing.xs) {
                ForEach(Weekday.allCases) { day in
                    let isSelected = preferredDays.contains(day)
                    let isFull = !isSelected && preferredDays.count >= Self.daysPerWeekRange.upperBound
                    Button {
                        Haptics.selection()
                        AppAnimation.with(AppAnimation.springSnappy) { togglePreferredDay(day) }
                    } label: {
                        Text(day.shortName.prefix(1).uppercased())
                            .font(AppFont.footnote.weight(.bold))
                            .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                            .onboardingFilledChoice(isSelected: isSelected, .capsule)
                            .opacity(isFull ? 0.4 : 1)
                    }
                    .buttonStyle(ScalePressStyle())
                    .disabled(isFull)
                    // "T" and "S" are ambiguous spoken; say the day.
                    .accessibilityLabel(day.rawValue.capitalized)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private var timeOfDayPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionEyebrow("Preferred time")
            HStack(spacing: Spacing.xs) {
                ForEach(PreferredTimeOfDay.allCases) { slot in
                    let isSelected = timeOfDay == slot
                    Button {
                        Haptics.selection()
                        AppAnimation.with(AppAnimation.springSnappy) { timeOfDay = slot }
                    } label: {
                        Text(slot.displayName)
                            .font(AppFont.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? AppColor.onAccent : AppColor.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                            .onboardingFilledChoice(isSelected: isSelected)
                    }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    /// One eyebrow style for every in-step section label, matching the
    /// theme picker's "DISPLAY MODE" / "COLOR THEME" headers.
    private func sectionEyebrow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.eyebrow)
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(AppColor.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Equipment

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                sectionEyebrow("Equipment")
                Spacer()
                if keepOneEquipmentHinted {
                    Text("Keep at least one")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .transition(.opacity)
                }
            }
            .appAnimation(AppAnimation.fadeIn, value: keepOneEquipmentHinted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: Spacing.sm) {
                ForEach(EquipmentKind.accessChoices) { equipmentCard($0) }
            }
        }
    }

    private func equipmentCard(_ kind: EquipmentKind) -> some View {
        let selected = equipment.contains(kind)
        return Button {
            if selected {
                // Always keep at least one option selected — an empty
                // set makes ExerciseLibrary filters return zero hits
                // and the program preview renders a blank list. The
                // last deselect is refused out loud — a warning buzz,
                // a shake, and the "Keep at least one" hint — so
                // it doesn't read as a dead tap.
                guard equipment.count > 1 else {
                    Haptics.warning()
                    keepOneEquipmentHinted = true
                    Task { await shakeEquipmentCard(kind) }
                    return
                }
                Haptics.selection()
                AppAnimation.with(AppAnimation.springSnappy) { _ = equipment.remove(kind) }
            } else {
                Haptics.selection()
                AppAnimation.with(AppAnimation.springSnappy) { _ = equipment.insert(kind) }
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                // Fixed slot, not the glyph's own size. `figure.*` symbols
                // are much taller than `dumbbell.fill` or `wave.3.right`,
                // so letting each icon set its own height made every card
                // in the grid a different size — Barbell taller than
                // Dumbbell beside it, and so on down the two columns.
                GlyphImage(glyph: kind.glyph, size: 24)
                    .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textSecondary)
                    .symbolEffect(.bounce, value: selected)
                    .frame(height: 32)
                Text(kind.displayName)
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
            }
            // A floor rather than a fixed height, so the cards stay uniform
            // at default type sizes but can still grow for Dynamic Type
            // instead of clipping the label.
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, Spacing.md)
            .onboardingChoice(isSelected: selected)
            .offset(x: shakingEquipment == kind ? equipmentShakeOffset : 0)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// Three-step horizontal shake (8 → -8 → 0), the lock screen's
    /// refusal idiom. Skipped under Reduce Motion; the warning haptic
    /// and the hint already carry the message.
    private func shakeEquipmentCard(_ kind: EquipmentKind) async {
        guard !reduceMotion else { return }
        shakingEquipment = kind
        AppAnimation.with(AppAnimation.shake) { equipmentShakeOffset = 8 }
        try? await Task.sleep(for: .milliseconds(80))
        AppAnimation.with(AppAnimation.shake) { equipmentShakeOffset = -8 }
        try? await Task.sleep(for: .milliseconds(80))
        AppAnimation.with(AppAnimation.shakeSettle) { equipmentShakeOffset = 0 }
    }

    // MARK: - Plan (personalised result, then the paywall)

    /// The last page: the user's own projection, daily targets, program
    /// and schedule, with the paywall behind its primary action. The
    /// projection numbers are illustrative — the curve shape and the
    /// headline adapt to the primary goal so it reads as "we built this
    /// for you" — but the targets are the ones just saved to Meals.
    private var planStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                sectionEyebrow("Your plan")
                    .padding(.top, Spacing.xl)
                OnboardingHeader(
                    title: LocalizedStringKey(projectionHeadline),
                    subtitle: LocalizedStringKey(projectionSubtitle)
                )

                ProjectionChart(
                    goal: primaryGoal,
                    daysPerWeek: daysPerWeek,
                    startWeightKg: bodyMetrics.weightKg,
                    weeks: goalWeeks,
                    targetDate: goalDate,
                    spokenSummary: "\(projectionStatLabel), \(projectionStatValue)",
                    revealed: projectionRevealed
                )
                .padding(.top, Spacing.sm)

                VStack(spacing: Spacing.xs) {
                    projectionStatRow(
                        label: projectionStatLabel,
                        value: projectionStatValue,
                        icon: primaryGoal.icon,
                        tint: primaryGoal.tint
                    )
                    if let targets = NutritionMath.recommendedTargets(for: bodyMetrics, goalRaw: primaryGoal.rawValue) {
                        // Hidden only for a profile hydrated from an
                        // older run with incomplete metrics — the
                        // body-metrics page fills untouched wheels.
                        projectionStatRow(
                            label: String(localized: "Daily targets"),
                            value: String(localized: "\(targets.calories) kcal\n\(targets.proteinG) g protein · \(targets.carbsG) g carbs · \(targets.fatG) g fat"),
                            icon: "fork.knife",
                            tint: AppColor.achievement
                        )
                    }
                    projectionStatRow(
                        label: String(localized: "Program"),
                        value: OnboardingPlanEngine.programName(goal: primaryGoal, daysPerWeek: daysPerWeek),
                        icon: "list.bullet.clipboard.fill",
                        tint: AppColor.accentPrimary
                    )
                    projectionStatRow(
                        label: String(localized: "Schedule"),
                        value: String(localized: "\(daysPerWeek)× per week, \(timeOfDay.displayName.lowercased())"),
                        icon: "calendar",
                        tint: AppColor.accentPrimary
                    )
                    projectionStatRow(
                        label: String(localized: "First milestone"),
                        value: String(localized: "Week 2 · habit locked in"),
                        icon: "checkmark.seal.fill",
                        tint: AppColor.accentPrimary
                    )
                    if let attribution = creatorAttribution {
                        // Attribution only — no percentage; the checkout
                        // applies no discount (see CreatorCodeService).
                        projectionStatRow(
                            label: "Referral",
                            value: "via \(attribution.creatorName)",
                            icon: "person.text.rectangle",
                            tint: AppColor.accentPrimary
                        )
                    }
                }

                Text("Projections from your goal, schedule, and body metrics. Actual results vary — what matters is the consistency curve.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 120)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private var projectionHeadline: String {
        let weeks = goalWeeks == 1 ? String(localized: "1 week") : String(localized: "\(goalWeeks) weeks")
        switch primaryGoal {
        case .buildMuscle:    return String(localized: "+\(projectedMuscleGain) in \(weeks)")
        case .loseFat:        return String(localized: "−\(projectedFatLoss) in \(weeks)")
        case .getStronger:    return String(localized: "Build strength\nover \(weeks)")
        case .stayConsistent: return String(localized: "\(daysPerWeek * goalWeeks) sessions\nin \(weeks)")
        case .athletic:       return String(localized: "Work on conditioning\nover \(weeks)")
        case .recomp:         return String(localized: "Work toward a recomp\nover \(weeks)")
        case .betterSleep:    return String(localized: "Track your sleep\nover \(weeks)")
        case .recovery:       return String(localized: "Track your recovery\nover \(weeks)")
        case .antiAging:      return String(localized: "Track your biomarkers\nover \(weeks)")
        case .skinHair:       return String(localized: "Track how you look & feel\nover \(weeks)")
        case .energy:         return String(localized: "Track your energy\nover \(weeks)")
        }
    }

    private var projectionSubtitle: String {
        switch primaryGoal {
        case .buildMuscle, .recomp:
            return String(localized: "Based on your training experience and \(daysPerWeek) sessions per week.")
        case .loseFat:
            return String(localized: "From a moderate deficit at \(daysPerWeek) sessions per week.")
        case .getStronger, .athletic:
            return String(localized: "Progressive overload at \(daysPerWeek) sessions per week.")
        case .stayConsistent:
            return String(localized: "Consistency curve from \(daysPerWeek) sessions per week.")
        case .betterSleep, .recovery, .antiAging, .skinHair, .energy:
            return String(localized: "Trend curve from your recovery signals.")
        }
    }

    private var projectionStatLabel: String {
        switch primaryGoal {
        case .buildMuscle, .recomp:                       return String(localized: "Projected gain")
        case .loseFat:                                     return String(localized: "Projected loss")
        case .getStronger:                                 return String(localized: "Projected lift increase")
        case .stayConsistent, .athletic:                   return String(localized: "Projected sessions")
        case .betterSleep, .recovery, .antiAging,
             .skinHair, .energy:                           return String(localized: "Projected trend")
        }
    }

    private var projectionStatValue: String {
        switch primaryGoal {
        case .buildMuscle: return String(localized: "+\(projectedMuscleGain) lean mass")
        case .loseFat:     return String(localized: "−\(projectedFatLoss) body weight")
        case .getStronger: return String(localized: "+10–15% on your top lifts")
        case .stayConsistent, .athletic: return String(localized: "\(daysPerWeek * goalWeeks) sessions logged")
        case .recomp:      return String(localized: "Body recomp tracked weekly")
        case .betterSleep: return String(localized: "Sleep tracked nightly")
        case .recovery:    return String(localized: "HRV trend tracked daily")
        case .antiAging:   return String(localized: "Biomarker improvement")
        case .skinHair:    return String(localized: "Tracked weekly with photos")
        case .energy:      return String(localized: "Steadier energy curve")
        }
    }

    // Estimates are in kilograms because the underlying model is; the
    // label converts afterwards so an imperial user reads lb, not kg.
    // Both scale with the chosen span, so "8 weeks" and "26 weeks"
    // don't promise the same number.

    /// A range rather than a single number, from half the typical rate
    /// for the user's experience up to it — a personal projection shown
    /// before the paywall shouldn't promise more than training delivers.
    private var projectedMuscleGain: String {
        let months = Double(goalWeeks) * 12 / 52
        let upperKg = monthlyLeanGainKg * months
        let unit = bodyMetrics.unit
        let lower = String(format: "%.1f", unit.weightForDisplay(upperKg / 2))
        return "\(lower)–\(unit.weightLabel(upperKg, fractionDigits: 1))"
    }

    private var projectedFatLoss: String {
        bodyMetrics.unit.weightLabel(min(10, max(1, (estimatedFatLossKg * goalSpanFactor).rounded())))
    }

    private var goalSpanFactor: Double {
        Double(goalWeeks) / 12
    }

    /// Typical lean-mass gain per month on a good program, which falls
    /// steeply with training age.
    private var monthlyLeanGainKg: Double {
        switch Experience(rawValue: experienceLevel) ?? .beginner {
        case .beginner:     return 0.75
        case .intermediate: return 0.4
        case .advanced:     return 0.2
        }
    }

    private var estimatedFatLossKg: Double {
        (bodyMetrics.weightKg ?? 75) * 0.05
    }

    private func projectionStatRow(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Medical disclaimer

    private var disclaimerStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "stethoscope", bounceTrigger: bounceTrigger, isActive: page == .disclaimer)
                    .padding(.top, Spacing.xl)
                OnboardingHeader(
                    title: "A quick safety note.",
                    subtitle: "Atlas is an educational and tracking tool — not a replacement for a clinician."
                )

                VStack(alignment: .leading, spacing: Spacing.md) {
                    disclaimerBullet(
                        icon: "xmark.shield.fill",
                        text: String(localized: "Atlas does **not** prescribe, recommend, or calculate doses for any supplement, medication, or training protocol.")
                    )
                    disclaimerBullet(
                        icon: "person.crop.circle.badge.questionmark.fill",
                        text: String(localized: "Always consult a qualified clinician before starting, changing, or stopping anything you track here.")
                    )
                    disclaimerBullet(
                        icon: "lock.fill",
                        text: privacyBulletText
                    )
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: Spacing.cardCornerRadius)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    /// Names the biometry this device actually has, and leaves the lock out
    /// where there is none, rather than promising Face ID on a Touch ID phone.
    private var privacyBulletText: String {
        let biometrics = BiometricService.shared
        guard biometrics.isAvailable else {
            return String(localized: "Your data lives in your private iCloud.")
        }
        return String(localized: "Your data lives in your private iCloud, and you can lock the app with \(biometrics.biometryName).")
    }

    private func disclaimerBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 24)
            Text(.init(text))
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Permissions (notifications + Apple Health)

    /// Both OS permission asks on one page. Each is optional and stays
    /// re-askable later — notifications from Profile → Daily reminders,
    /// Health from Profile and the Biology tab — so the page is
    /// skippable and nothing downstream assumes either was granted.
    private var permissionsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                OnboardingHeader(
                    title: "Stay on track.",
                    subtitle: "Workout reminders and recovery insights.\nBoth optional."
                )
                .padding(.top, Spacing.xl)

                NotificationPreviewCard(
                    title: "Leg day in 30 minutes",
                    subtitle: "Hit your second session of the week",
                    timestamp: "now"
                )
                .padding(.top, Spacing.sm)

                // Once denied, iOS never shows the prompt again — re-asking
                // was a dead tap. Route to Settings instead.
                permissionRow(
                    icon: "bell.fill",
                    title: String(localized: "Enable notifications"),
                    subtitle: notificationsDenied
                        ? String(localized: "Turned off in Settings. Tap to open Settings.")
                        : String(localized: "Reminders, weekly recaps, and rest-timer alerts."),
                    isLoading: requestingNotifications,
                    isOn: notificationsAuthorized,
                    action: notificationsDenied ? openAppSettings : requestNotifications
                )

                permissionRow(
                    icon: "heart.fill",
                    title: String(localized: "Connect Apple Health"),
                    subtitle: String(localized: "Reads sleep, HRV, heart rate, and weight for Recovery."),
                    isLoading: requestingHealth,
                    isOn: dataStore.profile.healthConnected,
                    action: requestHealth
                )

                Text("Health is read-only by default. You can give Atlas permission to save nutrition to Health later in Profile.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String,
                               isLoading: Bool, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(AppFont.scaled(20, weight: .semibold))
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
                } else {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(isOn ? AppColor.positive : AppColor.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.md)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(isLoading || isOn)
        .accessibilityValue(isOn ? "Enabled" : "Off")
        .onChange(of: isOn) { _, granted in
            if granted { Haptics.success() }
        }
    }

    private func openAppSettings() {
        haptic()
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private func requestHealth() {
        haptic()
        requestingHealth = true
        Task {
            let granted = await HealthKitService.shared.requestAuthorization()
            requestingHealth = false
            // Note: HealthKit deliberately doesn't tell apps when the
            // user denies a specific type — `granted == true` only
            // confirms the user saw the dialog. The toggleHealthConnection
            // path re-runs the auth request anyway and only flips the
            // flag when the system reports success, so a deny-all
            // still leaves healthConnected false.
            if granted, !dataStore.profile.healthConnected {
                _ = await dataStore.toggleHealthConnection()
            }
            OnboardingFunnelTracker.recordEvent(granted ? "health_granted" : "health_denied")
        }
    }

    private func requestNotifications() {
        haptic()
        requestingNotifications = true
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            requestingNotifications = false
            notificationsAuthorized = granted
            notificationsDenied = !granted
            // Surface the OS grant on the user's dose-reminders flag too
            // so peptide-protocol reminders fire by default the first time
            // the user adds a protocol. Independent of the OS auth state
            // tracked above — the user can still toggle this flag off
            // later from Profile without revoking notification permission.
            if granted, !dataStore.profile.doseRemindersEnabled {
                dataStore.profile.doseRemindersEnabled = true
                // Persist so a crash / quick backgrounding between here
                // and the next onboarding-driven save doesn't lose the
                // toggle. Settings-side `onChange` handlers do this same
                // belt-and-braces persist.
                dataStore.persistProfile()
            }
            // This step promises workout reminders, so a grant switches
            // the training-day nudge on at the time picked earlier.
            if granted {
                var reminders = DailyReminderSettings.load(training: dataStore.profile.trainingPreferences)
                reminders.slots[.workout]?.isEnabled = true
                reminders.save()
            }
            OnboardingFunnelTracker.recordEvent(granted ? "notifications_granted" : "notifications_denied")
        }
    }

    // MARK: - Creator code

    private var creatorCodeField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GlassTextField(
                placeholder: "Enter creator code…",
                text: $creatorCodeInput,
                icon: "person.text.rectangle"
            )
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { if hasCreatorCodeToApply { applyCreatorCode() } }

            if let error = creatorError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(AppFont.scaled(11, weight: .semibold))
                    Text(error)
                        .font(AppFont.caption2)
                }
                .foregroundStyle(AppColor.destructive)
                .padding(.leading, Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func creatorSuccessCard(_ attribution: CreatorAttribution) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(AppColor.accentPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Code applied")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                // Attribution only — the checkout applies no discount,
                // so promising "X% off" here would charge full price.
                Text("\(attribution.creatorName) gets credit for bringing you to Atlas.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .strokeBorder(AppColor.accentPrimary.opacity(0.45), lineWidth: 1)
        )
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}

/// Compact trust pill under the welcome headline — the first trust
/// anchor before any data is asked from the user. Verifiable claims
/// only: the previous five-star "4.9 · 12k+ athletes" version had no
/// App Store source behind it, and fabricated ratings are a Guideline
/// 2.3.1 problem. Reinstate a rating pill only when it renders the
/// real, current App Store figure.
private struct SocialProofPill: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Private by design")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text("·")
                .foregroundStyle(AppColor.textTertiary)
            Text("no ads, no tracking")
                .font(AppFont.scaled(13, weight: .semibold))
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
        // A glyph plus a bare "·" is several meaningless VoiceOver
        // stops; the claim is one fact, so it's spoken as one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Private by design. No ads, no tracking.")
    }
}

/// Personalized projection curve for the onboarding "you'll get there"
/// moment. Hand-drawn bezier — convex for goals where the user gains
/// (muscle, sessions, sleep), concave-rising for goals where the user
/// loses (fat). Real numbers aren't shown on the axes; this is a shape-
/// of-the-curve reveal, not a forecasting tool.
private struct ProjectionChart: View {
    let goal: OnboardingView.PrimaryGoal
    let daysPerWeek: Int
    let startWeightKg: Double?
    let weeks: Int
    let targetDate: Date
    let spokenSummary: String
    let revealed: Bool

    @State private var drawAmount: CGFloat = 0
    /// Separate from `drawAmount`: reading the model value (already 1
    /// the instant the draw starts) put the endpoint dot on screen at
    /// frame 0, ahead of the line it caps.
    @State private var dotVisible = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    fillUnder(in: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    goal.tint.opacity(0.22),
                                    goal.tint.opacity(0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(drawAmount)

                    curve(in: size)
                        .trim(from: 0, to: drawAmount)
                        .stroke(
                            goal.tint,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )

                    if dotVisible {
                        Circle()
                            .strokeBorder(goal.tint, lineWidth: 3)
                            .background(Circle().fill(AppColor.background))
                            .frame(width: 14, height: 14)
                            .position(endPoint(in: size))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(height: 180)

            HStack {
                Text("Today")
                Spacer()
                Text(targetDate.formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(AppFont.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.textSecondary)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(spokenSummary), by \(targetDate.formatted(.dateTime.month(.wide).day()))"
        )
        .onChange(of: revealed) { _, newValue in
            if newValue {
                reveal()
            } else {
                drawAmount = 0
                dotVisible = false
            }
        }
        .onAppear {
            if revealed { reveal() }
        }
    }

    /// The curve draws, then the endpoint dot lands as the line reaches
    /// it. `AppAnimation.with` drops both to an instant state change
    /// under Reduce Motion.
    private func reveal() {
        AppAnimation.with(AppAnimation.draw) { drawAmount = 1 }
        AppAnimation.with(AppAnimation.springSnappy.delay(1.0)) { dotVisible = true }
    }

    /// Convex up for gain-style goals, convex down for loss-style goals.
    private var isLossCurve: Bool {
        goal == .loseFat
    }

    private func curve(in size: CGSize) -> Path {
        Path { path in
            let start = startPoint(in: size)
            let end = endPoint(in: size)
            let ctrl1: CGPoint
            let ctrl2: CGPoint
            if isLossCurve {
                // Steep early drop, plateau into the goal — feels real
                // because steady fat loss decelerates as bodyfat falls.
                ctrl1 = CGPoint(x: size.width * 0.30, y: size.height * 0.45)
                ctrl2 = CGPoint(x: size.width * 0.65, y: size.height * 0.78)
            } else {
                // Modest start, steady acceleration through week 6,
                // ease toward the goal endpoint.
                ctrl1 = CGPoint(x: size.width * 0.30, y: size.height * 0.78)
                ctrl2 = CGPoint(x: size.width * 0.65, y: size.height * 0.25)
            }
            path.move(to: start)
            path.addCurve(to: end, control1: ctrl1, control2: ctrl2)
        }
    }

    private func fillUnder(in size: CGSize) -> Path {
        Path { path in
            let start = startPoint(in: size)
            let end = endPoint(in: size)
            let ctrl1: CGPoint
            let ctrl2: CGPoint
            if isLossCurve {
                ctrl1 = CGPoint(x: size.width * 0.30, y: size.height * 0.45)
                ctrl2 = CGPoint(x: size.width * 0.65, y: size.height * 0.78)
            } else {
                ctrl1 = CGPoint(x: size.width * 0.30, y: size.height * 0.78)
                ctrl2 = CGPoint(x: size.width * 0.65, y: size.height * 0.25)
            }
            path.move(to: start)
            path.addCurve(to: end, control1: ctrl1, control2: ctrl2)
            path.addLine(to: CGPoint(x: end.x, y: size.height))
            path.addLine(to: CGPoint(x: start.x, y: size.height))
            path.closeSubpath()
        }
    }

    private func startPoint(in size: CGSize) -> CGPoint {
        if isLossCurve {
            return CGPoint(x: 0, y: size.height * 0.18)
        }
        return CGPoint(x: 0, y: size.height * 0.85)
    }

    private func endPoint(in size: CGSize) -> CGPoint {
        if isLossCurve {
            return CGPoint(x: size.width, y: size.height * 0.85)
        }
        return CGPoint(x: size.width, y: size.height * 0.18)
    }
}

/// Theme picker presented as the second full-screen cover in the
/// onboarding tail. Wraps `ThemeChoicePage` with a chrome bar so the
/// user can confirm and finally enter the app.
private struct ThemePickerCover: View {
    let onContinue: () -> Void
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        ScrollView {
            ThemeChoicePage(theme: themeManager)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.xxl)
        }
        .pinnedFooter {
            PrimaryCTAButton(title: "Enter Atlas") {
                Haptics.impact(.medium)
                onContinue()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(AppColor.background.ignoresSafeArea())
        .preferredColorScheme(themeManager.displayMode.preferredScheme)
    }
}

private extension View {
    /// The one selection chrome for onboarding choice cards — goals,
    /// attribution, experience, equipment. Neutral glass at rest; a
    /// tinted wash and tint hairline once picked. Replaces fifteen
    /// hand-copied fill-plus-stroke rectangles.
    func onboardingChoice(
        isSelected: Bool,
        tint: Color = AppColor.accentPrimary,
        cornerRadius: CGFloat = Spacing.smallCornerRadius
    ) -> some View {
        glassControl(
            .rect(cornerRadius: cornerRadius),
            tint: isSelected ? tint.opacity(0.18) : nil,
            border: isSelected ? tint : AppColor.glassBorder,
            interactive: false
        )
    }

    /// Compact pickers (days, weekdays, time slots, target-date chips)
    /// fill solid when picked. `accentFill` is the stop that carries
    /// `onAccent` ink at AA in every theme; the old `accentPrimary` fill
    /// under `background` ink did not.
    @ViewBuilder
    func onboardingFilledChoice(
        isSelected: Bool,
        _ preset: GlassPreset = .rect(cornerRadius: Spacing.smallCornerRadius)
    ) -> some View {
        if isSelected {
            self.background { preset.shape.fill(AppColor.accentFill) }
        } else {
            self.glassControl(preset, interactive: false)
        }
    }
}
