import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Onboarding for Atlas — a health & fitness app. 18 steps covering
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
///      goals,goalDate,trainingPreferences,creatorAttribution,
///      emailSubscription}` — persisted via DataStore
struct OnboardingView: View {
    @Environment(DataStore.self) private var dataStore
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
    // "Building your plan…" loading screen progress (0…1). Drives the
    // ring fill on `buildingPlanStep` and gates the auto-advance.
    @State private var buildingProgress: Double = 0
    @State private var buildingStarted: Bool = false
    /// Holds the in-flight "auto-advance after the ring fills" task so
    /// a back-navigation off the building-plan page can cancel it
    /// (audit code-review #6 — unstructured task survived page exit and
    /// could double-advance on re-entry).
    @State private var buildingTask: Task<Void, Never>?
    /// Incremented every time the building-plan animation starts. The
    /// auto-advance task captures the value and re-checks it after its
    /// sleep — `cancel()` alone can lose a race against a fast
    /// back-then-forward navigation, letting a stale task advance.
    @State private var buildingGeneration: Int = 0
    // Email-capture step state. Validated against `looksLikeEmail` on
    // primary-action; opt-in is genuinely optional — leaving it blank
    // advances without persisting an EmailSubscription.
    @State private var emailInput: String = ""
    @State private var emailError: String?
    // Creator-attribution step state. Looked up against
    // CreatorCodeService.seeded on primary-action.
    @State private var creatorCodeInput: String = ""
    @State private var creatorAttribution: CreatorAttribution?
    @State private var creatorError: String?
    @State private var showingAffiliateApply: Bool = false
    // Projection chart "reveal" state. Drives a tasteful fade-in on
    // the chart instead of jump-cutting from the building screen.
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
        static let buildingPlan     = 14
        static let creatorCode      = 15
        static let email            = 16
        static let ready            = 17
        static let total            = 18
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
            case .antiAging:      return "Anti-aging"
            case .skinHair:       return "Skin & hair"
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
            case .beginner:     return "leaf.fill"
            case .intermediate: return "flame.fill"
            case .advanced:     return "bolt.fill"
            }
        }
    }

    /// Gates forward navigation out of the medical-disclaimer page
    /// until it is explicitly acknowledged. The footer "Continue"
    /// button sets `disclaimerAcknowledgedAt` *before* it advances, so
    /// button-driven advance passes; only an un-acknowledged swipe is
    /// blocked. Backward navigation is always allowed. Without this a
    /// user could swipe straight past the disclaimer — the
    /// acknowledgment is a hard gate for a regulated-substance app
    /// (Deep Audit II A1).
    private var gatedPage: Binding<Int> {
        Binding(
            get: { page },
            set: { newValue in
                if page == Page.disclaimer,
                   newValue > Page.disclaimer,
                   disclaimerAcknowledgedAt == 0 {
                    Haptics.warning()
                    return
                }
                page = newValue
            }
        )
    }

    var body: some View {
        ZStack {
            OnboardingBackground(step: page)

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
                    buildingPlanStep.tag(Page.buildingPlan)
                    creatorCodeStep.tag(Page.creatorCode)
                    emailStep.tag(Page.email)
                    readyStep.tag(Page.ready)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.springSmooth, value: page)
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
            // Re-hydrate goalDate + selected-goal state from a
            // previously-saved profile in case the user re-opened
            // onboarding (debug menu, reset-onboarding tester).
            // Otherwise the @State defaults (12 weeks from today,
            // .buildMuscle) win, which is also fine for a fresh install.
            if let saved = dataStore.profile.goalDate {
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
            updateBuildingPlanForPage(newPage)
            // Focus the name field only when the name page is actually
            // the current one. Driving this from the sub-view's
            // `.onAppear` summoned the keyboard early — TabView mounts
            // adjacent pages, so `.onAppear` fired on the prior page.
            //
            // Leaving any text-entry step must put the keyboard away —
            // otherwise the name keyboard rode along onto the goal grid
            // (and the email / creator-code keyboards onto their
            // neighbours), covering the lower half of the next card.
            if newPage == Page.name {
                nameFocused = true
            } else {
                nameFocused = false
                dismissKeyboard()
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
            // user isn't stuck on the Ready page tapping "Open Atlas"
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
        case Page.buildingPlan:   return "building_plan"
        case Page.creatorCode:    return "creator_code"
        case Page.email:          return "email"
        case Page.ready:          return "ready"
        default:                  return "unknown_\(index)"
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            if page > 0 {
                Button {
                    haptic()
                    withAnimation(AppAnimation.springSnappy) { page = max(0, page - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                        .background(Circle().fill(AppColor.surfaceSecondary.opacity(0.6)))
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
            progressIndicator
            Spacer()
            Color.clear.frame(width: 36, height: 36)
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
                        .animation(AppAnimation.springSmooth, value: page)
                }
                .frame(height: 4)
            }
            .frame(width: 160)

            Text("\(min(page + 1, totalPages)) / \(totalPages)")
                .font(AppFont.scaled(11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColor.textTertiary)
                .contentTransition(.numericText())
                .animation(AppAnimation.springSmooth, value: page)
        }
    }

    private var progressFraction: CGFloat {
        guard totalPages > 1 else { return 1 }
        let pos = CGFloat(min(page, totalPages - 1)) / CGFloat(totalPages - 1)
        return min(1, max(0, pos))
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            // Hide the primary button on the building-plan screen —
            // it auto-advances when the ring fills, and a tappable
            // CTA next to a progress ring reads as "click to bypass."
            if page != Page.buildingPlan {
                primaryButton
            }
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
             Page.creatorCode, Page.email:
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
                        .font(AppFont.scaled(16, weight: .semibold))
                }
            }
            .foregroundStyle(AppColor.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.sheetCornerRadius, style: .continuous)
                    .fill(primaryEnabled ? AppColor.textPrimary : AppColor.textTertiary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!primaryEnabled)
    }

    private var primaryTitle: String {
        switch page {
        case Page.welcome:      return "Let's go"
        case Page.disclaimer:   return "I understand"
        case Page.creatorCode:  return creatorAttribution == nil ? "Apply" : "Continue"
        case Page.email:        return emailInput.isEmpty ? "Skip for now" : "Subscribe"
        case Page.ready:        return "Open Atlas"
        default:                return "Continue"
        }
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
            if let targets = NutritionMath.dailyTargets(for: bodyMetrics) {
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
        case Page.email:
            if !persistEmailIfValid() { return }
        case Page.ready:
            // Present the trial paywall — flow continues through the
            // paywall and the theme picker before hasCompleted flips.
            // The theme picker's onContinue path resets `lastPage = 0`
            // so a future re-onboarding starts at page 0.
            showTrialOffer = true
            return
        default:
            break
        }
        advance()
    }

    /// Validates and persists the typed email. Empty input is a
    /// silent "skip" — the user moves on without any record. Bad
    /// format renders an inline error and blocks advance.
    private func persistEmailIfValid() -> Bool {
        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emailError = nil
            return true
        }
        guard trimmed.looksLikeEmail else {
            withAnimation(AppAnimation.fadeIn) { emailError = "That doesn't look like an email address." }
            Haptics.error()
            return false
        }
        emailError = nil
        dataStore.profile.emailSubscription = EmailSubscription(
            email: trimmed,
            capturedAt: Date()
        )
        // Flush sync — see goalDate comment.
        dataStore.flushPendingSave()
        OnboardingFunnelTracker.recordEvent("email_captured")
        return true
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
            withAnimation(AppAnimation.springBouncy) {
                creatorAttribution = match
                creatorError = nil
            }
            dataStore.profile.creatorAttribution = match
            // Flush sync — see goalDate comment.
            dataStore.flushPendingSave()
            OnboardingFunnelTracker.recordEvent("creator_code_applied")
            Haptics.success()
        } else {
            withAnimation(AppAnimation.fadeIn) { creatorError = "Code not found — double-check and try again." }
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
        withAnimation(AppAnimation.springSnappy) { page = min(totalPages - 1, page + 1) }
    }

    /// Resigns the first responder app-wide. Covers the text fields that
    /// live inside sub-views (email, creator code) where the parent has
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

    private func haptic() {
        Haptics.impact(.light)
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            HeroLogo(
                color: AppColor.accentPrimary,
                size: 148,
                bounceTrigger: bounceTrigger
            )
            VStack(spacing: Spacing.md) {
                Text("Welcome to\nAtlas.")
                    .font(AppFont.scaled(56, weight: .bold, design: .rounded, relativeTo: .largeTitle))
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

    // MARK: - Sign in with Apple

    /// Optional sign-in step. Skipping is genuinely fine — every feature
    /// works without an Apple ID — but a signed-in user gets cloud sync
    /// across devices, abandoned-onboarding retargeting hooks, and
    /// referral credit when the backend ships.
    private var signInStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            HeroIcon(symbol: "person.crop.circle.fill", bounceTrigger: bounceTrigger)
            VStack(spacing: Spacing.md) {
                Text("Save your\nprogress.")
                    .font(AppFont.scaled(38, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                Text("Optional. Back up across your devices.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            VStack(spacing: Spacing.md) {
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
                    .padding(.horizontal, Spacing.lg)
                }

                signInDisclosureRow(icon: "icloud.fill", text: "Cloud sync across iPhone, iPad, and Watch.")
                signInDisclosureRow(icon: "lock.shield.fill", text: "Atlas never sees your email — Apple relays it.")
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .alert(
            authService.lastError?.title ?? "",
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
            Text(authService.userDisplayName.map { "Signed in as \($0)" } ?? "Signed in with Apple")
                .font(AppFont.callout.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            Capsule()
                .fill(AppColor.accentPrimary.opacity(0.14))
        )
        .overlay(
            Capsule()
                .strokeBorder(AppColor.accentPrimary.opacity(0.45), lineWidth: 0.5)
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
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Attribution survey

    /// Marketing-channel survey. Anonymous, captured into the funnel
    /// snapshot only — useful for allocating ad spend, never stored on
    /// the user profile. Skippable.
    private var attributionStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Where did you hear\nabout Atlas?")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                Text("Optional.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
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
            Haptics.impact(.soft)
            withAnimation(AppAnimation.springSnappy) { attributionChannel = channel }
            OnboardingFunnelTracker.recordEvent("attribution_\(channel.rawValue)")
        } label: { chipLabel(channel: channel, isSelected: isSelected) }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isSelected ? "" : "Selects how you heard about Atlas")
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
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(isSelected ? AppColor.accentPrimary.opacity(0.12) : AppColor.surfaceSecondary.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(isSelected ? AppColor.accentPrimary : AppColor.glassBorder, lineWidth: isSelected ? 1 : 0.5)
        )
    }

    // MARK: - Name

    private var nameStep: some View {
        VStack(spacing: Spacing.xl) {
            HeroIcon(symbol: "person.fill", bounceTrigger: bounceTrigger)
                .padding(.top, Spacing.xl)
            VStack(spacing: Spacing.sm) {
                Text("What should we call you?")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
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
            VStack(spacing: Spacing.xs) {
                Text(goalHeadline)
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: goalHasBeenSelected)
                Text(goalSubheadline)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: goalHasBeenSelected)
            }
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
                    withAnimation(AppAnimation.springSmooth) {
                        proxy.scrollTo(Self.goalDateAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .animation(AppAnimation.springSmooth, value: goalHasBeenSelected)
    }

    private static let goalDateAnchorID = "onboarding.goal.dateSection"

    private var goalHeadline: String {
        goalHasBeenSelected ? "Hit it by when?" : "What are your goals?"
    }

    private var goalSubheadline: String {
        if !goalHasBeenSelected {
            return "Pick all that apply"
        }
        let count = selectedGoals.count
        return count <= 1
            ? "Set a target date to commit"
            : "\(count) goals · set a target date to commit"
    }

    /// True after the user has tapped a goal card at least once.
    /// Drives the date-section reveal so the picker only appears
    /// once there's an intention to anchor it to.
    @State private var goalHasBeenSelected: Bool = false

    private var goalDateSection: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                goalDateChip("8 wks",  weeks: 8)
                goalDateChip("12 wks", weeks: 12)
                goalDateChip("6 mo",   weeks: 26)
            }

            DatePicker(
                "Or a custom date",
                selection: $goalDate,
                in: Date().addingTimeInterval(60 * 60 * 24 * 14)...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .stroke(AppColor.glassBorder, lineWidth: 0.5)
            )

            Text(goalDateSummary)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .padding(.top, 2)
        }
    }

    private func goalDateChip(_ label: String, weeks: Int) -> some View {
        let candidate = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: Date()) ?? Date()
        let isSelected = Calendar.current.isDate(goalDate, inSameDayAs: candidate)
        return Button {
            Haptics.impact(.soft)
            withAnimation(AppAnimation.springSnappy) { goalDate = candidate }
        } label: {
            Text(label)
                .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? AppColor.background : AppColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(isSelected ? primaryGoal.tint : AppColor.surfaceSecondary.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .stroke(isSelected ? primaryGoal.tint : AppColor.glassBorder, lineWidth: isSelected ? 1 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Target date \(label.replacingOccurrences(of: "wks", with: " weeks").replacingOccurrences(of: "mo", with: " months"))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func goalCard(_ goal: PrimaryGoal) -> some View {
        let selected = selectedGoals.contains(goal)
        return Button {
            haptic()
            withAnimation(AppAnimation.springSmooth) { toggleGoal(goal) }
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
        .buttonStyle(.plain)
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

    /// Human-readable "8 weeks to commit" summary for the merged
    /// goal-and-date step. Used inside the date section underneath
    /// the picker.
    private var goalDateSummary: String {
        "That's \(goalWeeks) week\(goalWeeks == 1 ? "" : "s") to commit."
    }

    /// Weeks between today and the user's chosen goal date, clamped to
    /// at least one week. Used by the projection step's headline and
    /// the ProjectionChart's framing.
    private var goalWeeks: Int {
        max(1, Int(goalDate.timeIntervalSince(Date()) / (60 * 60 * 24 * 7)))
    }

    // MARK: - Experience

    private var experienceStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("How much experience?")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
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
            VStack(spacing: Spacing.sm) {
                Text("When do you train?")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
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

    // MARK: - Equipment

    private var equipmentStep: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("What gear do you have?")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
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
        .onAppear {
            // `.other` has no card in the grid — if a re-hydrated
            // profile carries it in the set, it can't be deselected
            // and skews the "keep at least one selected" count. Strip
            // it so the step only ever holds card-backed kinds.
            equipment.remove(.other)
        }
    }

    private func equipmentCard(_ kind: EquipmentKind) -> some View {
        let selected = equipment.contains(kind)
        return Button {
            haptic()
            if selected {
                // Always keep at least one option selected — an empty
                // set makes ExerciseLibrary filters return zero hits
                // and the program preview renders a blank list. The
                // last-deselect is silently ignored so the user
                // notices a non-response rather than getting trapped
                // in a broken-state next step.
                if equipment.count > 1 {
                    equipment.remove(kind)
                }
            } else {
                equipment.insert(kind)
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                // Fixed slot, not the glyph's own size. `figure.*` symbols
                // are much taller than `dumbbell.fill` or `wave.3.right`,
                // so letting each icon set its own height made every card
                // in the grid a different size — Barbell taller than
                // Dumbbell beside it, and so on down the two columns.
                Image(systemName: kind.symbolName)
                    .font(AppFont.scaled(24, weight: .semibold))
                    .foregroundStyle(selected ? AppColor.accentPrimary : AppColor.textSecondary)
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

    // MARK: - Try a set (interactive workout demo)

    private var demoSetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Try logging a set.")
                        .font(AppFont.scaled(32, weight: .bold, design: .rounded, relativeTo: .largeTitle))
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
                            .font(AppFont.scaled(20, weight: .semibold))
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
                    unit: bodyMetrics.unit,
                    onDelete: {}
                )
                .onChange(of: demoSet.completed) { _, completed in
                    if completed && !demoCelebrate {
                        withAnimation(.spring(response: 0.4)) { demoCelebrate = true }
                        if !UIAccessibility.isReduceMotionEnabled {
                            Haptics.success()
                        }
                    }
                }
                Text(demoCelebrate
                     ? "Nice. That's it — your workouts are this fast."
                     : "Tap the circle to log this set.")
                    .font(AppFont.footnote)
                    .foregroundStyle(demoCelebrate ? AppColor.positive : AppColor.textTertiary)
                    .animation(AppAnimation.fadeIn, value: demoCelebrate)
            }
        }
    }

    private var successBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.positive)
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

    // MARK: - Program name (used only on the Ready summary now;
    // the dedicated "Your starter plan" step was removed in the
    // polish pass as redundant with the projection reveal).

    private var recommendedProgramName: String {
        // Switch on the goal first, then refine by days inside each
        // arm where the choice depends on volume. Avoids the
        // partial-range-inside-tuple-pattern Swift 6 parser ambiguity
        // (the older `case (.buildMuscle, 5...)` form looked like it
        // worked but the audit flagged it as unreliable across
        // compiler versions). Every PrimaryGoal case must be covered —
        // the v3 expansion added five wellness-track goals that need
        // explicit program names so the Program Preview screen
        // doesn't crash on a non-exhaustive switch.
        switch primaryGoal {
        case .getStronger:    return "5/3/1 Strength"
        case .buildMuscle:    return daysPerWeek >= 5 ? "Push Pull Legs" : "Upper / Lower"
        case .loseFat:        return "Full Body Hypertrophy"
        case .athletic:       return "Athletic Conditioning"
        case .recomp:         return "Hybrid Recomp"
        case .stayConsistent: return "Consistency Builder"
        case .betterSleep:    return "Recovery & Sleep Hygiene"
        case .recovery:       return "Active Recovery Plan"
        case .antiAging:      return "Longevity Protocol"
        case .skinHair:       return "Skin & Hair Protocol"
        case .energy:         return "Energy & Vitality Plan"
        }
    }

    // MARK: - Projection (personalised plan reveal)

    /// Cal-AI-style projection moment. Numbers are illustrative — the
    /// curve shape and the headline copy adapt to the user's primary
    /// goal so it reads as "we built this for you" instead of a
    /// generic stock chart.
    private var projectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(projectionHeadline)
                        .font(AppFont.scaled(32, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(projectionSubtitle)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Spacing.xl)

                ProjectionChart(
                    goal: primaryGoal,
                    daysPerWeek: daysPerWeek,
                    startWeightKg: bodyMetrics.weightKg,
                    weeks: goalWeeks,
                    targetDate: goalDate,
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
                    if let targets = NutritionMath.dailyTargets(for: bodyMetrics) {
                        // Daily nutrition targets folded in here so the
                        // user sees the derived plan inline rather than
                        // on a separate "Nutrition" step. Hidden when
                        // body metrics aren't filled in enough to derive
                        // a real Mifflin-St Jeor estimate.
                        projectionStatRow(
                            label: "Daily targets",
                            value: "\(targets.calories) kcal · \(targets.proteinG)P · \(targets.carbsG)C · \(targets.fatG)F",
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
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 120)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .onAppear {
            withAnimation(AppAnimation.springSmooth.delay(0.2)) {
                projectionRevealed = true
            }
        }
        .onDisappear {
            projectionRevealed = false
        }
    }

    private var projectionHeadline: String {
        let weeks = goalWeeks
        switch primaryGoal {
        case .buildMuscle:    return "+\(projectedMuscleGain) in \(weeks) weeks"
        case .loseFat:        return "−\(projectedFatLoss) in \(weeks) weeks"
        case .getStronger:    return "Stronger every week\nfor \(weeks) weeks"
        case .stayConsistent: return "\(daysPerWeek * weeks) sessions\nin \(weeks) weeks"
        case .athletic:       return "Peak conditioning\nin \(weeks) weeks"
        case .recomp:         return "Leaner & stronger\nin \(weeks) weeks"
        case .betterSleep:    return "Better sleep scores\nin \(weeks) weeks"
        case .recovery:       return "Faster recovery\nin \(weeks) weeks"
        case .antiAging:      return "Better biomarkers\nin \(weeks) weeks"
        case .skinHair:       return "Visible skin & hair\ngains in \(weeks) weeks"
        case .energy:         return "Steady all-day energy\nin \(weeks) weeks"
        }
    }

    private var projectionSubtitle: String {
        switch primaryGoal {
        case .buildMuscle, .recomp:
            return "Based on \(daysPerWeek) sessions per week and your starting weight."
        case .loseFat:
            return "From a moderate deficit at \(daysPerWeek) sessions per week."
        case .getStronger, .athletic:
            return "Progressive overload at \(daysPerWeek) sessions per week."
        case .stayConsistent:
            return "Consistency curve from \(daysPerWeek) sessions per week."
        case .betterSleep, .recovery, .antiAging, .skinHair, .energy:
            return "Trend curve from your protocol and recovery signals."
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
        case .betterSleep: return "+45 min average sleep"
        case .recovery:    return "+10 HRV points (avg)"
        case .antiAging:   return "Biomarker improvement"
        case .skinHair:    return "Tracked weekly with photos"
        case .energy:      return "Steadier energy curve"
        }
    }

    // The realistic-range clamps are expressed in kilograms because the
    // underlying model is; the label converts afterwards so an imperial
    // user reads "9 lb", not "4 kg".
    private var projectedMuscleGain: String {
        bodyMetrics.unit.weightLabel(Double(min(6, max(2, Int(estimatedMuscleGainKg)))))
    }

    private var projectedFatLoss: String {
        bodyMetrics.unit.weightLabel(Double(min(10, max(3, Int(estimatedFatLossKg)))))
    }

    private var estimatedMuscleGainKg: Double {
        Double(daysPerWeek) * 0.6 + 1.5
    }

    private var estimatedFatLossKg: Double {
        let bodyW = bodyMetrics.weightKg ?? 75
        return min(10, max(3, bodyW * 0.05))
    }

    private func projectionStatRow(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(AppFont.callout.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
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

    // MARK: - Medical disclaimer

    private var disclaimerStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "stethoscope", bounceTrigger: bounceTrigger)
                    .padding(.top, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    Text("A quick safety note.")
                        .font(AppFont.scaled(30, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Atlas is an educational and tracking tool — not a replacement for a clinician.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    disclaimerBullet(
                        icon: "checkmark.shield.fill",
                        text: "Atlas does **not** prescribe, recommend, or calculate doses for any supplement, medication, or training protocol."
                    )
                    disclaimerBullet(
                        icon: "person.crop.circle.badge.questionmark.fill",
                        text: "Always consult a qualified clinician before starting, changing, or stopping anything you track here."
                    )
                    disclaimerBullet(
                        icon: "lock.fill",
                        text: "Your data stays on-device by default and is lockable with Face ID."
                    )
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .stroke(AppColor.glassBorder, lineWidth: 0.5)
                )

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
                HeroIcon(symbol: "bell.badge.fill", bounceTrigger: bounceTrigger)
                    .padding(.top, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    Text("Stay on track.")
                        .font(AppFont.scaled(32, weight: .bold, design: .rounded, relativeTo: .largeTitle))
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
                    isOn: notificationsAuthorized,
                    action: requestNotifications
                )
                .padding(.horizontal, Spacing.lg)

                Spacer(minLength: 100)
            }
        }
        .task {
            let status = await NotificationService.shared.checkAuthorization()
            notificationsAuthorized = (status == .authorized || status == .provisional)
        }
    }

    // MARK: - Health (with value preview)

    private var healthStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(
                    symbol: "heart.fill",
                    color: AppColor.metricHeartRate,
                    accent: AppColor.negative,
                    bounceTrigger: bounceTrigger
                )
                .padding(.top, Spacing.xl)
                VStack(spacing: Spacing.sm) {
                    Text("Connect Apple Health.")
                        .font(AppFont.scaled(32, weight: .bold, design: .rounded, relativeTo: .largeTitle))
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

                Text("Reads only by default. Optional nutrition-write turns on later from Profile. Lockable with Face ID.")
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

    // MARK: - Building your plan…

    private var buildingPlanStep: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            buildingRing
            VStack(spacing: Spacing.sm) {
                Text("Building your plan…")
                    .font(AppFont.scaled(28, weight: .bold, design: .rounded, relativeTo: .largeTitle))
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
    }

    /// Drives the building-plan reveal. Called from the outer body's
    /// .onChange(of: page) so the animation fires exactly when the
    /// user lands on the page — not on every other page transition the
    /// way an .onChange registered inside the sub-view would (audit
    /// code-review #4 / integration L7).
    private func updateBuildingPlanForPage(_ newPage: Int) {
        if newPage == Page.buildingPlan {
            startBuildingPlanAnimation()
        } else if buildingStarted {
            // Reset so a back-nav into this page re-runs the
            // animation instead of seeing progress already at 1.
            buildingProgress = 0
            buildingStarted = false
            buildingTask?.cancel()
            buildingTask = nil
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
                .font(AppFont.scaled(28, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                .monospacedDigit()
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
        withAnimation(.easeInOut(duration: 1.2)) {
            buildingProgress = 1
        }
        // Auto-advance once the ring fills. Matches the animation
        // duration plus a 200ms beat so the user reads "Done." Held on
        // a @State property so a back-navigation off the page can
        // cancel the in-flight sleep — without cancellation the user
        // could be advanced from an unrelated step seconds after
        // they swiped back (audit code-review #6).
        buildingTask?.cancel()
        buildingGeneration += 1
        let generation = buildingGeneration
        buildingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            // Re-check the generation as well as cancellation/page: a
            // fast back-then-forward nav can leave a stale task that
            // cancel() didn't catch in time.
            guard !Task.isCancelled,
                  generation == buildingGeneration,
                  page == Page.buildingPlan else { return }
            Haptics.success()
            advance()
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
                } else if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.positive)
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
            OnboardingFunnelTracker.recordEvent(granted ? "notifications_granted" : "notifications_denied")
        }
    }

    // MARK: - Ready

    private var readyStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ReadyHero(bounceTrigger: bounceTrigger)
                    .padding(.top, Spacing.xl)
                if !name.isEmpty {
                    Text("You're set, \(name).")
                        .font(AppFont.scaled(28, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: Spacing.sm) {
                    summaryRow(label: "Goal", value: primaryGoal.displayName)
                    summaryRow(label: "Experience", value: experienceLevel.capitalized)
                    summaryRow(label: "Schedule", value: "\(daysPerWeek)× per week, \(timeOfDay.displayName.lowercased())")
                    summaryRow(label: "Program", value: recommendedProgramName)
                    if let attribution = creatorAttribution {
                        // Attribution only — no percentage; the checkout
                        // applies no discount (see CreatorCodeService).
                        summaryRow(
                            label: "Referral",
                            value: "via \(attribution.creatorName)"
                        )
                    }
                }

                widgetTipCard
                .padding(.horizontal, Spacing.lg)
                Spacer(minLength: 100)
            }
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
                    .font(AppFont.caption.weight(.bold))
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
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .stroke(AppColor.accentPrimary.opacity(0.25), lineWidth: 0.5)
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
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

    // MARK: - Creator code / affiliate apply

    /// Dual-purpose step. For users with a code: enter it and we
    /// stamp the attribution + discount onto the profile. For users
    /// without a code: tap "Apply to be an affiliate" to surface a
    /// short form (handle, audience, channel link). Either path
    /// advances the onboarding; the step is skippable.
    private var creatorCodeStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "person.text.rectangle", bounceTrigger: bounceTrigger)
                    .padding(.top, Spacing.xl)

                VStack(spacing: Spacing.sm) {
                    Text("Got a creator code?")
                        .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .largeTitle))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Apply a friend's code or join the Atlas creator program.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                if let attribution = creatorAttribution {
                    creatorSuccessCard(attribution)
                } else {
                    creatorCodeField
                }

                affiliateApplyButton

                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .sheet(isPresented: $showingAffiliateApply) {
            AffiliateApplySheet(
                userName: dataStore.profile.name,
                userEmail: dataStore.profile.emailSubscription?.email,
                onSubmit: { application in
                    OnboardingFunnelTracker.recordEvent("creator_program_application_submitted")
                    // Persist the application onto the profile so a
                    // future Supabase drain can replay it 1:1. Backend
                    // wiring is a follow-up; local-only today.
                    dataStore.profile.affiliateApplication = application
                    dataStore.flushPendingSave()
                }
            )
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

            if let error = creatorError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(AppFont.scaled(11, weight: .semibold))
                    Text(error)
                        .font(AppFont.caption)
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

    /// Secondary "Join the creator program" link below the code
    /// field. Toned-down chrome (no sparkle, neutral text colour) so
    /// it reads as the secondary it is — the primary path on this
    /// step is still entering a code and tapping Continue (audit
    /// LOW: affiliate CTA was competing visually with the primary).
    private var affiliateApplyButton: some View {
        Button {
            Haptics.impact(.soft)
            OnboardingFunnelTracker.recordEvent("creator_program_apply_opened")
            showingAffiliateApply = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Join the creator program")
                    .font(AppFont.footnote.weight(.semibold))
                Image(systemName: "arrow.up.right")
                    .font(AppFont.scaled(11, weight: .bold))
            }
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Email capture

    private var emailStep: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HeroIcon(symbol: "envelope.fill", bounceTrigger: bounceTrigger)
                    .padding(.top, Spacing.xl)
                EmailCapturePage(input: $emailInput, error: emailError)
                Spacer(minLength: 100)
            }
            .padding(.horizontal, Spacing.lg)
        }
    }
}

/// Compact social-proof pill — five gold stars, a 4.9 score, and a
/// user count. Sits under the welcome headline as the first trust
/// anchor before any data is asked from the user.
private struct SocialProofPill: View {
    private let gold = AppColor.achievement

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(gold)
                }
            }
            Text("4.9")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text("·")
                .foregroundStyle(AppColor.textTertiary)
            Text("12k+ athletes")
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
        // Five separate star glyphs plus a bare "·" is eight meaningless
        // VoiceOver stops; the rating is one fact, so it's spoken as one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated 4.9 out of 5 by over 12,000 athletes")
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
    let revealed: Bool

    @State private var drawAmount: CGFloat = 0

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

                    if drawAmount > 0.85 {
                        Circle()
                            .strokeBorder(goal.tint, lineWidth: 3)
                            .background(Circle().fill(AppColor.background))
                            .frame(width: 14, height: 14)
                            .position(endPoint(in: size))
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 180)

            HStack {
                Text("Today")
                Spacer()
                Text(targetDate.formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AppColor.textSecondary)
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
        .onChange(of: revealed) { _, newValue in
            if newValue {
                withAnimation(.easeOut(duration: 1.6)) { drawAmount = 1 }
            } else {
                drawAmount = 0
            }
        }
        .onAppear {
            if revealed {
                withAnimation(.easeOut(duration: 1.6)) { drawAmount = 1 }
            }
        }
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
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack {
                ScrollView {
                    ThemeChoicePage(theme: themeManager)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.top, Spacing.xxl)
                }
                Button(action: {
                    Haptics.impact(.medium)
                    onContinue()
                }) {
                    Text("Enter Atlas")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.sheetCornerRadius, style: .continuous)
                                .fill(AppColor.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xl)
            }
        }
        .preferredColorScheme(themeManager.displayMode.preferredScheme)
    }
}
