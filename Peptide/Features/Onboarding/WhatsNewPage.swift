import Foundation
import SwiftUI

/// One page of the "What's New" tour. Pure data — the view layer
/// renders it deterministically so a future tour change is a
/// content edit, not a layout rewrite.
///
/// Each page carries its own gradient (the hero glyph background)
/// + accent (text + bullet tints) so the tour visually walks the
/// user through the warm-to-cool palette the rest of the app
/// uses. Three to five bullets per page is the sweet spot — fewer
/// and the page feels thin, more and the body text wraps off-
/// screen on the smaller iPhones.
///
/// `@unchecked Sendable` because `LocalizedStringKey` (used by
/// `eyebrow`, `title`, `body`, and `bullets`) isn't marked
/// Sendable by SwiftUI — Apple's annotation is missing. In
/// practice the type is an immutable value wrapping a string +
/// interpolation segments, safe to share across threads. The
/// struct's other fields (String, [Color], Color) are already
/// Sendable.
struct WhatsNewPage: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    /// Eyebrow above the title. Short — "FOOD", "BIOMETRICS",
    /// "SHORTCUTS". Reads as a category tag, not a sentence.
    let eyebrow: LocalizedStringKey
    /// Headline. One short clause; the page's primary text
    /// hierarchy weight.
    let title: LocalizedStringKey
    /// Body copy under the title. Two sentences max — anything
    /// longer should split into bullets.
    let body: LocalizedStringKey
    /// SF Symbol for the hero glyph. Pick weighted variants
    /// (`.fill`, `.circle.fill`) so the icon reads at the big
    /// 64-pt size the hero card uses.
    let icon: String
    /// Two-stop gradient for the hero card background. Drawn
    /// top-leading → bottom-trailing.
    let gradient: [Color]
    /// Accent tint for the bullet check marks + the page
    /// indicator dot. Usually picks up the gradient's first
    /// colour at full opacity.
    let accent: Color
    /// Three-to-five short bullet rows. Each renders as a
    /// checkmark + one-line description.
    let bullets: [LocalizedStringKey]
}

extension WhatsNewPage {

    /// The tour for this release. The automatic launch tour and the manual
    /// replay in Profile → About both read this, so they can't drift apart.
    static var current: [WhatsNewPage] { v30Training }

    /// Tour content for the current shell. Walks returning users through
    /// the five tabs (Today / Train / Meals / Biology / Habits), the muscle
    /// map, meal photo scan, Biological Age, Habits, and the Atlas Score.
    /// Mounted automatically on first launch after
    /// `WhatsNewService.currentTourVersion` bumps.
    static let v30Training: [WhatsNewPage] = [
        WhatsNewPage(
            id: "v3_welcome",
            eyebrow: "What's new",
            title: "Atlas is built around training",
            body: "Five tabs now cover your whole day: what to do today, how you train, what you eat, how you recover, and the habits that hold it together.",
            icon: "square.grid.2x2.fill",
            gradient: [
                Color(light: 0x5F57A0, dark: 0x8C80EB),
                Color(light: 0xA5575F, dark: 0xF2808C),
            ],
            accent: Color(light: 0x5F57A0, dark: 0x8C80EB),
            bullets: [
                "Today: your day and Atlas Score at a glance",
                "Train, Meals, and Biology each get a tab",
                "Habits moves into its own tab",
            ]
        ),
        WhatsNewPage(
            id: "v3_train",
            eyebrow: "Train",
            title: "Your weekly muscle map",
            body: "Every workout you log lights up the body. The Overview tab shows which muscles you trained this week and surfaces your top three regions with set counts.",
            icon: "figure.strengthtraining.traditional",
            gradient: [
                Color(light: 0xA04E6C, dark: 0xEB739E),
                Color(light: 0x5F5793, dark: 0x8C80D9),
            ],
            accent: Color(light: 0xA04E6C, dark: 0xEB739E),
            bullets: [
                "Two-tap set logging — your previous values fill in automatically",
                "PR detection celebrates new e1RM / volume bests",
                "Exercise detail shows primary + secondary muscles",
            ]
        ),
        WhatsNewPage(
            id: "v3_meals",
            eyebrow: "Meals",
            title: "Snap a photo, log the meal",
            body: "Take a photo of your plate or pick one from your library. Atlas lists what it sees so you can adjust portions before anything is logged.",
            icon: "camera.fill",
            gradient: [
                Color(light: 0xAD6C34, dark: 0xFF9E4C),
                Color(light: 0xA55734, dark: 0xF2804C),
            ],
            accent: Color(light: 0xAD6C34, dark: 0xFF9E4C),
            bullets: [
                "Review each item and drop anything it got wrong",
                "Barcode scan for packaged food",
                "Macro rings stay front and center",
            ]
        ),
        WhatsNewPage(
            id: "v31_biology",
            eyebrow: "Biology",
            title: "Meet your Biological Age",
            body: "Atlas estimates a Biological Age from your cardio fitness, HRV, resting heart rate, sleep, steps, and body composition. It's a direction to watch, not a medical test.",
            icon: "waveform.path.ecg.rectangle",
            gradient: [
                Color(light: 0x4E9387, dark: 0x73D9C7),
                Color(light: 0x455FA0, dark: 0x668CEB),
            ],
            accent: Color(light: 0x4E9387, dark: 0x73D9C7),
            bullets: [
                "Biological Age dial with the signals behind it (Pro)",
                "Pick the biomarkers you care about",
                "Latest lab card with normal-range banding",
            ]
        ),
        WhatsNewPage(
            id: "v3_habits",
            eyebrow: "Habits",
            title: "Habits get their own tab",
            body: "Check off today's habits in one place. Each one keeps its streak, your best run, and a heatmap of every day you showed up.",
            icon: "star.fill",
            gradient: [
                Color(light: 0x4580A0, dark: 0x66BDEB),
                Color(light: 0x5357A0, dark: 0x7A80EB),
            ],
            accent: Color(light: 0x4580A0, dark: 0x66BDEB),
            bullets: [
                "Streak, best, and total for every habit",
                "A heads-up when today's streak is at risk",
                "Swipe a row to edit or delete it",
            ]
        ),
        WhatsNewPage(
            id: "v3_atlas_score",
            eyebrow: "Atlas Score",
            title: "A score you earn",
            body: "Your Atlas Score grows only from what you actually log. Complete your habits and log your meals to bank points and level up.",
            icon: "bolt.fill",
            gradient: [
                Color(light: 0x5357A0, dark: 0x7A80EB),
                Color(light: 0x3E875F, dark: 0x5CC78C),
            ],
            accent: Color(light: 0x3E875F, dark: 0x5CC78C),
            bullets: [
                "Levels come fast early and slow down later",
                "Climb from Bronze to Diamond",
                "Tap the card on Today to see your progress",
            ]
        ),
    ]
}
