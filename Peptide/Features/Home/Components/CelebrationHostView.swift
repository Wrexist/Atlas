import StoreKit
import SwiftUI

/// The single, app-wide presenter for celebrations. Mounted once over the
/// root `TabView` (`PeptideApp.mainContent`) so a habit completion,
/// level-up, or achievement unlock celebrates on whichever tab the user
/// is on.
///
/// Two independent sources feed it:
///   • `CelebrationCenter` — the serialized queue of habit-complete and
///     level-up moments. Drained one at a time.
///   • `AchievementService.latestUnlock` — achievement unlocks. The host
///     shows the confetti and the explanatory toast together, so an unlock
///     earned on Train or Meals is explained where it happened.
///
/// Reduce Motion suppresses confetti (the level-up card still shows, and
/// fades rather than pops). Confetti is decorative and never blocks
/// touches; only the level-up dim is interactive (tap to dismiss).
struct CelebrationHostView: View {
    @State private var center = CelebrationCenter.shared
    @State private var achievements = AchievementService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    @State private var burst: ConfettiBurst?
    @State private var levelUp: LevelUpPresentation?
    @State private var toastAchievement: Achievement?
    @State private var showAchievementToast = false

    /// Milestones big enough to be a good moment for the review prompt —
    /// asked only after the user has actually seen the toast.
    private static let reviewWorthyAchievements: Set<String> = [
        "streak_7", "streak_14", "streak_30", "streak_90",
        "fifty_doses", "hundred_doses", "five_hundred_doses",
        "month_logged"
    ]

    private struct ConfettiBurst: Identifiable {
        let id = UUID()
        let colors: [Color]
        let intensity: Int
    }

    private struct LevelUpPresentation: Identifiable {
        let id: UUID
        let level: Int
        let tierName: String
        let tierSymbol: String
        let tint: Color
    }

    var body: some View {
        ZStack {
            if let levelUp {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) { self.levelUp = nil } }

                CelebrationOverlayView(
                    level: levelUp.level,
                    tierName: levelUp.tierName,
                    tierSymbol: levelUp.tierSymbol,
                    tint: levelUp.tint
                )
                .id(levelUp.id)
            }

            if let burst, !reduceMotion {
                ConfettiView(colors: burst.colors, intensity: burst.intensity)
                    .id(burst.id)
            }
        }
        // Only the level-up dim is interactive; confetti must never steal
        // touches from the app behind it.
        .allowsHitTesting(levelUp != nil)
        .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: levelUp?.id)
        // Outside the hit-testing gate so the toast's Dismiss stays tappable.
        .overlay {
            if center.current == nil, let toastAchievement {
                AchievementToastView(achievement: toastAchievement, isShowing: $showAchievementToast)
            }
        }
        .task(id: center.current?.id) { await present(center.current) }
        .task(id: achievements.latestUnlock?.id) { presentAchievement() }
        .onChange(of: showAchievementToast) { _, isShowing in
            guard !isShowing else { return }
            if let shown = toastAchievement, Self.reviewWorthyAchievements.contains(shown.id) {
                ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
            }
            // Drain one queued unlock when its toast finishes, surfacing
            // the next one if a single save crossed several milestones.
            achievements.acknowledgeLatestUnlock()
        }
    }

    // MARK: - Presentation

    private func present(_ event: CelebrationEvent?) async {
        guard let event else { return }
        switch event.kind {
        case let .habitComplete(tintHex, allHabitsDone):
            // No haptic here — `DataStore.toggleHabitEntry` already fires
            // the success notification at the tap site.
            triggerBurst(
                colors: [HabitTintCatalog.color(for: tintHex), AppColor.accentLight],
                intensity: allHabitsDone ? 90 : 36
            )
            // Brief pace so a flurry of completions doesn't stack overlays;
            // the burst manages its own (longer) lifetime.
            do {
                try await Task.sleep(for: .seconds(allHabitsDone ? 1.0 : 0.45))
            } catch { return }
            center.acknowledgeCurrent()

        case let .levelUp(level, tier):
            let tint = tier.tint
            Haptics.success()
            triggerBurst(
                colors: [tint, AppColor.accentLight, AppColor.accentPrimary],
                intensity: 110
            )
            withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) {
                levelUp = LevelUpPresentation(
                    id: event.id,
                    level: level,
                    tierName: tier.name,
                    tierSymbol: tier.symbol,
                    tint: tint
                )
            }
            do {
                try await Task.sleep(for: .seconds(2.6))
            } catch { return }
            withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) { levelUp = nil }
            center.acknowledgeCurrent()
        }
    }

    private func presentAchievement() {
        guard let unlock = achievements.latestUnlock else { return }
        toastAchievement = unlock
        AppAnimation.with(AppAnimation.springBouncy) { showAchievementToast = true }
        // The toast carries its own artwork. Avoid replacing an in-flight
        // habit/level-up burst with a second celebration for one tap.
        guard center.current == nil, levelUp == nil, burst == nil else { return }
        triggerBurst(colors: [AppColor.achievement, AppColor.accentLight], intensity: 60)
    }

    /// Starts a confetti burst, auto-clearing it after its visual lifetime.
    /// Suppressed entirely under Reduce Motion. The id check on clear means a
    /// newer burst started in the meantime is never cut short.
    private func triggerBurst(colors: [Color], intensity: Int) {
        guard !reduceMotion else { return }
        let newBurst = ConfettiBurst(colors: colors, intensity: intensity)
        burst = newBurst
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            if burst?.id == newBurst.id { burst = nil }
        }
    }
}
