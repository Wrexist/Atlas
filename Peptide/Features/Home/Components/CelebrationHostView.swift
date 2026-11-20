import StoreKit
import SwiftUI
import UIKit

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
///     earned on Train or Meals is explained where it happened. Unlocks
///     queued together share one summary toast.
///
/// Reduce Motion suppresses confetti (the level-up card still shows, and
/// fades rather than pops). Confetti is decorative and never blocks
/// touches; only the level-up dim is interactive (tap to dismiss).
/// Nothing presents while a sheet or cover hides the host.
struct CelebrationHostView: View {
    @State private var center = CelebrationCenter.shared
    @State private var achievements = AchievementService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview

    @State private var burst: ConfettiBurst?
    @State private var levelUp: LevelUpPresentation?
    /// The unlocks the current toast stands for, head first.
    @State private var toastUnlocks: [Achievement] = []
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
                    .onTapGesture { dismissLevelUp() }
                    .accessibilityAction(.escape) { dismissLevelUp() }

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
        // Full-screen even when empty: the toast overlay takes this size,
        // and a collapsed ZStack (no confetti, no level-up) squeezed the
        // toast to its minimum width in the middle of the screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only the level-up dim is interactive; confetti must never steal
        // touches from the app behind it.
        .allowsHitTesting(levelUp != nil)
        .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: levelUp?.id)
        // Outside the hit-testing gate so the toast's Dismiss stays tappable.
        .overlay {
            if center.current == nil, let first = toastUnlocks.first {
                AchievementToastView(achievement: first, count: toastUnlocks.count, isShowing: $showAchievementToast)
            }
        }
        .task(id: center.current?.id) { await present(center.current) }
        .task(id: achievements.latestUnlock?.id) {
            do { try await waitUntilUncovered() } catch { return }
            presentAchievement()
        }
        .onChange(of: showAchievementToast) { _, isShowing in
            guard !isShowing else { return }
            if toastUnlocks.contains(where: { Self.reviewWorthyAchievements.contains($0.id) }) {
                ReviewPromptService.shared.requestReviewIfEligible(using: requestReview)
            }
            // Drain what this toast showed once it has slid away, so the
            // next one never overlaps the outgoing card.
            let shownCount = toastUnlocks.count
            Task { @MainActor in
                try? await Task.sleep(for: AppAnimation.toastHandoffDelay)
                achievements.acknowledgeUnlocks(shownCount)
            }
        }
    }

    // MARK: - Presentation

    private func present(_ event: CelebrationEvent?) async {
        guard let event else { return }
        do { try await waitUntilUncovered() } catch { return }
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

    /// Tapping (or VoiceOver's escape) ends the level-up card early and
    /// drains it from the queue, so a waiting toast or celebration shows
    /// at once instead of after the card's full 2.6 s.
    private func dismissLevelUp() {
        withAnimation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion)) { levelUp = nil }
        center.acknowledgeCurrent()
    }

    /// Sheets and full-screen covers present above this overlay, so a
    /// celebration started under one would play unseen and its toast
    /// would time out and be acknowledged. Waits, without acknowledging,
    /// until nothing is presented over the root.
    private func waitUntilUncovered() async throws {
        while Self.isCoveredByModal {
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    @MainActor private static var isCoveredByModal: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }

    private func presentAchievement() {
        let unlocks = achievements.pendingUnlocks
        guard !unlocks.isEmpty else { return }
        // Screenshot captures stay clear of celebration chrome.
        guard !ScreenshotMode.shared.isEnabled else {
            achievements.acknowledgeUnlocks(unlocks.count)
            return
        }
        toastUnlocks = unlocks
        AppAnimation.with(AppAnimation.toast) { showAchievementToast = true }
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
