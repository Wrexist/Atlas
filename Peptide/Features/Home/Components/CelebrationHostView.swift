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
///     layers confetti; the explanatory toast stays owned by `HomeView`,
///     so there's no double toast.
///
/// Reduce Motion suppresses confetti (the level-up card still shows, and
/// fades rather than pops). Confetti is decorative and never blocks
/// touches; only the level-up dim is interactive (tap to dismiss).
struct CelebrationHostView: View {
    @State private var center = CelebrationCenter.shared
    @State private var achievements = AchievementService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var burst: ConfettiBurst?
    @State private var levelUp: LevelUpPresentation?

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
                    .onTapGesture { withAnimation(AppAnimation.springSmooth) { self.levelUp = nil } }

                CelebrationOverlayView(
                    level: levelUp.level,
                    tierName: levelUp.tierName,
                    tierSymbol: levelUp.tierSymbol,
                    tint: levelUp.tint
                )
                .id(levelUp.id)
            }

            if let burst {
                ConfettiView(colors: burst.colors, intensity: burst.intensity)
                    .id(burst.id)
            }
        }
        // Only the level-up dim is interactive; confetti must never steal
        // touches from the app behind it.
        .allowsHitTesting(levelUp != nil)
        .animation(AppAnimation.springSmooth, value: levelUp?.id)
        .task(id: center.current?.id) { await present(center.current) }
        .task(id: achievements.latestUnlock?.id) { presentAchievementConfetti() }
    }

    // MARK: - Presentation

    private func present(_ event: CelebrationEvent?) async {
        guard let event else { return }
        switch event.kind {
        case let .habitComplete(tintHex, allHabitsDone):
            // No haptic here — `DataStore.toggleHabitEntry` already fires
            // the success notification at the tap site.
            triggerBurst(
                colors: [Color(hex: UInt(tintHex)), AppColor.accentLight],
                intensity: allHabitsDone ? 90 : 36
            )
            // Brief pace so a flurry of completions doesn't stack overlays;
            // the burst manages its own (longer) lifetime.
            try? await Task.sleep(for: .seconds(allHabitsDone ? 1.0 : 0.45))
            center.acknowledgeCurrent()

        case let .levelUp(level, tierName, tierSymbol, tintHex):
            let tint = Color(hex: UInt(tintHex))
            Haptics.success()
            triggerBurst(
                colors: [tint, AppColor.accentLight, AppColor.accentPrimary],
                intensity: 110
            )
            withAnimation(AppAnimation.springSmooth) {
                levelUp = LevelUpPresentation(
                    id: event.id,
                    level: level,
                    tierName: tierName,
                    tierSymbol: tierSymbol,
                    tint: tint
                )
            }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(AppAnimation.springSmooth) { levelUp = nil }
            center.acknowledgeCurrent()
        }
    }

    private func presentAchievementConfetti() {
        guard achievements.latestUnlock != nil else { return }
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
