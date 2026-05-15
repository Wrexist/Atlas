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
struct WhatsNewPage: Identifiable, Equatable {
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

    /// Tour content for the v2.0 release — the food library +
    /// labs + correlation + Watch + Siri stack. Edits to this
    /// list show up next time the tour fires; bump
    /// `WhatsNewService.currentTourVersion` so users who already
    /// saw the old tour see the new one.
    static let v2: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            eyebrow: "What's new",
            title: "PeptideX just got a lot bigger",
            body: "We've shipped the most-requested premium features in one update. Here's a 30-second tour.",
            icon: "sparkles",
            gradient: [
                Color(red: 0.55, green: 0.50, blue: 0.92),
                Color(red: 0.95, green: 0.50, blue: 0.55),
            ],
            accent: Color(red: 0.55, green: 0.50, blue: 0.92),
            bullets: [
                "Track nutrition, labs, and biomarkers",
                "Voice-log doses and meals with Siri",
                "Pattern-finding insights from your data",
            ]
        ),
        WhatsNewPage(
            id: "food",
            eyebrow: "Food",
            title: "A Lifesum-class food library",
            body: "Search Open Food Facts, save your own foods, build recipes — log a multi-ingredient meal in one tap.",
            icon: "fork.knife.circle.fill",
            gradient: [
                Color(red: 1.00, green: 0.62, blue: 0.30),
                Color(red: 0.95, green: 0.50, blue: 0.30),
            ],
            accent: Color(red: 1.00, green: 0.62, blue: 0.30),
            bullets: [
                "Search 3M+ foods or scan a barcode",
                "Build custom foods + recipes",
                "Quick-log with one tap from anywhere",
            ]
        ),
        WhatsNewPage(
            id: "labs",
            eyebrow: "Labs",
            title: "See your numbers move",
            body: "Log testosterone, IGF-1, thyroid, lipids, and 23 more panels. Trend charts overlay your typical reference range so you can read your bloodwork at a glance.",
            icon: "testtube.2",
            gradient: [
                Color(red: 0.92, green: 0.45, blue: 0.62),
                Color(red: 0.55, green: 0.50, blue: 0.85),
            ],
            accent: Color(red: 0.92, green: 0.45, blue: 0.62),
            bullets: [
                "27 panels across 7 categories",
                "Per-panel trend chart with reference range",
                "Export as CSV for your doctor",
            ]
        ),
        WhatsNewPage(
            id: "insights",
            eyebrow: "Insights",
            title: "What's actually working?",
            body: "A 30-second daily check-in feeds the correlation engine — it tells you which days your sleep, energy, and HRV trend up on dosing weeks vs. off weeks.",
            icon: "chart.line.uptrend.xyaxis",
            gradient: [
                Color(red: 0.40, green: 0.74, blue: 0.92),
                Color(red: 0.48, green: 0.50, blue: 0.92),
            ],
            accent: Color(red: 0.40, green: 0.74, blue: 0.92),
            bullets: [
                "5-dimension daily check-in",
                "HRV / sleep / RHR vs. dose days",
                "Honest sample-size guards — no overclaiming",
            ]
        ),
        WhatsNewPage(
            id: "everywhere",
            eyebrow: "Everywhere",
            title: "Reach the app without opening it",
            body: "Siri, Action Button, Shortcuts, Spotlight, Lock Screen widget — log anything from anywhere on iOS.",
            icon: "mic.circle.fill",
            gradient: [
                Color(red: 0.36, green: 0.78, blue: 0.55),
                Color(red: 0.40, green: 0.74, blue: 0.92),
            ],
            accent: Color(red: 0.36, green: 0.78, blue: 0.55),
            bullets: [
                "\"Hey Siri, log my BPC-157\"",
                "Action Button + Shortcuts for every log",
                "Spotlight search hits your custom foods",
            ]
        ),
        WhatsNewPage(
            id: "watch",
            eyebrow: "Apple Watch",
            title: "From the wrist",
            body: "A third Watch page shows today's nutrition ring + meal streak. Quick-add water from the wrist; tap a dose row to complete it without opening your phone.",
            icon: "applewatch.radiowaves.left.and.right",
            gradient: [
                Color(red: 0.98, green: 0.78, blue: 0.20),
                Color(red: 1.00, green: 0.62, blue: 0.30),
            ],
            accent: Color(red: 0.98, green: 0.78, blue: 0.20),
            bullets: [
                "Today's calorie ring + meal streak",
                "Water quick-add (+8 / +16 / +32 oz)",
                "Tap any dose row to mark complete",
            ]
        ),
        WhatsNewPage(
            id: "tools",
            eyebrow: "Tools",
            title: "Built for the long run",
            body: "Reconstitution calculator. Travel-mode timezone detection. One-per-month streak freeze. Cycle / wash-out math. Per-protocol journal. Everything you'd want, where you'd expect it.",
            icon: "wrench.and.screwdriver.fill",
            gradient: [
                Color(red: 0.48, green: 0.50, blue: 0.92),
                Color(red: 0.36, green: 0.78, blue: 0.55),
            ],
            accent: Color(red: 0.48, green: 0.50, blue: 0.92),
            bullets: [
                "Visual reconstitution helper",
                "Travel-shift prompt at every new timezone",
                "Cycle + wash-out tracking",
            ]
        ),
    ]
}
