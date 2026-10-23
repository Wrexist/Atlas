import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Onboarding for Atlas — a health & fitness app. 16 steps covering
/// training, nutrition, biology / recovery signals, AI-assisted
/// research, and optional supplement tracking. Lean — every step
/// earns its place: a moment, a data ask, a permission ask, or a
/// reveal. The personalization captured here drives a date-anchored
/// projection that lands right before the post-Ready paywall.
///
/// Page indices live in the nested `Page` enum so reordering only
/// requires renaming there.
///
/// State writes:
///
///   - `hasCompletedOnboarding` — final dismiss flag (set by the
///     paywall handlers via the theme picker, not by the Ready button
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
    /// instead of restarting at the Welcome screen. Cleared on the
    /// final "Ready" step (which also sets `hasCompletedOnboarding`)
    /// so a future re-run of onboarding (testing path) starts at 0.
    @AppStorage("onboarding.lastPage") private var lastPage: Int = 0

    @State private var page: Int = 0
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
    /// signInStep view re-renders when AuthService's @Observable
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
    // Live "try a set" demo state.
    @State private var demoSet = SetEntry(index: 1, weightKg: 60, reps: 8, completed: false)
    @State private var demoCelebrate = false
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
    @State private var goalDate: Date = Calendar.current.date(
        byAdding: .weekOfYear, value: 12, to: Date()
    ) ?? Date().addingTimeInterval(60 * 60 * 24 * 84)
    /// Selected marketing-attribution channel. Persisted into the funnel
    /// snapshot only — never into the user profile (the marketing-channel
    /// answer is anonymous-aggregate signal, not personal data).
    @State private var attributionChannel: AttributionChannel? = nil

    enum AttributionChannel: String, CaseIterable, Identifiable {
        case friend, appStore, tiktok, youtube, reddit, podcast, other
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .friend:   return "A friend"
            case .appStore: return "App Store"
            case .tiktok:   return "TikTok"
            case .youtube:  return "YouTube"
            case .reddit:   return "Reddit"
            case .podcast:  return "Podcast"
            case .other:    return "Other"
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

    // Page indices — single source of truth for the flow. Adjusting
    // ordering only requires renaming here; everything else reads
    // through these constants.
    private enum Page {
        static let welcome          = 0
        static let signIn           = 1
        static let attribution      = 2
        static let name             = 3
        static let goal             = 4
        static let experience       = 5
        static let bodyMetrics      = 6
        static let schedule         = 7
        static let equipment        = 8
        static let demoSet          = 9
        static let projection       = 10
        static let disclaimer       = 11
        static let notifications    = 12
        static let health           = 13
        static let creatorCode      = 14
        static let ready            = 15
        static let total            = 16
        // Removed (Product Architecture 07): `buildingPlan` — a 2.6 s
        // synthetic ring animation with zero computation behind it
        // (every real write happens on earlier steps); pretending to
        // process erodes trust. And `email` — the captured address was
        // stored on the profile and never sent or read anywhere, while
        // the optional Sign in with Apple step already covers contact.
    }

    private var totalPages: Int { Page.total }

    enum PrimaryGoal: String, CaseIterable, Identifiable {
        case buildMuscle, loseFat, getStronger, stayConsistent,
             athletic, recomp, betterSleep, recovery, antiAging,
             skinHair, energy
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .buildMuscle:    return "Build muscle"
            case .loseFat:        return "Lose fat"
            case .getStronger:    return "Get stronger"
            case .stayConsistent: return "Stay consistent"
            case .athletic:       return "Athletic performance"
            case .recomp:         return "Recomp"
            case .betterSleep:    return "Better sleep"
            case .recovery:       return "Faster recovery"
            case .antiAging:      return "Healthy aging"
            case .skinHair:       return "Look & feel better"
            case .energy:         return "More energy"
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
    private var gatedPage: Binding<Int> {
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
                    // Tags use `Page.*` integer constants (see Page
                    // namespace below) rather than literal Ints so a
                    // step insertion doesn't silently shift every
                    // downstream tag and re-bucket the funnel events.
                    welcome.tag(Page.welcome)
                    signInStep.tag(Page.signIn)
                    attributionStep.tag(Page.attribution)
                    nameStep.tag(Page.name)
                    goalStep.tag(Page.goal)
                    experienceStep.tag(Page.experience)
                    bodyMetricsStep.tag(Page.bodyMetrics)
                    scheduleStep.tag(Page.schedule)
                    equipmentStep.tag(Page.equipment)
                    demoSetStep.tag(Page.demoSet)
                    projectionStep.tag(Page.projection)
                    disclaimerStep.tag(Page.disclaimer)
                    notificationsStep.tag(Page.notifications)
                    healthStep.tag(Page.health)
                    creatorCodeStep.tag(Page.creatorCode)
                    readyStep.tag(Page.ready)
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
            if page == 0 && lastPage > 0 && lastPage < totalPages {
                page = lastPage
            }
        }
        .onChange(of: page) { _, newValue in
            lastPage = newValue
        }
        .onAppear {
            OnboardingFunnelTracker.recordStepEntered(stepName(for: page), index: page)
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
            OnboardingFunnelTracker.recordStepEntered(stepName(for: newPage), index: newPage)
            // Focus the name field only when the name page is actually
            // the current one. Driving this from the sub-view's
            // `.onAppear` summoned the keyboard early — TabView mounts
            // adjacent pages, so `.onAppear` fired on the prior page.
            //
            // Leaving any text-entry step must put the keyboard away —
            // otherwise the name keyboard rode along onto the goal grid
            // (and the creator-code keyboard onto its
            // neighbours), covering the lower half of the next card.
            if newPage == Page.name {
                nameFocused = true
            } else {
                nameFocused = false
                dismissKeyboard()
            }
            // Move VoiceOver to the new step instead of leaving focus
            // parked on the footer button of the step that just left.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            if newPage == Page.ready {
                Haptics.success()
            }
            // Driven by the page, not the step's `.onAppear`: the paged
            // TabView mounts neighbours, so the curve used to draw while
            // the user was still on the Demo-set page.
            if newPage == Page.projection {
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
            // user isn't stuck on the Ready page tapping "Enter Atlas"
            // re-triggering the paywall every time (audit code-review
            // #10). The funnel event "paywall_dismissed_externally"
            // lets us distinguish this from user-initiated decline.
            if !presented && !showThemePicker && !hasCompleted {
                OnboardingFunnelTracker.recordEvent("paywall_dismissed_externally")
                showThemePicker = true
            }
        }
    }

    /// Maps a page index to a stable string name so the funnel
    /// snapshot is human-readable in Console / a future analytics
    /// export. Anything past the known range falls back to "unknown_N".
    private func stepName(for index: Int) -> String {
        switch index {
        case Page.welcome:        return "welcome"
        case Page.signIn:         return "sign_in"
        case Page.attribution:    return "attribution"
        case Page.name:           return "name"
        case Page.goal:           return "goal_and_date"
        case Page.experience:     return "experience"
        case Page.bodyMetrics:    return "body_metrics"
        case Page.schedule:       return "schedule"
        case Page.equipment:      return "equipment"
        case Page.demoSet:        return "demo_set"
        case Page.projection:     return "projection"
        case Page.disclaimer:     return "disclaimer"
        case Page.notifications:  return "notifications"
        case Page.health:         return "health"
        case Page.creatorCode:    return "creator_code"
        case Page.ready:          return "ready"
        default:                  return "unknown_\(index)"
        }
    }

    /// Copies whatever an earlier run already saved into the step state.
    /// Resuming mid-flow restores `page`, but without this every field
    /// behind it fell back to its default: the Ready summary showed a
    /// generic schedule, and Projection skipped the nutrition-target
    /// write because `bodyMetrics` read as unspecified.
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
                if page > 0 {
                    Button {
                        haptic()
                        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { page = max(0, page - 1) }
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

            Text("\(min(page + 1, totalPages)) / \(totalPages)")
                .font(AppFont.scaled(11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textTertiary)
                .contentTransition(.numericText())
                .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: page)
        }
        // The capsule and the "3 / 16" counter are one fact; read as two
        // stops they were meaningless on their own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(page + 1, totalPages)) of \(totalPages)")
    }

    private var progressFraction: CGFloat {
        guard totalPages > 1 else { return 1 }
        let pos = CGFloat(min(page, totalPages - 1)) / CGFloat(totalPages - 1)
        return min(1, max(0, pos))
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            primaryButton
            // `showSkipOnCurrentPage` whitelists Skip on the optional
            // steps only; the personalization-critical pages (goal,
            // experience, body metrics, schedule, equipment,
            // projection) are intentionally excluded — skipping body
            // metrics silently breaks nutrition targets and skipping
            // projection bypasses the derived-targets write.
            if showSkipOnCurrentPage {
                Button("Skip") {
                    haptic()
                    // Record the skip with the step name so the funnel
                    // can distinguish "user advanced after engaging" vs
                    // "user tapped Skip" (audit integration M3).
                    OnboardingFunnelTracker.recordEvent("skip_\(stepName(for: page))")
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

    /// Skip is shown only on optional informational pages. Data-input
    /// pages (goal, experience, body, schedule, equipment) lose Skip so
    /// that personalization is genuinely captured — skipping these
    /// poisons the recommendation engine and removes the sunk-cost
    /// commitment that drives trial conversion.
    private var showSkipOnCurrentPage: Bool {
        // Projection deliberately omitted — that step also persists
        // the derived nutrition targets, so a Skip would silently
        // bypass the write (audit MED #2). Continue does the right
        // thing whether the user lingered on the chart or not.
        switch page {
        case Page.signIn, Page.attribution, Page.demoSet,
             Page.notifications, Page.health,
             Page.creatorCode:
            return true
        default:
            return false
        }
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
        case Page.welcome:      return "Let's go"
        case Page.disclaimer:   return "I understand"
        case Page.creatorCode:  return hasCreatorCodeToApply ? "Apply" : "Continue"
        case Page.ready:        return "Enter Atlas"
        default:                return "Continue"
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
        case Page.name:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case Page.goal:
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
        switch page {
        case Page.name:
            dataStore.updateProfileIdentity(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: dataStore.profile.bio
            )
        case Page.goal:
            // Merged step persists both the primary goal AND the
            // chosen date. setPrimaryGoal guards against goals that
            // aren't in profile.goals, so updateGoals must run first
            // (audit C2). Flush sync so a force-quit within the
            // 350ms debounce doesn't lose either field.
            let raw = primaryGoal.rawValue
            var goalSet = Set(dataStore.profile.goals)
            goalSet.formUnion(selectedGoals.map(\.rawValue))
            goalSet.insert(raw)
            dataStore.updateGoals(goalSet)
            dataStore.setPrimaryGoal(raw)
            dataStore.profile.goalDate = goalDate
            dataStore.flushPendingSave()
        case Page.experience:
            // Seed `activityLevel` from the experience picker on the
            // way OUT of the experience step. This sets a sensible
            // default before the user lands on the body-metrics page
            // (audit Meals L12). Anything the user changes on a later
            // step persists — only seeding here, not overriding on
            // save, so we never clobber an explicit choice.
            bodyMetrics.activityLevel = activityFromExperience()
        case Page.bodyMetrics:
            bodyMetrics = BodyMetricsRanges.filledWithDefaults(bodyMetrics)
            dataStore.updateBodyMetrics(bodyMetrics)
        case Page.schedule, Page.equipment:
            // Schedule and equipment both feed the same struct.
            // Persist on advance off either step (writes are idempotent
            // — currentTrainingPrefs builds from the live @State) so a
            // user who edits schedule, advances to equipment, then
            // back-navs past schedule to bodyMetrics doesn't lose the
            // schedule changes (audit code-review #H3).
            dataStore.updateTrainingPreferences(currentTrainingPrefs)
        case Page.projection:
            // Nutrition targets derived from body metrics persist here,
            // alongside the user seeing them on the same screen as the
            // projection (merged from a now-deleted dedicated step).
            if let targets = NutritionMath.recommendedTargets(for: bodyMetrics, goalRaw: primaryGoal.rawValue) {
                dataStore.updateNutritionTargets(targets)
            }
        case Page.disclaimer:
            // One-tap acknowledge → advance. The persistent
            // @AppStorage timestamp is the legal audit trail.
            disclaimerAcknowledgedAt = Date().timeIntervalSince1970
            OnboardingFunnelTracker.recordEvent("disclaimer_acknowledged")
        case Page.creatorCode:
            if creatorAttribution == nil {
                applyCreatorCode()
                return
            }
        case Page.ready:
            // Present the trial paywall — flow continues through the
            // paywall and the theme picker before hasCompleted flips.
            // The theme picker's onContinue path resets `lastPage = 0`
            // so a future re-onboarding starts at page 0. An existing
            // subscriber (reinstall / new device) skips the trial offer.
            if StoreService.shared.isProUser {
                OnboardingFunnelTracker.recordEvent("paywall_skipped_pro")
                showThemePicker = true
            } else {
                showTrialOffer = true
            }
            return
        default:
            break
        }
        advance()
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
            AppAnimation.with(AppAnimation.fadeIn) { creatorError = "Code not found — double-check and try again." }
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

    /// Maps the lifting-experience picker to the closest TDEE
    /// activity bucket. Conservative — most users land in `.moderate`
    /// and can tune up in Profile when their training volume warrants.
    private func activityFromExperience() -> ActivityLevel {
        switch Experience(rawValue: experienceLevel) ?? .beginner {
        case .beginner:     return .light
        case .intermediate: return .moderate
        case .advanced:     return .active
        }
    }

    private func advance() {
        // Tear down the keyboard before the page transition so it can't
        // linger over the next card mid-animation.
        dismissKeyboard()
        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { page = min(totalPages - 1, page + 1) }
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
                    isActive: page == Page.welcome
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
    /// the 56pt Welcome title and the Sign-in button stack both overflow
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

    /// Optional sign-in step. Skipping is genuinely fine — every feature
    /// works without an Apple ID — but a signed-in user gets cloud sync
    /// across devices, abandoned-onboarding retargeting hooks, and
    /// referral credit when the backend ships.
    private var signInStep: some View {
        centeredScroll {
            VStack(spacing: Spacing.xl) {
                Spacer()
                HeroIcon(symbol: "person.crop.circle.fill", bounceTrigger: bounceTrigger, isActive: page == Page.signIn)
                OnboardingHeader(
                    title: "Save your progress.",
                    subtitle: "Optional. Back up across your devices."
                )
                VStack(spacing: Spacing.md) {
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
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            if signedIn { Haptics.success() }
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
            Text(authService.userDisplayName.map { "Signed in as \($0)" } ?? "Signed in with Apple")
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

    // MARK: - Attribution survey

    /// Marketing-channel survey. Anonymous, captured into the funnel
    /// snapshot only — useful for allocating ad spend, never stored on
    /// the user profile. Skippable.
    private var attributionStep: some View {
        VStack(spacing: Spacing.lg) {
            OnboardingHeader(title: "Where did you hear about Atlas?", subtitle: "Optional.")
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xl)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.sm) {
                    ForEach(AttributionChannel.allCases) { channel in
                        attributionChip(channel)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
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
        VStack(spacing: Spacing.xl) {
            HeroIcon(symbol: "person.fill", bounceTrigger: bounceTrigger, isActive: page == Page.name)
                .padding(.top, Spacing.xl)
            OnboardingHeader(title: "What should we call you?")
                .padding(.horizontal, Spacing.lg)
            GlassTextField(placeholder: "First name", text: $name, icon: nil, focus: $nameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .font(AppFont.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
                .onSubmit { if primaryEnabled { primaryAction() } }
            Spacer()
        }
        .onAppear {
            // Focus is driven from the root `.onChange(of: page)` —
            // setting it here fired while the page was still off-screen
            // (TabView pre-mounts neighbours) and summoned the keyboard
            // over the previous step.
            //
            // Pre-fill from the Apple-relayed full name if the user
            // signed in on step 1. AppleSignInButton only forwards the
            // name on the very first authorization — once we have it,
            // we shouldn't ask twice (audit H2). Trim to first name so
            // the placeholder semantic ("First name") still reads true.
            if name.isEmpty, let display = authService.userDisplayName {
                let first = display.split(separator: " ").first.map(String.init) ?? display
                if !first.isEmpty { name = first }
            }
        }
    }

    // MARK: - Primary goal

    /// Merged "what's your goal + by when?" step. The user picks a
    /// goal from the grid; the date row animates in below once a
    /// goal is selected. Two intentions, one screen — captures
    /// commitment without burning a full page on date-picking.
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
                            .padding(.bottom, Spacing.xxxxl)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Color.clear.frame(height: Spacing.xxxxl)
                    }
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
                goalDateChip("8 wks", a11yLabel: "8 weeks", weeks: 8)
                goalDateChip("12 wks", a11yLabel: "12 weeks", weeks: 12)
                goalDateChip("6 mo", a11yLabel: "6 months", weeks: 26)
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
        "That's \(goalWeeks) week\(goalWeeks == 1 ? "" : "s") to commit."
    }

    /// Weeks between today and the user's chosen goal date, clamped to
    /// at least one week. Used by the projection step's headline and
    /// the ProjectionChart's framing. Counted in calendar days and
    /// rounded: truncating the raw interval read "11 weeks" a few
    /// seconds after the user tapped "12 wks".
    private var goalWeeks: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: goalDate)
        ).day ?? 0
        return max(1, Int((Double(days) / 7).rounded()))
    }

    // MARK: - Experience

    private var experienceStep: some View {
        VStack(spacing: Spacing.lg) {
            OnboardingHeader(title: "How much experience?")
                .padding(.horizontal, Spacing.lg)
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

    // MARK: - Schedule

    private var scheduleStep: some View {
        VStack(spacing: Spacing.lg) {
            OnboardingHeader(title: "When do you train?")
                .padding(.horizontal, Spacing.lg)
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

    private var equipmentStep: some View {
        VStack(spacing: Spacing.lg) {
            OnboardingHeader(title: "What gear do you have?", subtitle: keepOneEquipmentHint)
                .padding(.horizontal, Spacing.lg)
                .appAnimation(AppAnimation.fadeIn, value: keepOneEquipmentHinted)
                .padding(.top, Spacing.xl)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: Spacing.sm) {
                    ForEach(EquipmentKind.accessChoices) { equipmentCard($0) }
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

    private func equipmentCard(_ kind: EquipmentKind) -> some View {
        let selected = equipment.contains(kind)
        return Button {
            if selected {
                // Always keep at least one option selected — an empty
                // set makes ExerciseLibrary filters return zero hits
                // and the program preview renders a blank list. The
                // last deselect is refused out loud — a warning buzz,
                // a shake, and the "Keep at least one" subtitle — so
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

    private var keepOneEquipmentHint: LocalizedStringKey? {
        keepOneEquipmentHinted ? "Keep at least one" : nil
    }

    /// Three-step horizontal shake (8 → -8 → 0), the lock screen's
    /// refusal idiom. Skipped under Reduce Motion; the warning haptic
    /// and the subtitle already carry the message.
    private func shakeEquipmentCard(_ kind: EquipmentKind) async {
        guard !reduceMotion else { return }
        shakingEquipment = kind
        AppAnimation.with(AppAnimation.shake) { equipmentShakeOffset = 8 }
        try? await Task.sleep(for: .milliseconds(80))
        AppAnimation.with(AppAnimation.shake) { equipmentShakeOffset = -8 }
        try? await Task.sleep(for: .milliseconds(80))
        AppAnimation.with(AppAnimation.shakeSettle) { equipmentShakeOffset = 0 }
    }

    // MARK: - Try a set (interactive workout demo)

    private var demoSetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                OnboardingHeader(title: "Try logging a set.", subtitle: "Two taps. That's the whole loop.")
                    .padding(.top, Spacing.xl)

                demoCard
                    .padding(.top, Spacing.sm)

                if demoCelebrate {
                    successBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            .font(AppFont.scaled(20, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bench Press")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Chest · Barbell")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    Spacer()
                }
                Divider().background(AppColor.glassBorder)
                SetEditorRow(
                    set: $demoSet,
                    previousSet: SetEntry(index: 0, weightKg: 55, reps: 8, completed: true),
                    unit: bodyMetrics.unit,
                    onDelete: {}
                )
                .onChange(of: demoSet.completed) { _, completed in
                    if completed && !demoCelebrate {
                        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { demoCelebrate = true }
                        // Haptics aren't motion; `Haptics` already honours
                        // the user's own haptics toggle.
                        Haptics.success()
                    }
                }
                Text(demoCelebrate
                     ? "Nice. That's it — your workouts are this fast."
                     : "Tap the circle to log this set.")
                    .font(AppFont.footnote)
                    .foregroundStyle(demoCelebrate ? AppColor.positive : AppColor.textTertiary)
                    .appAnimation(AppAnimation.fadeIn, value: demoCelebrate)
            }
        }
    }

    private var successBanner: some View {
        HStack(spacing: Spacing.sm) {
            MilestoneArtwork(
                symbol: "checkmark",
                size: 48,
                isActive: page == Page.demoSet && demoCelebrate
            )
            Text("Set logged. Atlas tracks weight, reps, RPE — and lights up the muscles you trained.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.positive.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .stroke(AppColor.positive.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Projection (personalised plan reveal)

    /// Cal-AI-style projection moment. Numbers are illustrative — the
    /// curve shape and the headline copy adapt to the user's primary
    /// goal so it reads as "we built this for you" instead of a
    /// generic stock chart.
    private var projectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                OnboardingHeader(
                    title: LocalizedStringKey(projectionHeadline),
                    subtitle: LocalizedStringKey(projectionSubtitle)
                )
                .padding(.top, Spacing.xl)

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
                        // Daily nutrition targets folded in here so the
                        // user sees the derived plan inline rather than
                        // on a separate "Nutrition" step. Hidden when
                        // body metrics aren't filled in enough to derive
                        // a real Mifflin-St Jeor estimate.
                        projectionStatRow(
                            label: "Daily targets",
                            value: "\(targets.calories) kcal\n\(targets.proteinG) g protein · \(targets.carbsG) g carbs · \(targets.fatG) g fat",
                            icon: "fork.knife",
                            tint: AppColor.achievement
                        )
                    }
                    projectionStatRow(
                        label: "First milestone",
                        value: "Week 2 · habit locked in",
                        icon: "checkmark.seal.fill",
                        tint: AppColor.accentPrimary
                    )
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
        let weeks = goalWeeks == 1 ? "1 week" : "\(goalWeeks) weeks"
        switch primaryGoal {
        case .buildMuscle:    return "+\(projectedMuscleGain) in \(weeks)"
        case .loseFat:        return "−\(projectedFatLoss) in \(weeks)"
        case .getStronger:    return "Build strength\nover \(weeks)"
        case .stayConsistent: return "\(daysPerWeek * goalWeeks) sessions\nin \(weeks)"
        case .athletic:       return "Work on conditioning\nover \(weeks)"
        case .recomp:         return "Work toward a recomp\nover \(weeks)"
        case .betterSleep:    return "Track your sleep\nover \(weeks)"
        case .recovery:       return "Track your recovery\nover \(weeks)"
        case .antiAging:      return "Track your biomarkers\nover \(weeks)"
        case .skinHair:       return "Track how you look & feel\nover \(weeks)"
        case .energy:         return "Track your energy\nover \(weeks)"
        }
    }

    private var projectionSubtitle: String {
        switch primaryGoal {
        case .buildMuscle, .recomp:
            return "Based on your training experience and \(daysPerWeek) sessions per week."
        case .loseFat:
            return "From a moderate deficit at \(daysPerWeek) sessions per week."
        case .getStronger, .athletic:
            return "Progressive overload at \(daysPerWeek) sessions per week."
        case .stayConsistent:
            return "Consistency curve from \(daysPerWeek) sessions per week."
        case .betterSleep, .recovery, .antiAging, .skinHair, .energy:
            return "Trend curve from your recovery signals."
        }
    }

    private var projectionStatLabel: String {
        switch primaryGoal {
        case .buildMuscle, .recomp:                       return "Projected gain"
        case .loseFat:                                     return "Projected loss"
        case .getStronger:                                 return "Projected lift increase"
        case .stayConsistent, .athletic:                   return "Projected sessions"
        case .betterSleep, .recovery, .antiAging,
             .skinHair, .energy:                           return "Projected trend"
        }
    }

    private var projectionStatValue: String {
        switch primaryGoal {
        case .buildMuscle: return "+\(projectedMuscleGain) lean mass"
        case .loseFat:     return "−\(projectedFatLoss) body weight"
        case .getStronger: return "+10–15% on your top lifts"
        case .stayConsistent, .athletic: return "\(daysPerWeek * goalWeeks) sessions logged"
        case .recomp:      return "Body recomp tracked weekly"
        case .betterSleep: return "Sleep tracked nightly"
        case .recovery:    return "HRV trend tracked daily"
        case .antiAging:   return "Biomarker improvement"
        case .skinHair:    return "Tracked weekly with photos"
        case .energy:      return "Steadier energy curve"
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
                HeroIcon(symbol: "stethoscope", bounceTrigger: bounceTrigger, isActive: page == Page.disclaimer)
                    .padding(.top, Spacing.xl)
                OnboardingHeader(
                    title: "A quick safety note.",
                    subtitle: "Atlas is an educational and tracking tool — not a replacement for a clinician."
                )

                VStack(alignment: .leading, spacing: Spacing.md) {
                    disclaimerBullet(
                        icon: "xmark.shield.fill",
                        text: "Atlas does **not** prescribe, recommend, or calculate doses for any supplement, medication, or training protocol."
                    )
                    disclaimerBullet(
                        icon: "person.crop.circle.badge.questionmark.fill",
                        text: "Always consult a qualified clinician before starting, changing, or stopping anything you track here."
                    )
                    disclaimerBullet(
                        icon: "lock.fill",
                        text: "Your data lives in your private iCloud, and you can lock the app with Face ID."
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

    // MARK: - Notifications (with preview)

    private var notificationsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "bell.badge.fill", bounceTrigger: bounceTrigger, isActive: page == Page.notifications)
                    .padding(.top, Spacing.xl)
                OnboardingHeader(
                    title: "Stay on track.",
                    subtitle: "Workout reminders, weekly recaps,\nand rest-timer alerts."
                )
                .padding(.horizontal, Spacing.lg)

                NotificationPreviewCard(
                    title: "Leg day in 30 minutes",
                    subtitle: "Hit your second session of the week",
                    timestamp: "now"
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

                // Once denied, iOS never shows the prompt again — re-asking
                // was a dead tap. Route to Settings instead.
                permissionRow(
                    icon: "bell.fill",
                    title: "Enable notifications",
                    subtitle: notificationsDenied
                        ? "Turned off in Settings. Tap to open Settings."
                        : "Tap to allow. You can change this anytime.",
                    isLoading: requestingNotifications,
                    isOn: notificationsAuthorized,
                    action: notificationsDenied ? openAppSettings : requestNotifications
                )
                .padding(.horizontal, Spacing.lg)

                Spacer(minLength: 100)
            }
        }
    }

    // MARK: - Health (with value preview)

    private var healthStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(
                    symbol: "heart.fill",
                    color: AppColor.metricHeartRate,
                    bounceTrigger: bounceTrigger,
                    isActive: page == Page.health
                )
                .padding(.top, Spacing.xl)
                OnboardingHeader(
                    title: "Connect Apple Health.",
                    subtitle: "Unlock Recovery, HRV trends,\nand sleep-quality insights."
                )
                .padding(.horizontal, Spacing.lg)

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

                Text("Reads only by default. Optional nutrition-write turns on later from Profile.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 100)
            }
        }
    }

    /// Mocked Health Monitor grid — three sample biomarker cards that
    /// preview what connecting Health unlocks. Pure presentation; the
    /// values are illustrative, so the grid is visibly labelled as an
    /// example to avoid reading as the user's own data.
    private var healthValuePreview: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Example")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
            healthPreviewCards
        }
        .accessibilityElement(children: .combine)
    }

    private var healthPreviewCards: some View {
        HStack(spacing: Spacing.sm) {
            healthPreviewCard(
                icon: "waveform.path.ecg",
                label: "HRV",
                value: "62",
                unit: "ms",
                tint: AppColor.positive
            )
            healthPreviewCard(
                icon: "bed.double.fill",
                label: "Sleep",
                value: "7.4",
                unit: "h",
                tint: AppColor.metricHRV
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
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                Text(unit)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
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

    // MARK: - Ready

    private var readyStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ReadyHero(bounceTrigger: bounceTrigger, isActive: page == Page.ready)
                    .padding(.top, Spacing.xl)
                if !name.isEmpty {
                    OnboardingHeader(title: "You're set, \(name).")
                }
                // Re-identified when Ready becomes the live page so the
                // rows stagger in on arrival, not while pre-mounted
                // off-screen beside the Creator-code step.
                VStack(spacing: Spacing.sm) {
                    summaryRow(label: "Goal", value: primaryGoal.displayName)
                        .staggeredAppear(index: 0)
                    summaryRow(
                        label: "Experience",
                        value: Experience(rawValue: experienceLevel)?.title ?? experienceLevel.capitalized
                    )
                    .staggeredAppear(index: 1)
                    summaryRow(label: "Schedule", value: "\(daysPerWeek)× per week, \(timeOfDay.displayName.lowercased())")
                        .staggeredAppear(index: 2)
                    if let attribution = creatorAttribution {
                        // Attribution only — no percentage; the checkout
                        // applies no discount (see CreatorCodeService).
                        summaryRow(
                            label: "Referral",
                            value: "via \(attribution.creatorName)"
                        )
                        .staggeredAppear(index: 3)
                    }
                }
                .id(page == Page.ready)

                widgetTipCard
                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    /// Subtle "add the widget" tip on Ready. iOS doesn't expose a
    /// public deep link to the widget gallery, so this is a tip card,
    /// not a button — but the visual cue is enough to lift widget-
    /// install rate on comparable apps.
    private var widgetTipCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "square.grid.2x2.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pro tip")
                    .font(AppFont.caption2.weight(.bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .textCase(.uppercase)
                Text("Long-press your home screen to add the Atlas widget for daily progress at a glance.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius, tinted: true)
        .accessibilityElement(children: .combine)
        .padding(.top, Spacing.sm)
    }

    /// Label and value side by side while both fit on one line; at large
    /// Dynamic Type sizes the value drops under the label instead of
    /// truncating either.
    private func summaryRow(label: String, value: String) -> some View {
        let labelText = Text(label)
            .font(AppFont.footnote)
            .foregroundStyle(AppColor.textSecondary)
        let valueText = Text(value)
            .font(AppFont.callout.weight(.semibold))
            .foregroundStyle(AppColor.textPrimary)
        return ViewThatFits(in: .horizontal) {
            HStack {
                labelText
                    .lineLimit(1)
                    .frame(minWidth: 100, alignment: .leading)
                valueText
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                labelText
                valueText
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.smallCornerRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Creator code

    /// Users with a code enter it and we stamp the attribution onto
    /// the profile (credit only — no discount is applied at
    /// checkout). The step is skippable.
    private var creatorCodeStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "person.text.rectangle", bounceTrigger: bounceTrigger, isActive: page == Page.creatorCode)
                    .padding(.top, Spacing.xl)

                OnboardingHeader(
                    title: "Have a code?",
                    subtitle: "Enter a creator or referral code below."
                )

                if let attribution = creatorAttribution {
                    creatorSuccessCard(attribution)
                } else {
                    creatorCodeField
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

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
