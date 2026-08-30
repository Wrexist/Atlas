import SwiftUI

enum AppTab: String, CaseIterable {
    /// Daily action hub — doses, meals, check-in. Was `.home`
    /// (renamed in Phase 32 to be verb-forward). `selectedTab`
    /// isn't currently persisted across launches, so no
    /// migration of the prior raw value is required.
    case today
    /// Workout planning + logging. Added in the training pivot —
    /// raw value is new so older builds that don't know about it
    /// simply fall back to `.today` when their persisted state
    /// reloads.
    case train
    /// Meal logging + macros + recipes. Promoted out of the Home
    /// section in the training pivot so food gets its own
    /// top-level surface alongside training.
    case meals
    /// Biology hub — biological-age estimate, HRV/RHR/Sleep
    /// baselines, lab markers, body composition. Replaces the
    /// prior `.insights` slot in the tab bar with a Bevel-style
    /// premium surface. The analytical / correlation content
    /// (compliance trends, HealthKit correlation, labs) now lives
    /// on the Biology and Today surfaces.
    case biology

    /// User-defined habits, streaks, and the Atlas Score. Promoted into
    /// the main tab bar (replacing the demoted Library) so daily habits
    /// lead the app. The peptide reference + Protocols now open as a modal
    /// (`showLibrary`) rather than a tab.
    case habits
}

@MainActor @Observable
final class AppState {
    var selectedTab: AppTab = .today
    /// Presents the Profile + settings sheet over whichever tab is
    /// active. Profile lost its tab slot in the training pivot; routing
    /// it through a shared flag lets every tab open it from a top-right
    /// avatar button instead of forcing the user back to Today.
    var showProfile = false
    /// Presents the demoted peptide Library (database + Protocols + AI
    /// research) as an app-level modal over whichever tab is active.
    /// Library lost its tab slot when Habits was promoted; call sites that
    /// historically did `selectedTab = .library` now set this (together
    /// with `pendingProtocolList` / `pendingProtocolDeepLink`, which
    /// `PeptideListView` still consumes on appear).
    var showLibrary = false
    /// When set, the Protocols tab pushes the matching protocol's detail view
    /// onto its navigation stack and then clears this value. Used by the
    /// profile customization sheet to deep-link from a stack row to that
    /// protocol's full detail screen.
    var pendingProtocolDeepLink: UUID?
    /// When set, the Meals tab opens the food library with the matching
    /// food pre-selected on the review screen. `HomeMealsSection` is
    /// mounted only on the Meals tab (with `consumesDeepLink: true`),
    /// which clears the flag. Populated by the CoreSpotlight
    /// `NSUserActivity` handler so tapping a food result on the Home
    /// Screen's Spotlight pull-down lands the user directly on the
    /// log-this-food sheet, not just on the app's launch view.
    var pendingFoodLogID: FoodLogDeepLink?
    /// When true, the Biology tab opens the Labs view automatically
    /// on next appear and clears the flag. Used by Home's "latest lab"
    /// insight tap so the user lands one tap away from the trend
    /// chart inside the Biology surface.
    var pendingLabsOpen: Bool = false
    /// When set, the Home tab presents the matching `ProtocolEntry`'s
    /// dose-logging sheet automatically on next appear. Cleared the
    /// moment HomeView consumes it. Populated by the `peptidex://dose/<uuid>`
    /// deep-link handler so a tap on the Live Activity lands on the
    /// logging sheet in one bounce instead of dumping the user on the
    /// Home tab root and asking them to find the row.
    var pendingDoseLogEntryId: UUID?
    /// Set by the Sunday `peptidex://weekly/current` deep-link
    /// handler in `PeptideApp.onOpenURL`. HomeView consumes it on
    /// its next appear by pushing the matching detail view. Two-step
    /// (flag → consume) instead of pushing directly so the
    /// onOpenURL closure doesn't need a reference to HomeView's
    /// navigation path.
    var pendingWeeklyRecap: Bool = false
    /// When true, `PeptideListView` (the Library modal) presents
    /// `ProtocolListView` on next appear and clears the flag. Set
    /// alongside `showLibrary` by call sites that historically switched
    /// to the Library/Protocols tab — Home's cycle pill and the
    /// profile-stacks taps — so the user lands on the protocol list in
    /// one hop instead of the peptide reference root.
    var pendingProtocolList: Bool = false
}

/// Routes a `peptidex://` URL onto AppState. Extracted from
/// `PeptideApp.onOpenURL` so the mapping is unit-testable and the
/// widget/Live Activity/notification link vocabulary lives in one
/// place. Unknown schemes and hosts return false and mutate nothing —
/// a garbled custom-scheme tap from another app must not log an error
/// or open an unrelated view.
@MainActor
enum DeepLinkRouter {
    @discardableResult
    static func route(_ url: URL, appState: AppState) -> Bool {
        guard url.scheme == "peptidex" else { return false }
        switch url.host {
        case "dose":
            // Live Activity / dose-widget tap → `peptidex://dose/<uuid>`.
            // HomeView consumes the parked UUID on next appear and
            // presents the dose-logging sheet.
            guard let entryUUID = UUID(uuidString: url.lastPathComponent) else { return false }
            appState.selectedTab = .today
            appState.pendingDoseLogEntryId = entryUUID
        case "weekly":
            // Weekly recap notification → `peptidex://weekly/current`.
            appState.selectedTab = .today
            appState.pendingWeeklyRecap = true
        case "today":
            // Home-screen dose/compliance widgets → land on Today.
            appState.selectedTab = .today
        case "train":
            // Reserved for workout reminders and a future training
            // widget — lands on the Train tab, where the resume banner
            // or Start Workout CTA is the next action.
            appState.selectedTab = .train
        case "meals":
            // Nutrition widget → the Meals tab's log-entry pickers.
            appState.selectedTab = .meals
        default:
            return false
        }
        return true
    }
}

/// Discriminated identifier for the Spotlight deep-link payload.
/// Mirrors the namespacing in `FoodSpotlightService` — OFF favorites
/// carry a barcode, custom foods carry a UUID, recipes carry a
/// recipe UUID. The receiving view pattern-matches on the case to
/// resolve which path to take.
enum FoodLogDeepLink: Equatable, Hashable, Sendable {
    case openFoodFacts(barcode: String)
    case custom(id: UUID)
    case recipe(id: UUID)

    /// Parse a `peptidex-food/...` identifier emitted by the
    /// matching `FoodSpotlightService.identifier(...)` builder.
    /// Returns nil for any string that doesn't match a known
    /// scheme — caller falls through and the app opens to its
    /// default view.
    init?(spotlightIdentifier: String) {
        let parts = spotlightIdentifier.split(separator: "/")
        guard parts.count == 3,
              parts[0] == "peptidex-food"
        else { return nil }
        let payload = String(parts[2])
        switch parts[1] {
        case "custom":
            guard let uuid = UUID(uuidString: payload) else { return nil }
            self = .custom(id: uuid)
        case "off":
            // OFF barcodes are 8-14 ASCII digits. A malicious
            // NSUserActivity (Handoff sync, a crafted Spotlight
            // donation by another app) could push arbitrary strings
            // through this path otherwise; the validated shape
            // matches `OpenFoodFactsService.normalize(barcode:)`.
            guard (8...14).contains(payload.count),
                  payload.allSatisfy({ $0.isASCII && $0.isNumber })
            else { return nil }
            self = .openFoodFacts(barcode: payload)
        case "recipe":
            guard let uuid = UUID(uuidString: payload) else { return nil }
            self = .recipe(id: uuid)
        default:
            return nil
        }
    }
}
