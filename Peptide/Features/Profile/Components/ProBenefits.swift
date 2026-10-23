import SwiftUI

/// What Atlas Pro adds, shared by every purchase surface so the paywall and
/// the trial offer can't drift apart.
///
/// Only features `StoreService` actually gates belong here. Training
/// progression, recovery, HRV and sync are free for everyone (the store page
/// says so), and listing them as Pro benefits sold buyers something they
/// already had, which App Review treats as misleading under Guideline 3.1.2.
enum ProBenefits {
    static var all: [(icon: String, title: LocalizedStringKey)] {
        [
            ("camera.viewfinder", "Log every meal from a photo, with no weekly cap"),
            ("heart.text.square.fill", "See your Biological Age and the full Biology tab"),
            ("brain.head.profile.fill", "Ask anything, get cited research — not guesswork"),
            ("text.bubble.fill", "Get a Sunday AI recap of your week"),
            ("chart.line.uptrend.xyaxis", "Unlimited protocols with schedules and reminders"),
            ("square.and.arrow.up", "Export your full history as CSV, JSON or PDF"),
        ]
    }
}
